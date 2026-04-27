import Foundation

struct DeviceTokenPayload: Encodable {
    let token: String
    let platform: String
}

final class DeviceService {
    static let shared = DeviceService()

    private init() {}

    func register(token: String, authToken: String?) async {
        guard let authToken else { return }
        let payload = DeviceTokenPayload(token: token, platform: "ios")
        do {
            let _: EmptyResponse = try await APIClient.shared.request("/devices/register", method: "POST", token: authToken, body: payload)
        } catch {
            print("Device register failed: \(error)")
        }
    }
}

private struct EmptyResponse: Decodable {}
