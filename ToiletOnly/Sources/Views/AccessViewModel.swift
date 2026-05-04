import Foundation
import Combine
import AVFoundation

final class AccessViewModel: ObservableObject {
    @Published var isDetecting: Bool = false
    @Published var isToiletInFrame: Bool = false
    @Published var lastConfidence: Float = 0
    @Published var lastRawConfidence: Float = 0
    @Published var lastLabel: String = "none"
    @Published var lastLabelConfidence: Float = 0
    @Published var lastGeometryScore: Float = 0
    @Published var lastStructureScore: Float = 0
    @Published var lastSceneLabel: String = "none"
    @Published var lastSceneConfidence: Float = 0
    @Published var lastSceneToiletConfidence: Float = 0
    @Published var lastBlockedLabel: String = "none"
    @Published var lastBlockedConfidence: Float = 0
    @Published var lastDecision: String = "waiting"
    @Published var fps: Int = 0
    @Published var hitCount: Int = 0
    @Published var windowCount: Int = 0
    @Published var streakCount: Int = 0

    let cameraController: CameraController
    private let detector: ToiletDetecting
    private let sessionManager: SessionManager

    private var lastProcessTime: Date = .distantPast
    private var lastFpsTime: Date = .distantPast
    private var frameCounter: Int = 0
    private var recentDetections: [Bool] = []
    private let windowSize = 12
    private let requiredHits = 7
    private let requiredStreak = 4
    private let minConfidence: Float = 0.58
    private let minFrameInterval: TimeInterval = 0.14
    private let stableFrameInterval: TimeInterval = 0.22
    private var currentStreak: Int = 0

    var unlockProgress: Double {
        min(1, Double(hitCount) / Double(requiredHits))
    }

    var scanTitle: String {
        if isToiletInFrame {
            return L10n.text("Унитаз подтвержден", "Toilet confirmed")
        }
        if lastBlockedLabel != "none" && lastBlockedConfidence >= 0.48 {
            return L10n.text("Это не унитаз", "Not a toilet")
        }
        if lastConfidence >= 0.35 {
            return L10n.text("Держите камеру ровнее", "Hold the camera steady")
        }
        return L10n.text("Наведите на настоящий унитаз", "Point at a real toilet")
    }

    var scanSubtitle: String {
        if isToiletInFrame {
            return L10n.text("Подтверждаю несколько кадров подряд", "Confirming across multiple frames")
        }
        if lastBlockedLabel != "none" && lastBlockedConfidence >= 0.48 {
            return "\(L10n.text("Похоже на", "Looks like")) \(localizedObjectName(lastBlockedLabel))"
        }
        if lastDecision == "adjust_angle" {
            return L10n.text("Покажите чашу и сиденье целиком", "Show the bowl and seat clearly")
        }
        return L10n.text("Сработает только на унитаз, не на белую мебель", "Unlocks only on a toilet, not white furniture")
    }

    init(sessionManager: SessionManager, detector: ToiletDetecting = ToiletDetector()) {
        self.sessionManager = sessionManager
        self.detector = detector
        self.cameraController = CameraController()
        bindCamera()
    }

    private func bindCamera() {
        cameraController.onFrame = { [weak self] pixelBuffer, orientation in
            guard let self else { return }
            guard !self.sessionManager.isActive else { return }

            let now = Date()
            self.frameCounter += 1
            if now.timeIntervalSince(self.lastFpsTime) >= 1.0 {
                let elapsed = max(1.0, now.timeIntervalSince(self.lastFpsTime))
                let newFps = Int(Double(self.frameCounter) / elapsed)
                self.frameCounter = 0
                self.lastFpsTime = now
                DispatchQueue.main.async {
                    self.fps = newFps
                }
            }

            let frameInterval = self.isToiletInFrame ? self.stableFrameInterval : self.minFrameInterval
            if now.timeIntervalSince(self.lastProcessTime) < frameInterval { return }
            self.lastProcessTime = now

            DispatchQueue.main.async {
                self.isDetecting = true
            }

            self.detector.process(pixelBuffer: pixelBuffer, orientation: orientation) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.lastConfidence = result.confidence
                    self.lastRawConfidence = result.rawConfidence
                    self.lastLabel = result.bestLabel
                    self.lastLabelConfidence = result.bestLabelConfidence
                    self.lastGeometryScore = result.geometryScore
                    self.lastStructureScore = result.structureScore
                    self.lastSceneLabel = result.sceneLabel
                    self.lastSceneConfidence = result.sceneConfidence
                    self.lastSceneToiletConfidence = result.sceneToiletConfidence
                    self.lastBlockedLabel = result.blockedLabel
                    self.lastBlockedConfidence = result.blockedConfidence
                    self.lastDecision = result.decision
                    let isValidToilet = result.isToilet && result.confidence >= self.minConfidence
                    self.isToiletInFrame = isValidToilet
                    self.pushDetection(isValidToilet)
                    if isValidToilet {
                        self.sessionManager.markToiletDetected()
                    }
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
        if value {
            currentStreak += 1
        } else {
            currentStreak = 0
        }
        hitCount = recentDetections.filter { $0 }.count
        windowCount = recentDetections.count
        streakCount = currentStreak
    }

    private func shouldUnlock() -> Bool {
        let hits = recentDetections.filter { $0 }.count
        return hits >= requiredHits && currentStreak >= requiredStreak
    }

    private func resetDetections() {
        recentDetections.removeAll(keepingCapacity: true)
        currentStreak = 0
        hitCount = 0
        windowCount = 0
        streakCount = 0
        lastConfidence = 0
        lastRawConfidence = 0
        lastLabel = "none"
        lastLabelConfidence = 0
        lastGeometryScore = 0
        lastStructureScore = 0
        lastSceneLabel = "none"
        lastSceneConfidence = 0
        lastSceneToiletConfidence = 0
        lastBlockedLabel = "none"
        lastBlockedConfidence = 0
        lastDecision = "waiting"
        isToiletInFrame = false
        isDetecting = false
    }

    private func localizedObjectName(_ label: String) -> String {
        switch label {
        case "chair":
            return L10n.text("стул", "chair")
        case "couch":
            return L10n.text("диван", "couch")
        case "bed":
            return L10n.text("кровать", "bed")
        case "dining table":
            return L10n.text("стол", "table")
        case "sink":
            return L10n.text("раковину", "sink")
        case "refrigerator":
            return L10n.text("холодильник", "refrigerator")
        case "cup":
            return L10n.text("кружку", "cup")
        case "bowl":
            return L10n.text("миску", "bowl")
        case "wine glass":
            return L10n.text("бокал", "wine glass")
        case "bottle":
            return L10n.text("бутылку", "bottle")
        case "microwave":
            return L10n.text("микроволновку", "microwave")
        case "oven":
            return L10n.text("духовку", "oven")
        case "tv":
            return L10n.text("телевизор", "tv")
        case "laptop":
            return L10n.text("ноутбук", "laptop")
        case "flat appliance":
            return L10n.text("ровную белую поверхность", "a flat white surface")
        case "round_top_view":
            return L10n.text("круглый предмет сверху", "a round object from above")
        default:
            return label
        }
    }
}
