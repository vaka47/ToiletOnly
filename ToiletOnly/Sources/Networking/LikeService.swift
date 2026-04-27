import Foundation

struct LikeActionRequest: Encodable {
    let to_user_id: String
    let action: String
    let message: String?
}

struct MatchOutDTO: Decodable {
    let id: String
    let user_a_id: String
    let user_b_id: String
    let status: String
    let my_is_kept: Bool
    let other_is_kept: Bool
    let my_sessions_left: Int
    let other_sessions_left: Int
}

struct IncomingLikeDTO: Decodable, Identifiable {
    let id: String
    let from_user_id: String
    let display_name: String
    let age: Int
    let hide_age: Bool
    let gender: String
    let toilet_selfie_url: String
    let photos: [String]
    let bio_ai: String
    let bio_text: String
    let interests: [String]
    let session_video_url: String?
    let is_online_toilet: Bool
    let session_expires_at: String?
    let like_type: String
    let message: String?
    let created_at: String
}

final class LikeService {
    static let shared = LikeService()

    private init() {}

    func send(to userId: String, action: String, message: String? = nil, token: String?) async -> MatchOutDTO? {
        guard let token else { return nil }
        let payload = LikeActionRequest(to_user_id: userId, action: action, message: message)
        do {
            let result: MatchOutDTO? = try await APIClient.shared.request(
                "/likes",
                method: "POST",
                token: token,
                body: payload
            )
            return result
        } catch {
            print("Like action failed: \(error)")
            return nil
        }
    }

    func incoming(token: String?) async -> [IncomingLikeDTO] {
        guard let token else { return [] }
        do {
            let items: [IncomingLikeDTO] = try await APIClient.shared.request(
                "/likes/incoming",
                token: token
            )
            return items
        } catch {
            print("Incoming likes failed: \(error)")
            return []
        }
    }
}
