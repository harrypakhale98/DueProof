import Foundation

enum CurrencyFormatter {
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

    static func string(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func editingString(_ value: Double) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: Locale.current.currencySymbol ?? "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let number = decimalFormatter.number(from: cleaned) {
            return number.doubleValue
        }

        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }
}
