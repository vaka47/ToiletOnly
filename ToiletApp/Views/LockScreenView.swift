import SwiftUI

struct LockScreenView: View {
    @ObservedObject var viewModel: AccessViewModel

    var body: some View {
        ZStack {
            CameraView(controller: viewModel.cameraController)
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0.2), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Наведите камеру на унитаз")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Сессия откроется на 15 минут")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.8))

                if viewModel.isDetecting {
                    ProgressView()
                        .tint(.white)
                }

                Text("Уверенность: \(Int(viewModel.lastConfidence * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(24)
            .background(Color.black.opacity(0.35))
            .cornerRadius(16)
            .padding()
        }
    }
}
