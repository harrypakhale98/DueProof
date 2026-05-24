import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

final class OCRService {
    static let shared = OCRService()

    private init() {}

    func recognizeText(at imageURL: URL) async -> OCRResult {
        guard imageURL.isFileURL, let image = UIImage(contentsOfFile: imageURL.path) else {
            return OCRResult(warnings: ["DueProof could not read that local proof image."])
        }

        return await recognizeText(in: image)
    }

    func searchableText(at fileURL: URL, type: ProofItemType) async -> String? {
        guard fileURL.isFileURL else { return nil }

        switch type {
        case .photo:
            let result = await recognizeText(at: fileURL)
            return normalizedSearchText(result.text)
        case .document:
            return normalizedSearchText(pdfText(at: fileURL))
        case .note:
            return nil
        }
    }

    func recognizeText(in image: UIImage) async -> OCRResult {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else {
                return OCRResult(warnings: ["DueProof could not prepare that image for text recognition."])
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                return OCRResult(warnings: ["Text recognition could not finish for that proof image."])
            }

            let lines = (request.results ?? []).compactMap { observation -> OCRResult.RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return OCRResult.RecognizedLine(text: text, confidence: Double(candidate.confidence))
            }

            let combinedText = lines.map(\.text).joined(separator: "\n")
            let confidences = lines.compactMap(\.confidence)
            let averageConfidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)

            return OCRResult(
                text: combinedText,
                lines: lines,
                averageConfidence: averageConfidence,
                warnings: combinedText.isEmpty ? ["No readable text was found in that proof image."] : []
            )
        }.value
    }

    private func pdfText(at url: URL) -> String {
        PDFDocument(url: url)?.string ?? ""
    }

    private func normalizedSearchText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(12_000))
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
