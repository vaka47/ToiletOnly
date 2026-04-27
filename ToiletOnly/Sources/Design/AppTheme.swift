import SwiftUI
import Foundation

enum AppTheme {
    static let ink = Color(red: 0.10, green: 0.11, blue: 0.16)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let coral = Color(red: 0.96, green: 0.38, blue: 0.34)
    static let mango = Color(red: 0.98, green: 0.72, blue: 0.33)
    static let mint = Color(red: 0.20, green: 0.72, blue: 0.60)
    static let sky = Color(red: 0.22, green: 0.54, blue: 0.95)
    static let panel = Color.white.opacity(0.78)
    static let shadow = Color.black.opacity(0.10)
    static let muted = Color.black.opacity(0.56)

    static let accentGradient = LinearGradient(
        colors: [coral, mango],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let actionGradient = LinearGradient(
        colors: [sky, mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.99, blue: 0.98),
                    Color(red: 0.98, green: 0.95, blue: 0.90),
                    Color(red: 0.93, green: 0.96, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.coral.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 28)
                .offset(x: -170, y: -240)

            Circle()
                .fill(AppTheme.sky.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 32)
                .offset(x: 160, y: 250)

            RoundedRectangle(cornerRadius: 48)
                .fill(AppTheme.mint.opacity(0.08))
                .frame(width: 360, height: 200)
                .rotationEffect(.degrees(-12))
                .offset(x: 150, y: -10)
        }
    }
}

struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppTheme.panel)
                    .shadow(color: AppTheme.shadow, radius: 18, x: 0, y: 10)
            )
    }
}

struct SessionCountdownPill: View {
    let expiresAt: Date?
    var accent: Color = AppTheme.coral

    var body: some View {
        if let expiresAt {
            TimelineView(.periodic(from: Date(), by: 1)) { _ in
                let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
                Label(formatSeconds(remaining), systemImage: "timer")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.16))
                    .foregroundColor(accent)
                    .clipShape(Capsule())
            }
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct AccentTag: View {
    let title: String
    var tint: Color = AppTheme.sky

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }
}

enum L10n {
    private static var isRussian: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
    }

    static func text(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}
