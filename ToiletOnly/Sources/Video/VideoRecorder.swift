import AVFoundation
import Foundation
import Vision

final class VideoRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastVideoURL: URL?
    @Published private(set) var isFaceVisible: Bool = false
    @Published private(set) var faceStatusText: String = "Держи лицо в кадре"
    @Published private(set) var isSessionReady: Bool = false
    @Published private(set) var cameraAccessDenied: Bool = false
    @Published var didStopBecauseFaceLost: Bool = false
    @Published var lastErrorMessage: String?

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "video.recorder.session.queue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "video.recorder.vision.queue", qos: .userInitiated)
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let sequenceRequestHandler = VNSequenceRequestHandler()
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var isConfigured: Bool = false
    private var lastVisionRunAt: Date = .distantPast
    private var lastFaceSeenAt: Date = .distantPast
    private let visionInterval: TimeInterval = 0.25
    private let maxFaceGapWhileRecording: TimeInterval = 1.2

    override init() {
        super.init()
    }

    func prepareForPresentation() {
        DispatchQueue.main.async {
            self.didStopBecauseFaceLost = false
            self.lastErrorMessage = nil
            self.faceStatusText = "Готовим камеру"
        }
    }

    func startSession() {
        sessionQueue.async {
            self.ensureCameraAccessAndStartSession()
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            DispatchQueue.main.async {
                self.isSessionReady = false
            }
        }
    }

    func resetDraft() {
        if let url = lastVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        DispatchQueue.main.async {
            self.lastVideoURL = nil
            self.didStopBecauseFaceLost = false
            self.lastErrorMessage = nil
        }
    }

    func startRecording(maxDuration: TimeInterval = 60) {
        sessionQueue.async {
            guard !self.movieOutput.isRecording else { return }

            if self.cameraAccessDenied {
                DispatchQueue.main.async {
                    self.faceStatusText = "Разреши доступ к камере"
                }
                self.publishError("camera_denied")
                return
            }

            if !self.isSessionReady {
                DispatchQueue.main.async {
                    self.faceStatusText = "Камера еще запускается"
                }
                self.startSession()
                self.publishError("camera_preparing")
                return
            }

            guard self.isFaceVisible else {
                DispatchQueue.main.async {
                    self.faceStatusText = "Запись доступна только когда лицо в кадре"
                }
                self.publishError("record_face_required")
                return
            }

            self.resetDraft()

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("session_\(UUID().uuidString).mov")
            self.movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 1)
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
                self.didStopBecauseFaceLost = false
                self.lastErrorMessage = nil
            }
        }
    }

    func stopRecording() {
        sessionQueue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        previewLayer
    }

    private func ensureCameraAccessAndStartSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.cameraAccessDenied = false
            }
            configureSessionIfNeeded()
            startRunningSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.sessionQueue.async {
                    DispatchQueue.main.async {
                        self.cameraAccessDenied = !granted
                        self.faceStatusText = granted ? "Готовим камеру" : "Разреши доступ к камере"
                    }
                    guard granted else { return }
                    self.configureSessionIfNeeded()
                    self.startRunningSessionIfNeeded()
                }
            }
        default:
            DispatchQueue.main.async {
                self.cameraAccessDenied = true
                self.faceStatusText = "Разреши доступ к камере"
            }
        }
    }

    private func startRunningSessionIfNeeded() {
        configureAudioSession()
        if !session.isRunning {
            session.startRunning()
        }
        DispatchQueue.main.async {
            self.isSessionReady = true
            if !self.isRecording {
                self.faceStatusText = self.isFaceVisible ? "Лицо найдено, можно записывать" : "Держи лицо в кадре"
            }
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

        defer {
            session.commitConfiguration()
            isConfigured = true
        }

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            publishError("camera_missing")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }
            configureVideoDevice(videoDevice)

            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                try? configureAudioInput(with: audioDevice)
            }

            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
                if let connection = videoDataOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }
            }
        } catch {
            publishError(error.localizedDescription)
        }
    }

    private func configureAudioInput(with device: AVCaptureDevice) throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                audioDeviceInput = input
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                self.sessionQueue.async {
                    guard self.audioDeviceInput == nil else { return }
                    do {
                        let input = try AVCaptureDeviceInput(device: device)
                        if self.session.canAddInput(input) {
                            self.session.beginConfiguration()
                            self.session.addInput(input)
                            self.session.commitConfiguration()
                            self.audioDeviceInput = input
                        }
                    } catch {
                        self.publishError(error.localizedDescription)
                    }
                }
            }
        default:
            break
        }
    }

    private func configureVideoDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            let targetFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = targetFrameDuration
            device.activeVideoMaxFrameDuration = targetFrameDuration
            device.unlockForConfiguration()
        } catch {
            publishError(error.localizedDescription)
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            publishError(error.localizedDescription)
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.lastErrorMessage = nil
            self.lastErrorMessage = message
        }
    }

    private func updateFaceState(hasFace: Bool) {
        let now = Date()
        if hasFace {
            lastFaceSeenAt = now
        }

        let faceVisible = hasFace || now.timeIntervalSince(lastFaceSeenAt) <= 0.35
        DispatchQueue.main.async {
            self.isFaceVisible = faceVisible
            if self.cameraAccessDenied {
                self.faceStatusText = "Разреши доступ к камере"
            } else if !self.isSessionReady {
                self.faceStatusText = "Готовим камеру"
            } else if self.isRecording {
                self.faceStatusText = faceVisible
                    ? "Лицо на месте, можно продолжать"
                    : "Верни лицо в кадр"
            } else {
                self.faceStatusText = faceVisible
                    ? "Лицо найдено, можно записывать"
                    : "Держи лицо в кадре"
            }
        }

        if movieOutput.isRecording && now.timeIntervalSince(lastFaceSeenAt) > maxFaceGapWhileRecording {
            stopRecording()
            DispatchQueue.main.async {
                self.didStopBecauseFaceLost = true
            }
        }
    }
}

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if let error {
                self.publishError(error.localizedDescription)
                return
            }
            self.lastVideoURL = outputFileURL
        }
    }
}

extension VideoRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastVisionRunAt) >= visionInterval else { return }
        lastVisionRunAt = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        do {
            try sequenceRequestHandler.perform([faceRequest], on: pixelBuffer, orientation: .leftMirrored)
            let hasFace = !(faceRequest.results ?? []).isEmpty
            updateFaceState(hasFace: hasFace)
        } catch {
            updateFaceState(hasFace: false)
        }
    }
}
