import SwiftUI

struct LockScreenView: View {
    @ObservedObject var viewModel: AccessViewModel
    @AppStorage("debug_overlay") private var showDebugOverlay: Bool = true

    private var scanColor: Color {
        if viewModel.isToiletInFrame {
            return Color(red: 0.29, green: 0.86, blue: 0.59)
        }
        if viewModel.lastBlockedLabel != "none" && viewModel.lastBlockedConfidence >= 0.48 {
            return Color(red: 1.00, green: 0.45, blue: 0.31)
        }
        return Color(red: 0.78, green: 0.90, blue: 1.00)
    }

    var body: some View {
        ZStack {
            CameraView(controller: viewModel.cameraController)
                .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.68), location: 0.00),
                    .init(color: Color.black.opacity(0.18), location: 0.36),
                    .init(color: Color.black.opacity(0.08), location: 0.58),
                    .init(color: Color.black.opacity(0.76), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topStatus
                    .padding(.top, 54)
                    .padding(.horizontal, 20)

                Spacer(minLength: 260)

                scanCard
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
            }
        }
        .onLongPressGesture(minimumDuration: 1.0) {
            showDebugOverlay.toggle()
        }
    }

    private var topStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(scanColor)
                .frame(width: 9, height: 9)
                .shadow(color: scanColor.opacity(0.7), radius: 8)

            Text("ToiletOnly")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Text(L10n.text("15 мин", "15 min"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.36), in: Capsule())
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.scanTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(viewModel.scanSubtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            progressView

            if showDebugOverlay {
                debugMetrics
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.text("Подтверждение", "Verification"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.68))

                Spacer()

                Text("\(viewModel.hitCount)/\(max(viewModel.windowCount, 1))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.68))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [scanColor.opacity(0.72), scanColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * viewModel.unlockProgress))
                }
            }
            .frame(height: 9)
        }
    }

    private var debugMetrics: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricPill(title: "Unlock", value: "\(Int(viewModel.lastConfidence * 100))%")
                MetricPill(title: "Raw", value: "\(Int(viewModel.lastRawConfidence * 100))%")
                MetricPill(title: "Scene", value: "\(Int(viewModel.lastSceneToiletConfidence * 100))%")
            }

            HStack(spacing: 10) {
                MetricPill(title: "Shape", value: "\(Int(viewModel.lastGeometryScore * 100))%")
                MetricPill(title: "Texture", value: "\(Int(viewModel.lastStructureScore * 100))%")
                MetricPill(title: "FPS", value: "\(viewModel.fps)")
            }

            HStack {
                Text("Top: \(viewModel.lastLabel) \(Int(viewModel.lastLabelConfidence * 100))%")
                Spacer()
                Text("Guard: \(viewModel.lastSceneLabel) \(Int(viewModel.lastSceneConfidence * 100))%")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.55))
            .lineLimit(1)

            if viewModel.lastBlockedLabel != "none" {
                Text("Blocked: \(viewModel.lastBlockedLabel) \(Int(viewModel.lastBlockedConfidence * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(scanColor.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
