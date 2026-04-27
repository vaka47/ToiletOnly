import SwiftUI
import AVFoundation

struct VideoRecorderView: View {
    @ObservedObject var recorder: VideoRecorder
    @Environment(\.dismiss) private var dismiss
    let token: String?

    @State private var isUploading: Bool = false
    @State private var uploadSuccess: Bool = false
    @State private var showNSFWAlert: Bool = false
    @State private var showFaceAlert: Bool = false
    @State private var showFaceLostAlert: Bool = false
    @State private var caption: String = ""

    var body: some View {
        ZStack {
            CameraPreview(layer: recorder.makePreviewLayer())
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                topBar

                Spacer()

                statusPanel

                if recorder.lastVideoURL != nil {
                    captionComposer
                } else {
                    recordingHint
                }

                controlDock
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .alert(L10n.text("Видео не прошло модерацию", "Video moderation failed"), isPresented: $showNSFWAlert) {
            Button(L10n.text("Ок", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.text("Похоже, в видео есть запрещённый контент. Попробуй другое.", "The video appears to contain restricted content. Try another one."))
        }
        .alert(L10n.text("Нужно лицо", "Face required"), isPresented: $showFaceAlert) {
            Button(L10n.text("Ок", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.text("Добавь видео, где видно лицо. Так мы снижаем риск нежелательного контента.", "Add a video where a face is visible to reduce unwanted content."))
        }
        .alert(L10n.text("Лицо пропало из кадра", "Face left the frame"), isPresented: $showFaceLostAlert) {
            Button(L10n.text("Ок", "OK"), role: .cancel) {
                recorder.didStopBecauseFaceLost = false
            }
        } message: {
            Text(L10n.text("Запись остановлена автоматически. Держи лицо в кадре без выпадений.", "Recording stopped automatically. Keep your face in frame at all times."))
        }
        .onAppear {
            recorder.startSession()
        }
        .onDisappear {
            recorder.stopSession()
        }
        .onChange(of: recorder.didStopBecauseFaceLost) { newValue in
            showFaceLostAlert = newValue
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.34))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            pill(L10n.text("До 60 сек", "Up to 60 sec"), tint: AppTheme.mango)
            pill(recorder.faceStatusText, tint: recorder.isFaceVisible ? AppTheme.mint : AppTheme.coral)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Видео текущей сессии", "Current session video"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(
                L10n.text(
                    "Начать запись можно только с лицом в кадре. Если лицо пропадёт, запись остановится автоматически.",
                    "Recording starts only when your face is visible. If your face leaves the frame, recording stops automatically."
                )
            )
            .font(.callout.weight(.medium))
            .foregroundColor(.white.opacity(0.86))
            .lineSpacing(2)

            if uploadSuccess {
                pill(
                    L10n.text("Видео опубликовано: оно уже в ленте и в профиле.", "Video published: it is already in the feed and on your profile."),
                    tint: AppTheme.mint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(AppTheme.sky.opacity(0.38))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Сними короткий живой ролик", "Shoot a short live clip"))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(
                    L10n.text(
                        "Лучше всего работают видео с лицом, движением и короткой подписью. Они сразу сильнее цепляют в ленте.",
                        "Videos with a visible face, movement, and a short caption perform best in the feed."
                    )
                )
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.82))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
    }

    private var captionComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Подпись к видео", "Video caption"))
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(caption.count)/240")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
            }

            TextEditor(text: $caption)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 120)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                )
                .foregroundColor(.white)
                .onChange(of: caption) { value in
                    if value.count > 240 {
                        caption = String(value.prefix(240))
                    }
                }

            if let url = recorder.lastVideoURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
    }

    private var controlDock: some View {
        HStack(alignment: .center, spacing: 16) {
            if recorder.lastVideoURL != nil, !recorder.isRecording {
                Button {
                    recorder.startRecording()
                } label: {
                    Label(L10n.text("Переснять", "Retake"), systemImage: "arrow.counterclockwise")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 112, height: 1)
            }

            Button {
                if recorder.isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 90, height: 90)
                    Circle()
                        .fill(recorder.isRecording ? Color.white : AppTheme.coral)
                        .frame(width: recorder.isRecording ? 34 : 72, height: recorder.isRecording ? 34 : 72)
                }
            }
            .buttonStyle(.plain)
            .disabled(!recorder.isRecording && !recorder.isFaceVisible)
            .opacity((!recorder.isRecording && !recorder.isFaceVisible) ? 0.58 : 1)

            if recorder.lastVideoURL != nil, !recorder.isRecording {
                Button {
                    Task { await publishVideo() }
                } label: {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                        }
                        Text(isUploading ? L10n.text("Публикуем", "Publishing") : L10n.text("В ленту", "Publish"))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.coral.opacity(0.34), radius: 18, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
            } else {
                Color.clear
                    .frame(width: 112, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func publishVideo() async {
        guard let url = recorder.lastVideoURL else { return }
        isUploading = true
        do {
            let assetURL = try await MediaService.shared.uploadVideo(token: token, fileURL: url, purpose: "session_video")
            await ProfileService.shared.updateSessionVideo(
                token: token,
                assetURL: assetURL,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            uploadSuccess = true
        } catch UploadError.nsfwDetected {
            showNSFWAlert = true
        } catch UploadError.faceRequired {
            showFaceAlert = true
        } catch {
            print("Session video publish failed: \(error)")
        }
        isUploading = false
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.92))
            .clipShape(Capsule())
    }
}

private struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        layer.frame = uiView.bounds
    }
}
