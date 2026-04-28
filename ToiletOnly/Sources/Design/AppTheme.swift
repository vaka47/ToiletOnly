import SwiftUI
import Foundation

enum AppTheme {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.13)
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let coral = Color(red: 0.96, green: 0.39, blue: 0.35)
    static let mango = Color(red: 0.97, green: 0.72, blue: 0.36)
    static let mint = Color(red: 0.21, green: 0.69, blue: 0.58)
    static let sky = Color(red: 0.24, green: 0.52, blue: 0.90)
    static let panel = Color.white.opacity(0.68)
    static let panelStrong = Color.white.opacity(0.84)
    static let shadow = Color.black.opacity(0.12)
    static let muted = Color.black.opacity(0.58)

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
                    Color(red: 0.99, green: 0.98, blue: 0.96),
                    Color(red: 0.97, green: 0.94, blue: 0.89),
                    Color(red: 0.92, green: 0.95, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.coral.opacity(0.20), AppTheme.mango.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 360, height: 280)
                .blur(radius: 36)
                .offset(x: -160, y: -260)

            Circle()
                .fill(AppTheme.sky.opacity(0.13))
                .frame(width: 340, height: 340)
                .blur(radius: 34)
                .offset(x: 180, y: 220)

            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(AppTheme.mint.opacity(0.08))
                .frame(width: 380, height: 220)
                .rotationEffect(.degrees(-11))
                .offset(x: 150, y: -8)

            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: 420, height: 180)
                .rotationEffect(.degrees(18))
                .blur(radius: 18)
                .offset(x: -180, y: 260)
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
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.panel)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: AppTheme.shadow, radius: 20, x: 0, y: 12)
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
