import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Основной экран")
                .font(.largeTitle.bold())

            if let expiresAt = sessionManager.expiresAt {
                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                    let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
                    Text("Осталось: \(format(remaining))")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Доступ закрыт")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Text("Здесь будет основной функционал приложения")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
