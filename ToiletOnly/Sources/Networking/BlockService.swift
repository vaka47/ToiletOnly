import Foundation

struct BlockRequest: Encodable {
    let blocked_user_id: String
}

struct BlockResponse: Decodable, Identifiable {
    var id: String { blocked_user_id }
    let blocker_id: String
    let blocked_user_id: String
}

final class BlockService {
    static let shared = BlockService()

    private init() {}

    func block(userId: String, token: String?) async {
        guard let token else { return }
        let body = BlockRequest(blocked_user_id: userId)
        do {
            let _: BlockResponse = try await APIClient.shared.request("/blocks", method: "POST", token: token, body: body)
        } catch {
            print("Block failed: \(error)")
        }
    }

    func list(token: String?) async -> [BlockResponse] {
        guard let token else { return [] }
        do {
            let items: [BlockResponse] = try await APIClient.shared.request("/blocks", token: token)
            return items
        } catch {
            print("Block list failed: \(error)")
            return []
        }
    }

    func unblock(userId: String, token: String?) async {
        guard let token else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.request("/blocks/\(userId)", method: "DELETE", token: token)
        } catch {
            print("Unblock failed: \(error)")
        }
    }
}

private struct EmptyResponse: Decodable {}
