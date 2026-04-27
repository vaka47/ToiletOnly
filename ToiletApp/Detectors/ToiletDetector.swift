import Foundation
import AVFoundation
import Vision
import CoreML

protocol ToiletDetecting {
    func process(pixelBuffer: CVPixelBuffer, completion: @escaping (Bool, Float) -> Void)
}

final class ToiletDetector: ToiletDetecting {
    private let queue = DispatchQueue(label: "toilet.detector.queue")
    private let model: VNCoreMLModel?

    init() {
        if let modelURL = Bundle.main.url(forResource: "ToiletDetector", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: modelURL) {
            model = try? VNCoreMLModel(for: mlModel)
        } else {
            model = nil
        }
    }

    func process(pixelBuffer: CVPixelBuffer, completion: @escaping (Bool, Float) -> Void) {
        guard let model else {
            completion(false, 0)
            return
        }

        let request = VNCoreMLRequest(model: model) { request, _ in
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            let best = observations
                .flatMap { $0.labels }
                .max(by: { $0.confidence < $1.confidence })

            let isToilet = observations.contains { obs in
                obs.labels.contains { label in
                    let name = label.identifier.lowercased()
                    return name.contains("toilet") || name.contains("wc") || name.contains("commode")
                }
            }

            completion(isToilet, best?.confidence ?? 0)
        }

        request.imageCropAndScaleOption = .centerCrop

        queue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }
}
