import Foundation
import Combine
import AVFoundation

final class AccessViewModel: ObservableObject {
    @Published var isDetecting: Bool = false
    @Published var lastConfidence: Float = 0

    let cameraController: CameraController
    private let detector: ToiletDetecting
    private let sessionManager: SessionManager

    private var lastProcessTime: Date = .distantPast
    private var recentDetections: [Bool] = []
    private let windowSize = 10
    private let requiredHits = 6
    private let minConfidence: Float = 0.6

    init(sessionManager: SessionManager, detector: ToiletDetecting = ToiletDetector()) {
        self.sessionManager = sessionManager
        self.detector = detector
        self.cameraController = CameraController()
        bindCamera()
    }

    private func bindCamera() {
        cameraController.onFrame = { [weak self] pixelBuffer in
            guard let self else { return }
            guard !self.sessionManager.isActive else { return }

            let now = Date()
            if now.timeIntervalSince(self.lastProcessTime) < 0.3 { return }
            self.lastProcessTime = now

            self.isDetecting = true

            self.detector.process(pixelBuffer: pixelBuffer) { [weak self] isToilet, confidence in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lastConfidence = confidence
                    self.pushDetection(isToilet && confidence >= self.minConfidence)
                    self.isDetecting = false

                    if self.shouldUnlock() {
                        self.sessionManager.startSession(durationMinutes: 15)
                        self.resetDetections()
                    }
                }
            }
        }
    }

    private func pushDetection(_ value: Bool) {
        recentDetections.append(value)
        if recentDetections.count > windowSize {
            recentDetections.removeFirst(recentDetections.count - windowSize)
        }
    }

    private func shouldUnlock() -> Bool {
        let hits = recentDetections.filter { $0 }.count
        return hits >= requiredHits
    }

    private func resetDetections() {
        recentDetections.removeAll(keepingCapacity: true)
        lastConfidence = 0
        isDetecting = false
    }
}
