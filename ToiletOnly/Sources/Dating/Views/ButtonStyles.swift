import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    let tint: Color
    var useGradient: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(
                Group {
                    if useGradient {
                        AppTheme.accentGradient.opacity(configuration.isPressed ? 0.82 : 1)
                    } else {
                        tint.opacity(configuration.isPressed ? 0.82 : 1)
                    }
                }
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 12, x: 0, y: 8)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.62 : 0.80))
                    .shadow(color: AppTheme.shadow.opacity(0.8), radius: 10, x: 0, y: 6)
            )
            .foregroundColor(AppTheme.ink)
    }
}
