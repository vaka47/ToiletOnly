import SwiftUI
import AVFoundation

struct SelfieCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = SelfieCameraController()
    let onCaptured: (Data) -> Void

    var body: some View {
        VStack(spacing: 16) {
            AppCard {
                CameraPreview(layer: controller.makePreviewLayer())
                    .frame(height: 360)
                    .cornerRadius(20)
                    .overlay(alignment: .topLeading) {
                        Text("Селфи при унитазе")
                            .font(.caption.bold())
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(12)
                    }
            }

            Button("Сделать фото") {
                controller.capture { data in
                    onCaptured(data)
                    dismiss()
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral, useGradient: true))

            Button("Отмена") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(tint: .gray))
        }
        .padding(20)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        layer.frame = uiView.bounds
    }
}
