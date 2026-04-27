import Foundation
import SwiftUI
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {
    @AppStorage("auth_token") private var authToken: String = ""
    @AppStorage("auth_user_id") private var authUserId: String = ""
    @AppStorage("auth_provider") private var authProvider: String = ""

    @Published var isLoading: Bool = false
    @Published var authError: String?

    var isAuthenticated: Bool {
        !authToken.isEmpty && !authUserId.isEmpty
    }

    func signInMock(provider: String = "apple") {
        authToken = "mock_\(UUID().uuidString)"
        authUserId = UUID().uuidString
        authProvider = provider
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            authError = "Не удалось получить токен Apple ID"
            return
        }
        isLoading = true
        if let response = await AuthService.shared.signInWithApple(idToken: token) {
            authToken = response.access_token
            authUserId = response.user_id
            authProvider = "apple"
        } else {
            authError = "Ошибка авторизации"
        }
        isLoading = false
    }

    func signOut() {
        authToken = ""
        authUserId = ""
        authProvider = ""
    }

    func token() -> String? {
        authToken.isEmpty ? nil : authToken
    }

    func userId() -> String? {
        authUserId.isEmpty ? nil : authUserId
    }
}
