import Foundation
import SwiftUI

@MainActor
final class DatingViewModel: ObservableObject {
    @Published private(set) var profiles: [DatingProfile]
    @Published private(set) var matches: [DatingMatch]
    @Published var ageFilter: AgeFilter
    @Published var superLikeError: String?
    private var currentIndex: Int = 0
    // Daily limit for superlikes (can be extended with subscription in future)
    private let dailySuperLikeLimit = 5
    private let superLikeDateKey = "toilet_superlike_date"
    private let superLikeCountKey = "toilet_superlike_count"

    init() {
        self.profiles = Self.sampleProfiles
        self.matches = []
        self.ageFilter = .default
    }

    var currentProfile: DatingProfile? {
        filteredProfiles.indices.contains(currentIndex) ? filteredProfiles[currentIndex] : nil
    }

    var filteredProfiles: [DatingProfile] {
        profiles.filter { profile in
            profile.age >= ageFilter.minAge && profile.age <= ageFilter.maxAge
        }
    }

    var activeMatches: [DatingMatch] {
        matches.filter { $0.status != .expired }
    }

    var remainingSuperLikesToday: Int {
        let today = Calendar.current.startOfDay(for: Date())
        if let savedDate = UserDefaults.standard.object(forKey: superLikeDateKey) as? Date, savedDate >= today {
            return max(0, dailySuperLikeLimit - UserDefaults.standard.integer(forKey: superLikeCountKey))
        }
        return dailySuperLikeLimit
    }

    func loadFeed(token: String?) async {
        let items = await ProfileService.shared.fetchFeed(
            token: token,
            minAge: ageFilter.minAge,
            maxAge: ageFilter.maxAge,
            showNearby: ageFilter.showNearby,
            targetGender: ageFilter.targetGender,
            radiusKm: ageFilter.showNearby ? ageFilter.radiusKm : nil
        )
        guard !items.isEmpty else { return }
        let sessionItems = items.filter { dto in
            guard let url = dto.session_video_url else { return false }
            return !url.isEmpty
        }
        let sourceItems = sessionItems.isEmpty ? items : sessionItems
        profiles = sourceItems.map { dto in
            let bio = dto.bio_text.isEmpty ? dto.bio_ai : dto.bio_text
            return DatingProfile(
                id: UUID(uuidString: dto.user_id) ?? UUID(),
                remoteUserId: dto.user_id,
                name: dto.display_name,
                age: dto.age,
                hideAge: dto.hide_age,
                gender: dto.gender,
                bio: bio,
                photos: [dto.toilet_selfie_url] + dto.photos,
                sessionVideoURL: dto.session_video_url,
                toiletSelfieIndex: 0,
                tags: dto.interests,
                isOnline: dto.is_online_toilet,
                distanceKm: dto.distance_km,
                sessionExpiresAt: Self.parseDate(dto.session_expires_at)
            )
        }
        currentIndex = 0
    }

    func advance() {
        if currentIndex + 1 < filteredProfiles.count {
            currentIndex += 1
        } else {
            currentIndex = 0
        }
    }

    func passCurrent(token: String?) async {
        guard let profile = currentProfile else { return }
        await pass(profile: profile, token: token)
        advance()
    }

    func likeCurrent(token: String?) async -> DatingMatch? {
        guard let profile = currentProfile else { return nil }
        let match = await like(profile: profile, token: token)
        advance()
        return match
    }

    func superLikeCurrent(token: String?, message: String? = nil) async -> DatingMatch? {
        guard let profile = currentProfile else { return nil }
        let match = await superLike(profile: profile, token: token, message: message)
        if match != nil || superLikeError == nil {
            advance()
        }
        return match
    }

    func pass(profile: DatingProfile, token: String?) async {
        _ = await LikeService.shared.send(to: profile.remoteUserId, action: "pass", token: token)
    }

    func like(profile: DatingProfile, token: String?) async -> DatingMatch? {
        let dto = await LikeService.shared.send(to: profile.remoteUserId, action: "like", token: token)
        return (dto != nil) ? createMatchIfNeeded(with: profile, backend: dto) : nil
    }

    func superLike(profile: DatingProfile, token: String?, message: String? = nil) async -> DatingMatch? {
        // Enforce daily limit for superlikes
        let today = Calendar.current.startOfDay(for: Date())
        if let savedDate = UserDefaults.standard.object(forKey: superLikeDateKey) as? Date, savedDate >= today {
            let count = UserDefaults.standard.integer(forKey: superLikeCountKey)
            if count >= dailySuperLikeLimit {
                superLikeError = L10n.text("Суперлайк на сегодня исчерпан", "Daily superlike limit reached")
                return nil
            }
        } else {
            // Reset count for new day
            UserDefaults.standard.set(today, forKey: superLikeDateKey)
            UserDefaults.standard.set(0, forKey: superLikeCountKey)
        }
        let dto = await LikeService.shared.send(
            to: profile.remoteUserId,
            action: "superlike",
            message: message?.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token
        )
        if dto == nil {
            superLikeError = L10n.text("Суперлайк недоступен в этой сессии.", "Superlike is unavailable in this session.")
            return nil
        }
        let match = createMatchIfNeeded(with: profile, backend: dto)
        // Increment daily counter after a successful superlike
        let newCount = UserDefaults.standard.integer(forKey: superLikeCountKey) + 1
        UserDefaults.standard.set(newCount, forKey: superLikeCountKey)
        // Clear any previous error
        superLikeError = nil
        return match
    }

    func keepMatch(_ match: DatingMatch, token: String?) async {
        guard let token else { return }
        let updated = await MatchService.shared.keep(matchId: match.id.uuidString, token: token)
        guard let updated else { return }
        guard let index = matches.firstIndex(of: match) else { return }
        matches[index] = DatingMatch.fromBackend(updated, profile: matches[index].profile, createdAt: matches[index].createdAt)
    }

