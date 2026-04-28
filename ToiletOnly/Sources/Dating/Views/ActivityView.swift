import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var items: [ActivityItemDTO] = []
    @State private var selectedProfile: DatingProfile?
    @State private var selectedMatch: DatingMatch?
    @State private var processingUserId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if items.isEmpty {
                    AppCard {
                        VStack(spacing: 10) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 28))
                                .foregroundColor(AppTheme.coral)
                            Text(L10n.text("Пока пусто", "Nothing yet"))
                                .font(.headline)
                                .foregroundColor(AppTheme.ink)
                            Text(L10n.text("Здесь появятся лайки, суперлайки, пинги и реакции на видео.", "Likes, superlikes, pings, and video reactions will appear here."))
                                .font(.callout)
                                .foregroundColor(AppTheme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                    }
                    .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(items) { item in
                            AppCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ActivityAvatar(urlString: item.actor_toilet_selfie_url)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(title(for: item))
                                                .font(.headline)
                                                .foregroundColor(AppTheme.ink)
                                            Text(relativeTime(item.created_at))
                                                .font(.caption)
                                                .foregroundColor(AppTheme.muted)
                                        }
                                        Spacer()
                                        eventBadge(for: item.event_type)
                                    }

                                    if let message = item.message, !message.isEmpty {
                                        Text(message)
                                            .font(.callout)
                                            .foregroundColor(AppTheme.muted)
                                    }

                                    HStack(spacing: 10) {
                                        Button(L10n.text("Профиль", "Profile")) {
                                            selectedProfile = mapProfile(from: item)
                                        }
                                        .buttonStyle(PrimaryButtonStyle(tint: AppTheme.sky))

                                        if canLikeBack(item) {
                                            Button(processingUserId == item.actor_user_id ? L10n.text("Отправка...", "Sending...") : L10n.text("Лайк в ответ", "Like back")) {
                                                Task { await likeBack(item) }
                                            }
                                            .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral, useGradient: true))
                                            .disabled(processingUserId == item.actor_user_id)
                                        }

                                        if let match = mapMatch(from: item) {
                                            Button(L10n.text("Чат", "Chat")) {
                                                selectedMatch = match
                                            }
                                            .buttonStyle(GhostButtonStyle())
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
            .padding(.top, 10)
        }
        .sheet(item: $selectedProfile) { profile in
            ProfileInfoView(profile: profile)
                .environmentObject(authViewModel)
        }
        .sheet(item: $selectedMatch) { match in
            ChatView(match: match) {}
                .environmentObject(authViewModel)
        }
        .task {
            await ActivityService.shared.markRead(scope: "activity", token: authViewModel.token())
            await reload()
        }
    }

    private var header: some View {
        AppCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Активность", "Activity"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.ink)
                    Text(L10n.text("Все сигналы интереса в одном месте.", "All signals of interest in one place."))
                        .font(.callout)
                        .foregroundColor(AppTheme.muted)
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.74))
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundColor(AppTheme.ink)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func reload() async {
        items = await ActivityService.shared.feed(token: authViewModel.token())
    }

    private func title(for item: ActivityItemDTO) -> String {
        switch item.event_type {
        case "superlike_received":
            return L10n.text("\(item.actor_display_name) отправил суперлайк", "\(item.actor_display_name) sent a superlike")
        case "like_received":
            return L10n.text("\(item.actor_display_name) поставил лайк", "\(item.actor_display_name) liked you")
        case "ping_received":
            return L10n.text("\(item.actor_display_name) зовет в онлайн", "\(item.actor_display_name) wants you online")
        case "video_comment":
            return L10n.text("\(item.actor_display_name) прокомментировал видео", "\(item.actor_display_name) commented on your video")
        case "video_reaction":
            return L10n.text("\(item.actor_display_name) отреагировал на видео", "\(item.actor_display_name) reacted to your video")
        default:
            return item.actor_display_name
        }
    }

    private func eventBadge(for eventType: String) -> some View {
        let pair: (String, Color) = {
            switch eventType {
            case "superlike_received":
                return (L10n.text("Супер", "Super"), AppTheme.mango)
            case "like_received":
                return (L10n.text("Лайк", "Like"), AppTheme.coral)
            case "ping_received":
                return (L10n.text("Пинг", "Ping"), AppTheme.sky)
            case "video_comment":
                return (L10n.text("Коммент", "Comment"), AppTheme.mint)
            case "video_reaction":
                return (L10n.text("Реакция", "Reaction"), AppTheme.sky)
            default:
                return ("", AppTheme.sky)
            }
        }()
        return AccentTag(title: pair.0, tint: pair.1)
    }

    private func relativeTime(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func mapProfile(from item: ActivityItemDTO) -> DatingProfile {
        DatingProfile(
            id: UUID(uuidString: item.actor_user_id) ?? UUID(),
            remoteUserId: item.actor_user_id,
            name: item.actor_display_name,
            age: item.actor_age,
            hideAge: false,
            gender: item.actor_gender,
            bio: item.actor_bio_text.isEmpty ? item.actor_bio_ai : item.actor_bio_text,
            photos: [item.actor_toilet_selfie_url] + item.actor_photos,
            sessionVideoURL: item.actor_session_video_url,
            toiletSelfieIndex: 0,
            tags: item.actor_interests,
            isOnline: item.actor_is_online_toilet,
            distanceKm: nil,
            sessionExpiresAt: parseDate(item.actor_session_expires_at)
        )
    }

    private func mapMatch(from item: ActivityItemDTO) -> DatingMatch? {
        guard let matchId = item.match_id else { return nil }
        return DatingMatch(
            id: UUID(uuidString: matchId) ?? UUID(),
            profile: mapProfile(from: item),
            status: .pendingKeep,
            mySessionsLeft: 2,
            otherSessionsLeft: 2,
            myIsKept: false,
            otherIsKept: false,
            createdAt: parseDate(item.created_at) ?? Date()
        )
    }

    private func canLikeBack(_ item: ActivityItemDTO) -> Bool {
        item.match_id == nil && (item.event_type == "like_received" || item.event_type == "superlike_received")
    }

    private func likeBack(_ item: ActivityItemDTO) async {
        processingUserId = item.actor_user_id
        defer { processingUserId = nil }
        let result = await LikeService.shared.send(
            to: item.actor_user_id,
            action: "like",
            token: authViewModel.token()
        )
        guard let result else { return }
        selectedMatch = DatingMatch.fromBackend(result, profile: mapProfile(from: item), createdAt: Date())
        await reload()
    }
}

private struct ActivityAvatar: View {
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 54, height: 54)
        }
    }
}
