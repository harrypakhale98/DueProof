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

    var text: String
    var lines: [RecognizedLine]
    var averageConfidence: Double?
    var warnings: [String]

    init(
        text: String = "",
        lines: [RecognizedLine] = [],
        averageConfidence: Double? = nil,
        warnings: [String] = []
    ) {
        self.text = text
        self.lines = lines
        self.averageConfidence = averageConfidence
        self.warnings = warnings
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
