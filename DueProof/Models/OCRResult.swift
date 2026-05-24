import Foundation

struct OCRResult: Equatable {
    struct RecognizedLine: Identifiable, Equatable {
        let id: UUID
        var text: String
        var confidence: Double?

        init(id: UUID = UUID(), text: String, confidence: Double? = nil) {
            self.id = id
            self.text = text
            self.confidence = confidence
        }
    }

    struct RecognizedBarcode: Identifiable, Equatable {
        let id: UUID
        var value: String
        var symbology: String
        var confidence: Double?

        init(id: UUID = UUID(), value: String, symbology: String, confidence: Double? = nil) {
            self.id = id
            self.value = value
            self.symbology = symbology
            self.confidence = confidence
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
        self.text = text
        self.lines = lines
        self.barcodes = barcodes
        self.averageConfidence = averageConfidence
        self.warnings = warnings
    }

    var searchableText: String {
        let barcodeLines = barcodes.map { barcode in
            "Barcode \(barcode.symbology): \(barcode.value)"
        }
        return ([text] + barcodeLines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var isEmpty: Bool {
        searchableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
