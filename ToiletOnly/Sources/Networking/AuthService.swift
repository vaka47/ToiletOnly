import Foundation

struct AuthRequestPayload: Encodable {
    let id_token: String
}

struct AuthResponsePayload: Decodable {
    let access_token: String
    let user_id: String
}

final class AuthService {
    static let shared = AuthService()

    private init() {}

    func signInWithApple(idToken: String) async -> AuthResponsePayload? {
        do {
            let payload = AuthRequestPayload(id_token: idToken)
            let response: AuthResponsePayload = try await APIClient.shared.request("/auth/apple", method: "POST", body: payload)
            return response
        } catch {
            print("Auth failed: \(error)")
            return nil
        }
    }
}
