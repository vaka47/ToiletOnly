import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("Toilet Dating", "Toilet Dating"))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.ink)
                    Text(
                        L10n.text(
                            "Сессионные знакомства с реальным presence-gate. Не свайп-ферма, а живой локальный social layer.",
                            "Session-based dating with a real-world presence gate. Not a swipe farm, but a live local social layer."
                        )
                    )
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.muted)
                    .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)

                AppCard {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Text(L10n.text("Private beta", "Private beta"))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(AppTheme.coral)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.coral.opacity(0.12))
                                .clipShape(Capsule())

                            Text(L10n.text("Live session social", "Live session social"))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(AppTheme.sky)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.sky.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Text(L10n.text("Вход", "Sign in"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.ink)

                        Text(L10n.text("Apple ID для реального входа. Mock mode нужен для быстрого demo-прогона и интерфейсной проверки.", "Use Apple ID for the real app. Mock mode is for a fast demo walkthrough and UI verification."))
                            .font(.subheadline)
                            .foregroundColor(AppTheme.muted)

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
                        .frame(height: 54)

                        Button(viewModel.isLoading ? L10n.text("Входим...", "Signing in...") : L10n.text("Войти в mock mode", "Sign in mock mode")) {
                            viewModel.signInMock(provider: "mock")
                        }
                        .buttonStyle(GhostButtonStyle())

                        if let error = viewModel.authError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.bottom, 40)
        }
    }
}
