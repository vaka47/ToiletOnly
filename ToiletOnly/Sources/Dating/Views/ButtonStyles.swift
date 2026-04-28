import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    let tint: Color
    var useGradient: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: (useGradient ? AppTheme.coral : tint).opacity(configuration.isPressed ? 0.10 : 0.22), radius: 16, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.66 : 0.82))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: AppTheme.shadow.opacity(0.8), radius: 12, x: 0, y: 8)
            )
            .foregroundColor(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
    }
}
