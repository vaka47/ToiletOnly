import Foundation

struct PingRequestPayload: Encodable {
    let target_user_id: String
    let message: String?
}

final class PingService {
    static let shared = PingService()

    private init() {}

    func send(targetUserId: String, message: String?, token: String?) async {
        guard let token else { return }
        let payload = PingRequestPayload(target_user_id: targetUserId, message: message)
        do {
            let _: EmptyResponse = try await APIClient.shared.request("/ping", method: "POST", token: token, body: payload)
        } catch {
            print("Ping failed: \(error)")
        }
    }
}

private struct EmptyResponse: Decodable {}
