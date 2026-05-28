import Foundation

enum CurrencyFormatter {
    static let maximumSupportedAmount = 999_999_999.99
    private static let maximumInputCharacters = 32

    static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func sanitizedAmount(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(0, value), maximumSupportedAmount)
    }

    static func string(_ value: Double) -> String {
        let amount = sanitizedAmount(value)
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    static func editingString(_ value: Double) -> String {
        let amount = sanitizedAmount(value)
        return decimalFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumInputCharacters else {
            return nil
        }

        let cleaned = trimmed
            .replacingOccurrences(of: Locale.current.currencySymbol ?? "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let number = decimalFormatter.number(from: cleaned) {
            let value = number.doubleValue
            return normalizedParsedAmount(value)
        }

        return normalizedParsedAmount(Double(cleaned.replacingOccurrences(of: ",", with: ".")))
    }

    private static func normalizedParsedAmount(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= maximumSupportedAmount
        else {
            return nil
        }
        return value
    }
}
