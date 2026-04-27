import Foundation

struct VideoDTO: Decodable, Identifiable {
    let id: String
    let user_id: String
    let display_name: String
    let age: Int
    let hide_age: Bool
    let gender: String
    let asset_url: String
    let caption: String
    let comments_locked: Bool
    let comments_count: Int
    let reactions_count: Int
    let viewer_can_match_author: Bool
    let distance_km: Double?
    let session_expires_at: String?
    let created_at: String
}

struct VideoCommentDTO: Decodable, Identifiable {
    let id: String
    let video_id: String
    let user_id: String
    let display_name: String
    let parent_comment_id: String?
    let text: String
    let deleted: Bool
    let created_at: String
}

struct VideoCommentCreateRequest: Encodable {
    let text: String
    let parent_comment_id: String?
}

struct VideoReactionRequest: Encodable {
    let emoji: String
}

final class VideoService {
    static let shared = VideoService()

    private init() {}

    func feed(
        token: String?,
        targetGender: String?,
        ageMin: Int?,
        ageMax: Int?,
        sortBy: String,
        radiusKm: Double?
    ) async -> [VideoDTO] {
        guard let token else { return [] }
        var params: [String] = []
        if let targetGender, targetGender != "any" { params.append("target_gender=\(targetGender)") }
        if let ageMin { params.append("age_min=\(ageMin)") }
        if let ageMax { params.append("age_max=\(ageMax)") }
        params.append("sort_by=\(sortBy)")
        if let radiusKm { params.append("radius_km=\(String(format: "%.1f", radiusKm))") }
        let suffix = params.isEmpty ? "" : "?\(params.joined(separator: "&"))"
        do {
            let items: [VideoDTO] = try await APIClient.shared.request("/videos/feed\(suffix)", token: token)
            return items
        } catch {
            print("Video feed failed: \(error)")
            return []
        }
    }

    func byUser(userId: String, token: String?) async -> [VideoDTO] {
        guard let token else { return [] }
        do {
            let items: [VideoDTO] = try await APIClient.shared.request("/videos/user/\(userId)", token: token)
            return items
        } catch {
            print("User videos failed: \(error)")
            return []
        }
    }

    func comments(videoId: String, token: String?) async -> [VideoCommentDTO] {
        guard let token else { return [] }
        do {
            let items: [VideoCommentDTO] = try await APIClient.shared.request("/videos/\(videoId)/comments", token: token)
            return items
        } catch {
            print("Comments load failed: \(error)")
            return []
        }
    }

    func addComment(videoId: String, text: String, parentCommentId: String? = nil, token: String?) async -> VideoCommentDTO? {
        guard let token else { return nil }
        let payload = VideoCommentCreateRequest(text: text, parent_comment_id: parentCommentId)
        do {
            let item: VideoCommentDTO = try await APIClient.shared.request(
                "/videos/\(videoId)/comments",
                method: "POST",
                token: token,
                body: payload
            )
            return item
        } catch {
            print("Add comment failed: \(error)")
            return nil
        }
    }

    func deleteComment(commentId: String, token: String?) async {
        guard let token else { return }
        do {
            let _: Empty = try await APIClient.shared.request(
                "/videos/comments/\(commentId)",
                method: "DELETE",
                token: token
            )
        } catch {
            print("Delete comment failed: \(error)")
        }
    }

    func react(videoId: String, emoji: String, token: String?) async {
        guard let token else { return }
        do {
            let _: Empty = try await APIClient.shared.request(
                "/videos/\(videoId)/reactions",
                method: "POST",
                token: token,
                body: VideoReactionRequest(emoji: emoji)
            )
        } catch {
            print("Reaction failed: \(error)")
        }
    }

    func deleteVideo(videoId: String, token: String?) async {
        guard let token else { return }
        do {
            let _: Empty = try await APIClient.shared.request(
                "/videos/\(videoId)",
                method: "DELETE",
                token: token
            )
        } catch {
            print("Delete video failed: \(error)")
        }
    }
}

private struct Empty: Decodable {
    let ok: Bool?
}