    func consumeSessionForPendingMatches() {
        var updated: [DatingMatch] = []
        for match in matches {
            var item = match
            if !item.myIsKept {
                item.mySessionsLeft = max(0, item.mySessionsLeft - 1)
            }
            item.status = MatchStatus.fromBackend(
                item.status.rawValue,
                myIsKept: item.myIsKept,
                otherIsKept: item.otherIsKept,
                mySessionsLeft: item.mySessionsLeft,
                otherSessionsLeft: item.otherSessionsLeft
            )
            updated.append(item)
        }
        matches = updated
        removeExpiredMatches()
    }

    func block(profile: DatingProfile) {
        profiles.removeAll { $0.id == profile.id }
        matches.removeAll { $0.profile.id == profile.id }
        if currentIndex >= filteredProfiles.count {
            currentIndex = max(0, filteredProfiles.count - 1)
        }
    }

    private func createMatchIfNeeded(with profile: DatingProfile, backend: MatchOutDTO?) -> DatingMatch? {
        guard let backend else { return nil }
        let backendId = UUID(uuidString: backend.id) ?? UUID()
        if let existing = matches.first(where: { $0.id == backendId && $0.status != .expired }) {
            let refreshed = DatingMatch.fromBackend(backend, profile: existing.profile, createdAt: existing.createdAt)
            if let existingIndex = matches.firstIndex(where: { $0.id == backendId }) {
                matches[existingIndex] = refreshed
            }
            return refreshed
        }
        let match = DatingMatch.fromBackend(backend, profile: profile, createdAt: Date())
        matches.insert(match, at: 0)
        return match
    }

    private func removeExpiredMatches() {
        matches.removeAll { $0.status == .expired }
    }

    private static var sampleProfiles: [DatingProfile] {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true {
            return [
                DatingProfile(
                    id: UUID(),
                    remoteUserId: UUID().uuidString,
                    name: "Лера",
                    age: 22,
                    hideAge: false,
                    gender: "female",
                    bio: "Собираю мемы, гоняю ночные чаты и ищу человека, который тоже не боится странных вопросов.",
                    photos: ["toilet_1", "photo_1", "photo_2"],
                    sessionVideoURL: nil,
                    toiletSelfieIndex: 0,
                    tags: ["мемы", "кино", "сарказм"],
                    isOnline: true,
                    distanceKm: 2.1,
                    sessionExpiresAt: Date().addingTimeInterval(11 * 60)
                ),
                DatingProfile(
                    id: UUID(),
                    remoteUserId: UUID().uuidString,
                    name: "Даня",
                    age: 28,
                    hideAge: false,
                    gender: "male",
                    bio: "Здесь только по делу: быстро отвечаю, люблю дерзкий юмор и честные вайбы.",
                    photos: ["toilet_2", "photo_3", "photo_4"],
                    sessionVideoURL: nil,
                    toiletSelfieIndex: 0,
                    tags: ["флирт", "спорт", "техно"],
                    isOnline: true,
                    distanceKm: 5.4,
                    sessionExpiresAt: Date().addingTimeInterval(7 * 60)
                ),
                DatingProfile(
                    id: UUID(),
                    remoteUserId: UUID().uuidString,
                    name: "Саша",
                    age: 31,
                    hideAge: false,
                    gender: "female",
                    bio: "Если ты здесь, значит время для самых странных, но искренних знакомств.",
                    photos: ["toilet_3", "photo_5", "photo_6"],
                    sessionVideoURL: nil,
                    toiletSelfieIndex: 0,
                    tags: ["ирония", "музыка", "ночь"],
                    isOnline: false,
                    distanceKm: nil,
                    sessionExpiresAt: nil
                )
            ]
        }

        return [
            DatingProfile(
                id: UUID(),
                remoteUserId: UUID().uuidString,
                name: "Ava",
                age: 23,
                hideAge: false,
                gender: "female",
                bio: "Collecting memes, starting reckless late-night chats, and looking for someone who is good with weird questions.",
                photos: ["toilet_1", "photo_1", "photo_2"],
                sessionVideoURL: nil,
                toiletSelfieIndex: 0,
                tags: ["memes", "movies", "sarcasm"],
                isOnline: true,
                distanceKm: 1.9,
                sessionExpiresAt: Date().addingTimeInterval(11 * 60)
            ),
            DatingProfile(
                id: UUID(),
                remoteUserId: UUID().uuidString,
                name: "Miles",
                age: 29,
                hideAge: false,
                gender: "male",
                bio: "Fast replies, sharp humor, and zero patience for boring small talk. If the vibe is real, I am in.",
                photos: ["toilet_2", "photo_3", "photo_4"],
                sessionVideoURL: nil,
                toiletSelfieIndex: 0,
                tags: ["flirting", "fitness", "techno"],
                isOnline: true,
                distanceKm: 4.8,
                sessionExpiresAt: Date().addingTimeInterval(7 * 60)
            ),
            DatingProfile(
                id: UUID(),
                remoteUserId: UUID().uuidString,
                name: "Chloe",
                age: 31,
                hideAge: false,
                gender: "female",
                bio: "If you are here, we probably both like the kind of chemistry that starts strange and turns honest fast.",
                photos: ["toilet_3", "photo_5", "photo_6"],
                sessionVideoURL: nil,
                toiletSelfieIndex: 0,
                tags: ["wit", "music", "night owl"],
                isOnline: false,
                distanceKm: nil,
                sessionExpiresAt: nil
            )
        ]
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic = ISO8601DateFormatter()

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return iso8601WithFractional.date(from: raw) ?? iso8601Basic.date(from: raw)
    }
}
