import Foundation

struct MatchListItemDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let my_is_kept: Bool
    let other_is_kept: Bool
    let my_sessions_left: Int
    let other_sessions_left: Int
    let other_user_id: String
    let display_name: String
    let age: Int
    let hide_age: Bool
    let gender: String
    let toilet_selfie_url: String
    let is_online_toilet: Bool
    let session_expires_at: String?
    let last_message: String?
    let last_message_at: String?
}

final class MatchService {
    static let shared = MatchService()

    private init() {}

    func keep(matchId: String, token: String?) async -> MatchOutDTO? {
        guard let token else { return nil }
        do {
            let payload = ["match_id": matchId]
            let result: MatchOutDTO = try await APIClient.shared.request(
                "/matches/keep",
                method: "POST",
                token: token,
                body: payload
            )
            return result
        } catch {
            print("Keep match failed: \(error)")
            return nil
        }
    }

    func fetch(matchId: String, token: String?) async -> MatchOutDTO? {
        guard let token else { return nil }
        do {
            let result: MatchOutDTO = try await APIClient.shared.request(
                "/matches/\(matchId)",
                token: token
            )
            return result
        } catch {
            print("Fetch match failed: \(error)")
            return nil
        }
    }

    func list(token: String?) async -> [MatchListItemDTO] {
        guard let token else { return [] }
        do {
            let result: [MatchListItemDTO] = try await APIClient.shared.request(
                "/matches/list",
                token: token
            )
            return result
        } catch {
            print("List matches failed: \(error)")
            return []
        }
    }

    func delete(matchId: String, token: String?) async -> Bool {
        guard let token else { return false }
        do {
            let _: EmptyResponse = try await APIClient.shared.request(
                "/matches/\(matchId)",
                method: "DELETE",
                token: token
            )
            return true
        } catch {
            print("Delete match failed: \(error)")
            return false
        }
    }
}

private struct EmptyResponse: Decodable {
    let ok: Bool?
}
