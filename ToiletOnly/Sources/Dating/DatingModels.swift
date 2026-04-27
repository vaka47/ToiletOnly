import Foundation

struct DatingProfile: Identifiable, Hashable {
    let id: UUID
    let remoteUserId: String
    var name: String
    var age: Int
    var hideAge: Bool
    var gender: String
    var bio: String
    var photos: [String]
    var sessionVideoURL: String?
    var toiletSelfieIndex: Int
    var tags: [String]
    var isOnline: Bool
    var distanceKm: Double?
    var sessionExpiresAt: Date?
}

struct DatingMatch: Identifiable, Hashable {
    let id: UUID
    var profile: DatingProfile
    var status: MatchStatus
    var mySessionsLeft: Int
    var otherSessionsLeft: Int
    var myIsKept: Bool
    var otherIsKept: Bool
    var createdAt: Date
}

enum MatchStatus: String, CaseIterable {
    case pendingKeep
    case confirmKeep
    case awaitingOther
    case kept
    case expired
}

struct AgeFilter: Hashable {
    var minAge: Int
    var maxAge: Int
    var targetGender: String
    var radiusKm: Double
    var showNearby: Bool
    var videoSort: String

    static let `default` = AgeFilter(
        minAge: 18,
        maxAge: 35,
        targetGender: "any",
        radiusKm: 50,
        showNearby: true,
        videoSort: "popular"
    )
}

extension MatchStatus {
    static func fromBackend(
        _ status: String,
        myIsKept: Bool,
        otherIsKept: Bool,
        mySessionsLeft: Int,
        otherSessionsLeft: Int
    ) -> MatchStatus {
        if status == "kept" || (myIsKept && otherIsKept) {
            return .kept
        }
        if status == "expired" || (!myIsKept && mySessionsLeft <= 0) || (!otherIsKept && otherSessionsLeft <= 0) {
            return .expired
        }
        if otherIsKept && !myIsKept {
            return .confirmKeep
        }
        if myIsKept && !otherIsKept {
            return .awaitingOther
        }
        return .pendingKeep
    }
}

extension DatingMatch {
    static func fromBackend(_ dto: MatchOutDTO, profile: DatingProfile, createdAt: Date) -> DatingMatch {
        DatingMatch(
            id: UUID(uuidString: dto.id) ?? UUID(),
            profile: profile,
            status: MatchStatus.fromBackend(
                dto.status,
                myIsKept: dto.my_is_kept,
                otherIsKept: dto.other_is_kept,
                mySessionsLeft: dto.my_sessions_left,
                otherSessionsLeft: dto.other_sessions_left
            ),
            mySessionsLeft: dto.my_sessions_left,
            otherSessionsLeft: dto.other_sessions_left,
            myIsKept: dto.my_is_kept,
            otherIsKept: dto.other_is_kept,
            createdAt: createdAt
        )
    }
}
