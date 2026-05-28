import Foundation

enum OCRResultLimits {
    static let text = 12_000
    static let lineText = 500
    static let maximumLines = 300
    static let barcodeValue = 120
    static let barcodeSymbology = 40
    static let maximumBarcodes = 20
    static let warning = 160
    static let maximumWarnings = 8

    static func confidence(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

struct OCRResult: Equatable {
    struct RecognizedLine: Identifiable, Equatable {
        let id: UUID
        var text: String
        var confidence: Double?

        init(id: UUID = UUID(), text: String, confidence: Double? = nil) {
            self.id = id
            self.text = ClaimTextLimits.required(text, limit: OCRResultLimits.lineText)
            self.confidence = OCRResultLimits.confidence(confidence)
        }
    }

    struct RecognizedBarcode: Identifiable, Equatable {
        let id: UUID
        var value: String
        var symbology: String
        var confidence: Double?

        init(id: UUID = UUID(), value: String, symbology: String, confidence: Double? = nil) {
            self.id = id
            self.value = ClaimTextLimits.required(value, limit: OCRResultLimits.barcodeValue)
            self.symbology = ClaimTextLimits.required(symbology, limit: OCRResultLimits.barcodeSymbology)
            self.confidence = OCRResultLimits.confidence(confidence)
        }
    }

    var text: String
    var lines: [RecognizedLine]
    var barcodes: [RecognizedBarcode]
    var averageConfidence: Double?
    var warnings: [String]

    init(
        text: String = "",
        lines: [RecognizedLine] = [],
        barcodes: [RecognizedBarcode] = [],
        averageConfidence: Double? = nil,
        warnings: [String] = []
    ) {
        let normalizedLines = Self.normalizedLines(lines)
        let normalizedText = Self.normalizedSearchableText(text)
        self.text = normalizedText.isEmpty
            ? Self.normalizedSearchableText(normalizedLines.map(\.text).joined(separator: "\n"))
            : normalizedText
        self.lines = normalizedLines
        self.barcodes = Self.normalizedBarcodes(barcodes)
        self.averageConfidence = OCRResultLimits.confidence(averageConfidence) ?? Self.averageConfidence(from: normalizedLines)
        self.warnings = Self.normalizedWarnings(warnings)
    }

    var searchableText: String {
        let barcodeLines = barcodes.map { barcode in
            "Barcode \(barcode.symbology): \(barcode.value)"
        }
        let combined = ([text] + barcodeLines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Self.normalizedSearchableText(combined)
    }

    var isEmpty: Bool {
        searchableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func normalizedSearchableText(_ text: String) -> String {
        ClaimTextLimits.required(text, limit: OCRResultLimits.text)
    }

    private static func normalizedLines(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        lines
            .map { RecognizedLine(id: $0.id, text: $0.text, confidence: $0.confidence) }
            .filter { !$0.text.isEmpty }
            .prefix(OCRResultLimits.maximumLines)
            .map { $0 }
    }

    private static func normalizedBarcodes(_ barcodes: [RecognizedBarcode]) -> [RecognizedBarcode] {
        var seenValues = Set<String>()
        return barcodes.compactMap { barcode in
            let normalized = RecognizedBarcode(
                id: barcode.id,
                value: barcode.value,
                symbology: barcode.symbology,
                confidence: barcode.confidence
            )
            guard !normalized.value.isEmpty, seenValues.insert(normalized.value).inserted else { return nil }
            return normalized
        }
        .prefix(OCRResultLimits.maximumBarcodes)
        .map { $0 }
    }

    private static func normalizedWarnings(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.compactMap { warning in
            let normalized = ClaimTextLimits.required(warning, limit: OCRResultLimits.warning)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .prefix(OCRResultLimits.maximumWarnings)
        .map { $0 }
    }

    private static func averageConfidence(from lines: [RecognizedLine]) -> Double? {
        let confidences = lines.compactMap(\.confidence)
        guard !confidences.isEmpty else { return nil }
        return confidences.reduce(0, +) / Double(confidences.count)
    }
}
