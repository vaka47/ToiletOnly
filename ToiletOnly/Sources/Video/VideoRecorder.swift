import AVFoundation
import Foundation
import Vision

final class VideoRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastVideoURL: URL?
    @Published private(set) var isFaceVisible: Bool = false
    @Published private(set) var faceStatusText: String = "Держи лицо в кадре"
    @Published var didStopBecauseFaceLost: Bool = false

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "video.recorder.queue")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var lastVisionRunAt: Date = .distantPast
    private var lastFaceSeenAt: Date = .distantPast
    private let visionInterval: TimeInterval = 0.25
    private let maxFaceGapWhileRecording: TimeInterval = 1.2

    override init() {
        super.init()
        configureSession()
    }

    func startSession() {
        queue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func startRecording(maxDuration: TimeInterval = 60) {
        guard !movieOutput.isRecording else { return }
        guard isFaceVisible else {
            DispatchQueue.main.async {
                self.faceStatusText = "Запись доступна только когда лицо в кадре"
            }
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("session_\(UUID().uuidString).mov")
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 1)
        movieOutput.startRecording(to: url, recordingDelegate: self)
        DispatchQueue.main.async {
            self.isRecording = true
            self.didStopBecauseFaceLost = false
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoDataOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
        } catch {
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
    }

    private func updateFaceState(hasFace: Bool) {
        let now = Date()
        if hasFace {
            lastFaceSeenAt = now
        }

        let faceVisible = hasFace || now.timeIntervalSince(lastFaceSeenAt) <= 0.35
        DispatchQueue.main.async {
            self.isFaceVisible = faceVisible
            if self.isRecording {
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
            if error == nil {
                self.lastVideoURL = outputFileURL
            }
        }
    }
}

extension VideoRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastVisionRunAt) >= visionInterval else { return }
        lastVisionRunAt = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([request])
            let hasFace = !(request.results ?? []).isEmpty
            updateFaceState(hasFace: hasFace)
        } catch {
            updateFaceState(hasFace: false)
        }
    }
}
