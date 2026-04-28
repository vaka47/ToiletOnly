import Foundation

struct ActivityItemDTO: Decodable, Identifiable {
    let id: String
    let event_type: String
    let actor_user_id: String
    let actor_display_name: String
    let actor_age: Int
    let actor_gender: String
    let actor_toilet_selfie_url: String
    let actor_photos: [String]
    let actor_bio_ai: String
    let actor_bio_text: String
    let actor_interests: [String]
    let actor_session_video_url: String?
    let actor_is_online_toilet: Bool
    let actor_session_expires_at: String?
    let message: String?
    let match_id: String?
    let video_id: String?
    let created_at: String
}

struct InboxSummaryDTO: Decodable {
    let unread_activity_count: Int
    let unread_likes_count: Int
    let unread_matches_count: Int
}

struct InboxReadRequest: Encodable {
    let scope: String
}

final class ActivityService {
    static let shared = ActivityService()

    private init() {}

    func feed(token: String?, limit: Int = 50) async -> [ActivityItemDTO] {
        guard let token else { return [] }
        do {
            let items: [ActivityItemDTO] = try await APIClient.shared.request(
                "/activity/feed?limit=\(limit)",
                token: token
            )
            return items
        } catch {
            print("Activity feed failed: \(error)")
            return []
        }
    }

    func summary(token: String?) async -> InboxSummaryDTO {
        guard let token else {
            return InboxSummaryDTO(unread_activity_count: 0, unread_likes_count: 0, unread_matches_count: 0)
        }
        do {
            let item: InboxSummaryDTO = try await APIClient.shared.request("/activity/summary", token: token)
            return item
        } catch {
            print("Inbox summary failed: \(error)")
            return InboxSummaryDTO(unread_activity_count: 0, unread_likes_count: 0, unread_matches_count: 0)
        }
    }

    func markRead(scope: String, token: String?) async {
        guard let token else { return }
        do {
            let _: EmptyReadResponse = try await APIClient.shared.request(
                "/activity/read",
                method: "POST",
                token: token,
                body: InboxReadRequest(scope: scope)
            )
        } catch {
            print("Inbox read failed: \(error)")
        }
    }
}

private struct EmptyReadResponse: Decodable {
    let ok: Bool?
    let scope: String?
}
