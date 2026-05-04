import Foundation
import SwiftUI
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {
    @AppStorage("auth_token") private var authToken: String = ""
    @AppStorage("auth_user_id") private var authUserId: String = ""
    @AppStorage("auth_provider") private var authProvider: String = ""
    @AppStorage("mock_apple_sub") private var mockAppleSub: String = ""

    @Published var isLoading: Bool = false
    @Published var authError: String?

    var isAuthenticated: Bool {
        !authToken.isEmpty && !authUserId.isEmpty
    }

    func signInMock(provider: String = "mock") {
        if mockAppleSub.isEmpty {
            mockAppleSub = "mock:\(UUID().uuidString)"
        }
        isLoading = true
        authError = nil
        Task {
            if let response = await AuthService.shared.signInWithApple(idToken: mockAppleSub) {
                authToken = response.access_token
                authUserId = response.user_id
                authProvider = provider
                await registerDeviceIfNeeded()
            } else {
                authError = L10n.text("Не удалось войти в demo mode", "Failed to sign in to demo mode")
            }
            isLoading = false
        }
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
            await registerDeviceIfNeeded()
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

    private func registerDeviceIfNeeded() async {
        guard let deviceToken = UserDefaults.standard.string(forKey: "apns_device_token"), !deviceToken.isEmpty else { return }
        await DeviceService.shared.register(token: deviceToken, authToken: authToken)
    }
}
