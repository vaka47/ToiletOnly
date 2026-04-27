import Foundation

struct MessageDTO: Decodable {
    let id: String
    let match_id: String
    let sender_id: String
    let text: String
    let created_at: String
}

struct MessageCreateRequest: Encodable {
    let text: String
}

final class MessageService {
    static let shared = MessageService()

    private init() {}

    func fetch(matchId: String, token: String?) async -> [MessageDTO] {
        guard let token else { return [] }
        do {
            let items: [MessageDTO] = try await APIClient.shared.request("/matches/\(matchId)/messages", token: token)
            return items
        } catch {
            print("Fetch messages failed: \(error)")
            return []
        }
    }

    func post(matchId: String, token: String?, text: String) async {
        guard let token else { return }
        let payload = MessageCreateRequest(text: text)
        do {
            let _: MessageDTO = try await APIClient.shared.request("/matches/\(matchId)/messages", method: "POST", token: token, body: payload)
        } catch {
            print("Post message failed: \(error)")
        }
    }
}
