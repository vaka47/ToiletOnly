import Foundation
import AVFoundation
import Vision
import CoreML
import CoreImage
import ImageIO

struct ToiletDetectionResult {
    let isToilet: Bool
    let confidence: Float
    let rawConfidence: Float
    let bestLabel: String
    let bestLabelConfidence: Float
    let geometryScore: Float
    let structureScore: Float
    let sceneLabel: String
    let sceneConfidence: Float
    let sceneToiletConfidence: Float
    let blockedLabel: String
    let blockedConfidence: Float
    let decision: String
}

protocol ToiletDetecting {
    func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (ToiletDetectionResult) -> Void
    )
}

final class ToiletDetector: ToiletDetecting {
    private struct DetectionCandidate {
        let confidence: Float
        let label: String
        let labelConfidence: Float
        let rawConfidence: Float
        let centerX: Float
        let centerY: Float
        let width: Float
        let height: Float
    }

    private struct StructureValidation {
        let score: Float
        let seatContrast: Float
        let centerDarkness: Float
        let whiteRatio: Float
        let ringAspectRatio: Float
    }

    private struct SceneGuardResult {
        let topLabel: String
        let topConfidence: Float
        let toiletConfidence: Float
        let negativeLabel: String
        let negativeConfidence: Float
    }

    private let queue = DispatchQueue(label: "toilet.detector.queue", qos: .userInitiated)
    private let model: VNCoreMLModel?
    private let sceneGuardModel: VNCoreMLModel?
    private let modelLoadMessage: String
    private let toiletLabels: Set<String> = ["toilet", "wc", "commode"]
    private let minimumRawConfidence: Float = 0.48
    private let minimumCombinedConfidence: Float = 0.58
    private let minimumGeometryScore: Float = 0.10
    private let sceneGuardTriggerConfidence: Float = 0.34
    private let structureValidationTriggerConfidence: Float = 0.54
    private static let ciContext = CIContext(options: nil)
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    private static let cocoNames = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
        "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
        "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
        "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
        "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
        "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
        "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
        "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
        "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear",
        "hair drier", "toothbrush"
    ]
    private static let cocoToiletIndex = 61
    private static let negativeSceneLabels: Set<String> = [
        "chair", "couch", "bed", "dining table", "sink", "refrigerator", "microwave",
        "oven", "tv", "laptop", "cup", "bowl", "wine glass", "bottle"
    ]
    private static let drinkwareSceneLabels: Set<String> = ["cup", "bowl", "wine glass", "bottle"]

    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        var loadMessage = ""

        if let loaded = Self.loadModel(named: "ToiletDetector", configuration: config, loadMessage: &loadMessage) {
            model = loaded
        } else {
            NSLog("ToiletDetector: model missing. Bundle path=%@", Bundle.main.bundlePath)
            model = nil
        }

        if let loadedSceneGuard = Self.loadModel(named: "SceneGuard", configuration: config, loadMessage: &loadMessage) {
            sceneGuardModel = loadedSceneGuard
        } else {
            sceneGuardModel = nil
            NSLog("ToiletDetector: SceneGuard missing; running single-model fallback.")
        }

        if loadMessage.isEmpty {
            loadMessage = model == nil ? "ToiletDetector not found" : "ok"
        }
        modelLoadMessage = loadMessage
    }

    func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (ToiletDetectionResult) -> Void
    ) {
        guard let model else {
            completion(Self.emptyResult(label: "model_missing:\(modelLoadMessage)", decision: "model_missing"))
            return
        }

        queue.async {
            let toilet = self.runToiletModel(model, pixelBuffer: pixelBuffer, orientation: orientation)
            let scene = self.shouldRunSceneGuard(for: toilet)
                ? self.runSceneGuard(pixelBuffer: pixelBuffer, orientation: orientation)
                : nil

            guard let candidate = toilet.candidate else {
                completion(
                    Self.emptyResult(
                        label: toilet.bestLabel,
                        labelConfidence: toilet.bestLabelConfidence,
                        scene: scene,
                        decision: "no_toilet_candidate"
                    )
                )
                return
            }

            completion(
                self.makeResult(
                    candidate: candidate,
                    scene: scene,
                    pixelBuffer: pixelBuffer,
                    orientation: orientation
                )
            )
        }
    }

    private static func loadModel(
        named name: String,
        configuration: MLModelConfiguration,
        loadMessage: inout String
    ) -> VNCoreMLModel? {
        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            do {
                let mlModel = try MLModel(contentsOf: modelURL, configuration: configuration)
                return try VNCoreMLModel(for: mlModel)
            } catch {
                loadMessage = "\(name).mlmodelc load error: \(error)"
                NSLog("ToiletDetector: failed to load %@.mlmodelc at %@, error: %@", name, modelURL.path, String(describing: error))
            }
        }

        if let modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            do {
                let mlModel = try MLModel(contentsOf: modelURL, configuration: configuration)
                return try VNCoreMLModel(for: mlModel)
            } catch {
                loadMessage = "\(name).mlpackage load error: \(error)"
                NSLog("ToiletDetector: failed to load %@.mlpackage at %@, error: %@", name, modelURL.path, String(describing: error))
            }
        }

        return nil
    }

    private func runToiletModel(
        _ model: VNCoreMLModel,
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> (candidate: DetectionCandidate?, bestLabel: String, bestLabelConfidence: Float) {
        var bestLabel = "none"
        var bestLabelConfidence: Float = 0
        var bestCandidate: DetectionCandidate?

        let request = VNCoreMLRequest(model: model) { request, _ in
            if let observations = request.results as? [VNRecognizedObjectObservation], !observations.isEmpty {
                for obs in observations {
                    for label in obs.labels {
                        let name = label.identifier.lowercased()
                        if label.confidence > bestLabelConfidence {
                            bestLabelConfidence = label.confidence
                            bestLabel = name
                        }
                        guard self.toiletLabels.contains(where: { name.contains($0) }) else { continue }
                        let candidate = DetectionCandidate(
                            confidence: label.confidence,
                            label: name,
                            labelConfidence: label.confidence,
                            rawConfidence: label.confidence,
                            centerX: Float(obs.boundingBox.midX),
                            centerY: Float(obs.boundingBox.midY),
                            width: Float(obs.boundingBox.width),
                            height: Float(obs.boundingBox.height)
                        )
                        if bestCandidate == nil || Self.selectionScore(for: candidate) > Self.selectionScore(for: bestCandidate!) {
                            bestCandidate = candidate
                        }
                    }
                }
                return
            }

            if let observations = request.results as? [VNCoreMLFeatureValueObservation],
               let multiArray = observations.first?.featureValue.multiArrayValue,
               let candidate = Self.bestSingleClassCandidate(from: multiArray) {
                bestLabel = candidate.label
                bestLabelConfidence = candidate.labelConfidence
                bestCandidate = candidate
            }
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("ToiletDetector: ToiletDetector request failed: %@", String(describing: error))
        }

        return (bestCandidate, bestLabel, bestLabelConfidence)
    }

    private func runSceneGuard(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> SceneGuardResult? {
        guard let sceneGuardModel else { return nil }
        var result: SceneGuardResult?

        let request = VNCoreMLRequest(model: sceneGuardModel) { request, _ in
            if let observations = request.results as? [VNCoreMLFeatureValueObservation],
               let multiArray = observations.first?.featureValue.multiArrayValue {
                result = Self.sceneGuardResult(from: multiArray)
            } else if let observations = request.results as? [VNRecognizedObjectObservation] {
                result = Self.sceneGuardResult(from: observations)
            }
        }
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("ToiletDetector: SceneGuard request failed: %@", String(describing: error))
        }

        return result
    }

    private func makeResult(
        candidate: DetectionCandidate,
        scene: SceneGuardResult?,
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> ToiletDetectionResult {
        let geometryScore = Self.unlockGeometryScore(candidate)
        let sceneToilet = scene?.toiletConfidence ?? 0
        let shouldValidateStructure = candidate.rawConfidence >= structureValidationTriggerConfidence || sceneToilet >= 0.24
        let structure = shouldValidateStructure
            ? structureValidation(for: candidate, pixelBuffer: pixelBuffer, orientation: orientation)
            : StructureValidation(score: 0.32, seatContrast: 0, centerDarkness: 0, whiteRatio: 0.5)
        let sceneNegativeLabel = scene?.negativeLabel ?? "none"
        let sceneNegativeConfidence = scene?.negativeConfidence ?? 0
        let hasSceneToilet = sceneToilet >= 0.24
        let hasVeryHighCustomToilet = candidate.rawConfidence >= 0.88 &&
            geometryScore >= 0.18 &&
            structure.score >= 0.42

        let sceneBlocks = sceneNegativeConfidence >= 0.44 &&
            sceneNegativeConfidence >= sceneToilet + 0.12
        let drinkwareBlocks = Self.drinkwareSceneLabels.contains(sceneNegativeLabel) &&
            sceneNegativeConfidence >= max(0.18, sceneToilet + 0.06)
        let chairBlocks = sceneNegativeLabel == "chair" &&
            sceneNegativeConfidence >= 0.34 &&
            candidate.rawConfidence < 0.93
        let roundTopViewBlocks = !hasSceneToilet &&
            candidate.rawConfidence >= 0.56 &&
            abs(candidate.width - candidate.height) <= 0.10 &&
            abs(candidate.centerX - 0.50) <= 0.12 &&
            abs(candidate.centerY - 0.50) <= 0.12 &&
            abs(structure.ringAspectRatio - 1.0) <= 0.12 &&
            structure.seatContrast >= 0.05 &&
            structure.centerDarkness >= 0.16 &&
            structure.whiteRatio <= 0.72 &&
            !hasVeryHighCustomToilet
        let flatSurfaceBlocks = candidate.rawConfidence >= 0.65 &&
            candidate.height >= 0.72 &&
            candidate.width <= 0.58 &&
            structure.whiteRatio >= 0.74 &&
            structure.score <= 0.32
        let weakStructureBlocks = candidate.rawConfidence >= 0.60 &&
            structure.score <= 0.18 &&
            structure.whiteRatio >= 0.68 &&
            !hasVeryHighCustomToilet
        let semanticMismatchBlocks = candidate.rawConfidence >= 0.55 &&
            !hasSceneToilet &&
            !hasVeryHighCustomToilet
        let blocked = sceneBlocks || drinkwareBlocks || chairBlocks || roundTopViewBlocks || flatSurfaceBlocks || weakStructureBlocks || semanticMismatchBlocks
        let blockedLabel: String
        let blockedConfidence: Float
        if sceneBlocks {
            blockedLabel = sceneNegativeLabel
            blockedConfidence = sceneNegativeConfidence
        } else if drinkwareBlocks {
            blockedLabel = sceneNegativeLabel
            blockedConfidence = sceneNegativeConfidence
        } else if chairBlocks {
            blockedLabel = "chair"
            blockedConfidence = sceneNegativeConfidence
        } else if roundTopViewBlocks {
            blockedLabel = "round_top_view"
            blockedConfidence = candidate.rawConfidence
        } else if flatSurfaceBlocks {
            blockedLabel = "flat appliance"
            blockedConfidence = candidate.rawConfidence
        } else if weakStructureBlocks {
            blockedLabel = "weak_structure"
            blockedConfidence = candidate.rawConfidence
        } else if semanticMismatchBlocks {
            blockedLabel = "lookalike"
            blockedConfidence = candidate.rawConfidence
        } else {
            blockedLabel = "none"
            blockedConfidence = 0
        }

        let baseEvidence = max(candidate.rawConfidence, min(1, candidate.rawConfidence * 0.70 + sceneToilet * 0.42))
        let geometryMultiplier = 0.92 + 0.08 * geometryScore
        let structureMultiplier = 0.90 + 0.10 * structure.score
        let confidence = Self.clamp01(baseEvidence * geometryMultiplier * structureMultiplier)

        let hasToiletEvidence = hasSceneToilet || hasVeryHighCustomToilet
        let geometryOK = geometryScore >= minimumGeometryScore || hasSceneToilet
        let isDetected = !blocked &&
            candidate.rawConfidence >= minimumRawConfidence &&
            hasToiletEvidence &&
            geometryOK &&
            confidence >= minimumCombinedConfidence

        let decision: String
        if isDetected {
            decision = "confirmed"
        } else if blocked {
            decision = "blocked:\(blockedLabel)"
        } else if !hasToiletEvidence {
            decision = "scene_no_toilet"
        } else if !geometryOK {
            decision = "adjust_angle"
        } else {
            decision = "weak_toilet_evidence"
        }

        return ToiletDetectionResult(
            isToilet: isDetected,
            confidence: confidence,
            rawConfidence: candidate.rawConfidence,
            bestLabel: candidate.label,
            bestLabelConfidence: candidate.labelConfidence,
            geometryScore: geometryScore,
            structureScore: structure.score,
            sceneLabel: scene?.topLabel ?? "none",
            sceneConfidence: scene?.topConfidence ?? 0,
            sceneToiletConfidence: sceneToilet,
            blockedLabel: blockedLabel,
            blockedConfidence: blockedConfidence,
            decision: decision
        )
    }

    private static func emptyResult(
        label: String,
        labelConfidence: Float = 0,
        scene: SceneGuardResult? = nil,
        decision: String
    ) -> ToiletDetectionResult {
        ToiletDetectionResult(
            isToilet: false,
            confidence: 0,
            rawConfidence: 0,
            bestLabel: label,
            bestLabelConfidence: labelConfidence,
            geometryScore: 0,
            structureScore: 0,
            sceneLabel: scene?.topLabel ?? "none",
            sceneConfidence: scene?.topConfidence ?? 0,
            sceneToiletConfidence: scene?.toiletConfidence ?? 0,
            blockedLabel: scene?.negativeLabel ?? "none",
            blockedConfidence: scene?.negativeConfidence ?? 0,
            decision: decision
        )
    }

    private func shouldRunSceneGuard(
        for toiletResult: (candidate: DetectionCandidate?, bestLabel: String, bestLabelConfidence: Float)
    ) -> Bool {
        guard sceneGuardModel != nil else { return false }
        if let candidate = toiletResult.candidate, candidate.rawConfidence >= sceneGuardTriggerConfidence {
            return true
        }
        if Self.negativeSceneLabels.contains(toiletResult.bestLabel), toiletResult.bestLabelConfidence >= 0.28 {
            return true
        }
        return toiletResult.bestLabelConfidence >= 0.52
    }

    private static func selectionGeometryAffinity(for candidate: DetectionCandidate) -> Float {
        let area = candidate.width * candidate.height
        let bottomY = candidate.centerY + candidate.height * 0.5

        func closeness(_ value: Float, _ ideal: Float, _ tolerance: Float) -> Float {
            max(0, 1 - abs(value - ideal) / tolerance)
        }

        let widthScore = closeness(candidate.width, 0.74, 0.34)
        let heightScore = closeness(candidate.height, 0.68, 0.26)
        let areaScore = closeness(area, 0.44, 0.32)
        let centerXScore = closeness(candidate.centerX, 0.50, 0.34)
        let centerYScore = closeness(candidate.centerY, 0.50, 0.28)
        let bottomScore = closeness(bottomY, 0.80, 0.24)

        return (
            widthScore * 0.18 +
            heightScore * 0.16 +
            areaScore * 0.18 +
            centerXScore * 0.12 +
            centerYScore * 0.10 +
            bottomScore * 0.26
        )
    }

    private static func selectionScore(for candidate: DetectionCandidate) -> Float {
        candidate.rawConfidence * (0.82 + 0.18 * selectionGeometryAffinity(for: candidate))
    }

    private static func unlockGeometryScore(_ candidate: DetectionCandidate) -> Float {
        let area = candidate.width * candidate.height
        let bottomY = candidate.centerY + candidate.height * 0.5

        func closeness(_ value: Float, _ ideal: Float, _ tolerance: Float) -> Float {
            max(0, 1 - abs(value - ideal) / tolerance)
        }

        if area < 0.08 || area > 0.94 {
            return 0
        }

        let widthScore = closeness(candidate.width, 0.70, 0.42)
        let heightScore = closeness(candidate.height, 0.66, 0.36)
        let areaScore = closeness(area, 0.42, 0.40)
        let centerXScore = closeness(candidate.centerX, 0.50, 0.38)
        let centerYScore = closeness(candidate.centerY, 0.50, 0.34)
        let bottomScore = closeness(bottomY, 0.80, 0.28)

        return (
            widthScore * 0.16 +
            heightScore * 0.14 +
            areaScore * 0.16 +
            centerXScore * 0.12 +
            centerYScore * 0.10 +
            bottomScore * 0.32
        )
    }

    private func structureValidation(
        for candidate: DetectionCandidate,
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> StructureValidation {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(forExifOrientation: Int32(orientation.rawValue))
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return StructureValidation(score: 0, seatContrast: 0, centerDarkness: 0, whiteRatio: 1, ringAspectRatio: 1)
        }

        let normalizedRect = CGRect(
            x: CGFloat(candidate.centerX - candidate.width * 0.5),
            y: CGFloat(candidate.centerY - candidate.height * 0.5),
            width: CGFloat(candidate.width),
            height: CGFloat(candidate.height)
        ).insetBy(dx: -CGFloat(candidate.width) * 0.08, dy: -CGFloat(candidate.height) * 0.06)

        let cropRect = CGRect(
            x: normalizedRect.minX * extent.width,
            y: normalizedRect.minY * extent.height,
            width: normalizedRect.width * extent.width,
            height: normalizedRect.height * extent.height
        ).intersection(extent)

        guard cropRect.width >= 24, cropRect.height >= 24 else {
            return StructureValidation(score: 0, seatContrast: 0, centerDarkness: 0, whiteRatio: 1, ringAspectRatio: 1)
        }

        let sampleSide = 48
        let bytesPerPixel = 4
        let rowBytes = sampleSide * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: sampleSide * sampleSide * bytesPerPixel)

        let cropped = image.cropped(to: cropRect)
        let transformed = cropped.transformed(
            by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY)
                .scaledBy(
                    x: CGFloat(sampleSide) / cropRect.width,
                    y: CGFloat(sampleSide) / cropRect.height
                )
        )

        buffer.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            Self.ciContext.render(
                transformed,
                toBitmap: baseAddress,
                rowBytes: rowBytes,
                bounds: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide),
                format: .BGRA8,
                colorSpace: Self.colorSpace
            )
        }

        var luminance = [Float](repeating: 0, count: sampleSide * sampleSide)
        var whiteMask = [Float](repeating: 0, count: sampleSide * sampleSide)
        var brightnessSum: Float = 0
        var brightnessSquareSum: Float = 0

        for row in 0..<sampleSide {
            for col in 0..<sampleSide {
                let offset = row * rowBytes + col * bytesPerPixel
                let blue = Float(buffer[offset]) / 255
                let green = Float(buffer[offset + 1]) / 255
                let red = Float(buffer[offset + 2]) / 255
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
                let brightness = maxChannel
                let pixelLuminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let index = row * sampleSide + col

                luminance[index] = pixelLuminance
                whiteMask[index] = brightness >= 0.72 && saturation <= 0.18 ? 1 : 0
                brightnessSum += brightness
                brightnessSquareSum += brightness * brightness
            }
        }

        let pixelCount = Float(sampleSide * sampleSide)
        let meanBrightness = brightnessSum / pixelCount
        let variance = max(0, brightnessSquareSum / pixelCount - meanBrightness * meanBrightness)
        let brightnessStdDev = sqrt(variance)
        let whiteRatio = whiteMask.reduce(0, +) / pixelCount

        func maskSpanLengths(_ mask: [Float], threshold: Float = 0.5) -> (horizontal: Float, vertical: Float) {
            let centerRow = sampleSide / 2
            let centerCol = sampleSide / 2
            var minCol = sampleSide
            var maxCol = -1
            var minRow = sampleSide
            var maxRow = -1

            for col in 0..<sampleSide {
                if mask[centerRow * sampleSide + col] >= threshold {
                    minCol = min(minCol, col)
                    maxCol = max(maxCol, col)
                }
            }
            for row in 0..<sampleSide {
                if mask[row * sampleSide + centerCol] >= threshold {
                    minRow = min(minRow, row)
                    maxRow = max(maxRow, row)
                }
            }

            let horizontal = maxCol >= minCol ? Float(maxCol - minCol + 1) / Float(sampleSide) : 0
            let vertical = maxRow >= minRow ? Float(maxRow - minRow + 1) / Float(sampleSide) : 0
            return (horizontal, vertical)
        }

        func averageValue(
            _ values: [Float],
            centerX: Float,
            centerY: Float,
            radiusX: Float,
            radiusY: Float,
            excludeInnerRadiusX: Float? = nil,
            excludeInnerRadiusY: Float? = nil
        ) -> Float {
            var sum: Float = 0
            var count: Float = 0

            for row in 0..<sampleSide {
                for col in 0..<sampleSide {
                    let x = (Float(col) + 0.5) / Float(sampleSide)
                    let y = (Float(row) + 0.5) / Float(sampleSide)
                    let dx = (x - centerX) / radiusX
                    let dy = (y - centerY) / radiusY
                    guard dx * dx + dy * dy <= 1 else { continue }

                    if let excludeInnerRadiusX,
                       let excludeInnerRadiusY {
                        let innerDX = (x - centerX) / excludeInnerRadiusX
                        let innerDY = (y - centerY) / excludeInnerRadiusY
                        if innerDX * innerDX + innerDY * innerDY <= 1 {
                            continue
                        }
                    }

                    sum += values[row * sampleSide + col]
                    count += 1
                }
            }

            return count > 0 ? sum / count : 0
        }

        let innerSeatBrightness = averageValue(
            luminance,
            centerX: 0.50,
            centerY: 0.34,
            radiusX: 0.24,
            radiusY: 0.12
        )
        let rimBrightness = averageValue(
            luminance,
            centerX: 0.50,
            centerY: 0.34,
            radiusX: 0.38,
            radiusY: 0.20,
            excludeInnerRadiusX: 0.24,
            excludeInnerRadiusY: 0.12
        )

        let seatContrast = rimBrightness - innerSeatBrightness
        let centerDarkness = 1 - innerSeatBrightness
        let varianceScore = Self.clamp01((brightnessStdDev - 0.07) / 0.18)
        let seatScore = Self.clamp01((seatContrast - 0.03) / 0.18) * 0.55 +
            Self.clamp01((centerDarkness - 0.06) / 0.28) * 0.45
        let nonWhiteScore = 1 - Self.clamp01((whiteRatio - 0.80) / 0.18)
        let structureScore = seatScore * 0.50 + varianceScore * 0.25 + nonWhiteScore * 0.25
        let spans = maskSpanLengths(whiteMask)
        let ringAspectRatio = spans.horizontal > 0.01 && spans.vertical > 0.01
            ? max(spans.horizontal, spans.vertical) / max(0.01, min(spans.horizontal, spans.vertical))
            : 1

        return StructureValidation(
            score: structureScore,
            seatContrast: seatContrast,
            centerDarkness: centerDarkness,
            whiteRatio: whiteRatio,
            ringAspectRatio: ringAspectRatio
        )
    }

    private static func bestSingleClassCandidate(from array: MLMultiArray) -> DetectionCandidate? {
        guard let layout = arrayLayout(array), layout.channelCount >= 5 else { return nil }
        var bestCandidate: DetectionCandidate?

        for i in 0..<layout.count {
            let x = normalizeCoordinate(read(array, layout, channel: 0, index: i))
            let y = normalizeCoordinate(read(array, layout, channel: 1, index: i))
            let w = normalizeCoordinate(read(array, layout, channel: 2, index: i))
            let h = normalizeCoordinate(read(array, layout, channel: 3, index: i))

            let confidence: Float
            if layout.channelCount == 5 {
                confidence = score(read(array, layout, channel: 4, index: i))
            } else {
                var bestClassScore: Float = 0
                for classChannel in 4..<layout.channelCount {
                    bestClassScore = max(bestClassScore, score(read(array, layout, channel: classChannel, index: i)))
                }
                confidence = bestClassScore
            }

            let candidate = DetectionCandidate(
                confidence: confidence,
                label: "toilet",
                labelConfidence: confidence,
                rawConfidence: confidence,
                centerX: x,
                centerY: y,
                width: w,
                height: h
            )
            if bestCandidate == nil || selectionScore(for: candidate) > selectionScore(for: bestCandidate!) {
                bestCandidate = candidate
            }
        }

        return bestCandidate
    }

    private static func sceneGuardResult(from observations: [VNRecognizedObjectObservation]) -> SceneGuardResult {
        var topLabel = "none"
        var topConfidence: Float = 0
        var toiletConfidence: Float = 0
        var negativeLabel = "none"
        var negativeConfidence: Float = 0

        for obs in observations {
            for label in obs.labels {
                let name = label.identifier.lowercased()
                let confidence = label.confidence
                if confidence > topConfidence {
                    topConfidence = confidence
                    topLabel = name
                }
                if name == "toilet" {
                    toiletConfidence = max(toiletConfidence, confidence)
                }
                if negativeSceneLabels.contains(name), confidence > negativeConfidence {
                    negativeConfidence = confidence
                    negativeLabel = name
                }
            }
        }

        return SceneGuardResult(
            topLabel: topLabel,
            topConfidence: topConfidence,
            toiletConfidence: toiletConfidence,
            negativeLabel: negativeLabel,
            negativeConfidence: negativeConfidence
        )
    }

    private static func sceneGuardResult(from array: MLMultiArray) -> SceneGuardResult? {
        guard let layout = arrayLayout(array), layout.channelCount >= 4 + cocoNames.count else { return nil }
        var topLabel = "none"
        var topConfidence: Float = 0
        var toiletConfidence: Float = 0
        var negativeLabel = "none"
        var negativeConfidence: Float = 0

        for i in 0..<layout.count {
            for classIndex in 0..<cocoNames.count {
                let confidence = score(read(array, layout, channel: 4 + classIndex, index: i))
                guard confidence > 0.01 else { continue }
                let label = cocoNames[classIndex]

                if confidence > topConfidence {
                    topConfidence = confidence
                    topLabel = label
                }
                if classIndex == cocoToiletIndex {
                    toiletConfidence = max(toiletConfidence, confidence)
                }
                if negativeSceneLabels.contains(label), confidence > negativeConfidence {
                    negativeConfidence = confidence
                    negativeLabel = label
                }
            }
        }

        return SceneGuardResult(
            topLabel: topLabel,
            topConfidence: topConfidence,
            toiletConfidence: toiletConfidence,
            negativeLabel: negativeLabel,
            negativeConfidence: negativeConfidence
        )
    }

    private struct ArrayLayout {
        let channelCount: Int
        let count: Int
        let strideBatch: Int
        let strideChannel: Int
        let strideIndex: Int
    }

    private static func arrayLayout(_ array: MLMultiArray) -> ArrayLayout? {
        guard array.dataType == .float32 || array.dataType == .float16 else { return nil }
        guard array.shape.count == 3 else { return nil }
        let d1 = array.shape[1].intValue
        let d2 = array.shape[2].intValue

        if d1 >= 5 && d2 > d1 {
            return ArrayLayout(
                channelCount: d1,
                count: d2,
                strideBatch: array.strides[0].intValue,
                strideChannel: array.strides[1].intValue,
                strideIndex: array.strides[2].intValue
            )
        } else if d2 >= 5 && d1 > d2 {
            return ArrayLayout(
                channelCount: d2,
                count: d1,
                strideBatch: array.strides[0].intValue,
                strideChannel: array.strides[2].intValue,
                strideIndex: array.strides[1].intValue
            )
        }

        return nil
    }

    private static func read(_ array: MLMultiArray, _ layout: ArrayLayout, channel: Int, index: Int) -> Float {
        let offset = channel * layout.strideChannel + index * layout.strideIndex
        if array.dataType == .float32 {
            let ptr = UnsafeMutablePointer<Float>(OpaquePointer(array.dataPointer))
            return ptr[offset]
        } else {
            let ptr = UnsafeMutablePointer<UInt16>(OpaquePointer(array.dataPointer))
            return Float(Float16(bitPattern: ptr[offset]))
        }
    }

    private static func normalizeCoordinate(_ raw: Float) -> Float {
        let normalized = raw > 1.5 ? (raw / 448) : raw
        return clamp01(normalized)
    }

    private static func score(_ raw: Float) -> Float {
        if raw < 0 || raw > 1 {
            return 1 / (1 + exp(-raw))
        }
        return raw
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
