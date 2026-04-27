import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Toilet Dating", "Toilet Dating"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.ink)
                    Text(L10n.text("Вход через Apple ID.", "Sign in with Apple ID."))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            Task { await viewModel.signInWithApple(credential: credential) }
                        }
                    case .failure:
                        viewModel.authError = L10n.text("Apple ID отменен", "Apple ID sign-in canceled")
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .padding(.horizontal, 24)

                Button(viewModel.isLoading ? L10n.text("Входим...", "Signing in...") : L10n.text("Войти в мок-режиме", "Sign in mock mode")) {
                    viewModel.signInMock(provider: "mock")
                }
                .buttonStyle(GhostButtonStyle())
                .padding(.horizontal, 24)

                if let error = viewModel.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.bottom, 40)
        }
    }
}
