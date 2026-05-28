import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

final class OCRService {
    static let shared = OCRService()
    static let maximumPreparedImagePixelSize = 2_400
    private static let maximumSearchableTextCharacters = OCRResultLimits.text

    private init() {}

    func recognizeText(at imageURL: URL) async -> OCRResult {
        guard imageURL.isFileURL,
              let data = try? DueProofBoundedFileReader.data(
                at: imageURL,
                maximumBytes: FileStorageService.maximumProofFileBytes,
                tooLargeError: FileStorageError.proofFileTooLarge
              ),
              let image = preparedImage(from: data)
        else {
            return OCRResult(warnings: ["DueProof could not read that local proof image."])
        }

        return await recognizeText(in: image)
    }

    func searchableText(at fileURL: URL, type: ProofItemType) async -> String? {
        guard fileURL.isFileURL else { return nil }

        switch type {
        case .photo:
            let result = await recognizeText(at: fileURL)
            return normalizedSearchText(result.searchableText)
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

            let barcodeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )

            do {
                try handler.perform([request, barcodeRequest])
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
            let barcodes = Self.recognizedBarcodes(from: barcodeRequest.results ?? [])
            let warnings = combinedText.isEmpty && barcodes.isEmpty
                ? ["No readable text or barcode was found in that proof image."]
                : []

            return OCRResult(
                text: combinedText,
                lines: lines,
                barcodes: barcodes,
                averageConfidence: averageConfidence,
                warnings: warnings
            )
        }.value
    }

    func recognizeText(inImageData data: Data) async -> OCRResult {
        guard let image = preparedImage(from: data) else {
            return OCRResult(warnings: ["DueProof could not prepare that image for text recognition."])
        }

        return await recognizeText(in: image)
    }

    func preparedImage(from data: Data, maxPixelSize: Int = OCRService.maximumPreparedImagePixelSize) -> UIImage? {
        guard maxPixelSize > 0 else { return nil }
        let pixelSize = min(maxPixelSize, Self.maximumPreparedImagePixelSize)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func recognizedBarcodes(from observations: [VNBarcodeObservation]) -> [OCRResult.RecognizedBarcode] {
        var seenValues = Set<String>()

        return observations.compactMap { observation in
            guard let value = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seenValues.insert(value).inserted
            else {
                return nil
            }

            return OCRResult.RecognizedBarcode(
                value: String(value.prefix(120)),
                symbology: observation.symbology.rawValue,
                confidence: Double(observation.confidence)
            )
        }
    }

    private func pdfText(at url: URL) -> String {
        guard let data = try? DueProofBoundedFileReader.data(
            at: url,
            maximumBytes: FileStorageService.maximumProofFileBytes,
            tooLargeError: FileStorageError.proofFileTooLarge
        ),
              let document = PDFDocument(data: data)
        else {
            return ""
        }

        var text = ""
        for pageIndex in 0..<document.pageCount {
            guard text.count < Self.maximumSearchableTextCharacters else { break }
            guard let pageText = document.page(at: pageIndex)?.string else { continue }

            if !text.isEmpty {
                text.append("\n")
            }
            let remainingCharacters = Self.maximumSearchableTextCharacters - text.count
            text.append(String(pageText.prefix(max(0, remainingCharacters))))
        }

        return text
    }

    private func normalizedSearchText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Self.maximumSearchableTextCharacters))
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
