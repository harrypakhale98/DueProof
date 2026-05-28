import Foundation

final class ClaimReportExportService {
    static let shared = ClaimReportExportService()

    private init() {}

    func exportCSV(claims: [Claim]) throws -> URL {
        let header = [
            "Title",
            "Category",
            "Merchant",
            "Status",
            "Value At Risk",
            "Recovered Value",
            "Deadline",
            "Reminder",
            "Reference",
            "Policy Summary",
            "Action URL",
            "Proof Count",
            "Created",
            "Updated",
            "Notes"
        ]

        let rows = claims
            .sorted { ClaimListOrdering.deadlineSoonest($0, $1) }
            .map(row)

        let csv = ([header] + rows)
            .map { $0.map(Self.safeCell).map(Self.escape).joined(separator: ",") }
            .joined(separator: "\n")

        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: "DueProof-Claims-Report.csv",
            data: Data(csv.utf8)
        )
    }

    private func row(for claim: Claim) -> [String] {
        let title = normalizedRequired(claim.title, limit: ClaimTextLimits.title, fallback: "Untitled claim")
        let merchant = ClaimTextLimits.optional(claim.merchant, limit: ClaimTextLimits.merchant) ?? ""
        let policySummary = ClaimTextLimits.required(claim.policySummary, limit: ClaimTextLimits.policySummary)
        let notes = ClaimTextLimits.required(claim.notes, limit: ClaimTextLimits.notes)

        return [
            title,
            claim.categoryDisplayName,
            merchant,
            claim.statusDisplayName,
            CurrencyFormatter.editingString(claim.valueAtRisk),
            CurrencyFormatter.editingString(claim.recoveredValue),
            claim.deadline.map(DateHelpers.fullDateTime) ?? "",
            claim.reminderDate.map(DateHelpers.fullDateTime) ?? "",
            claim.primaryReference ?? "",
            policySummary,
            claim.actionURL?.absoluteString ?? "",
            "\(claim.proofItemsList.count)",
            DateHelpers.fullDateTime(claim.createdAt),
            DateHelpers.fullDateTime(claim.updatedAt),
            notes
        ]
    }

    private func normalizedRequired(_ value: String, limit: Int, fallback: String) -> String {
        let normalized = ClaimTextLimits.required(value, limit: limit)
        return normalized.isEmpty ? fallback : normalized
    }

    private static func escape(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let needsQuotes = normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n")
        let escaped = normalized.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    private static func safeCell(_ value: String) -> String {
        guard let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first,
              ["=", "+", "-", "@", "\t"].contains(first)
        else {
            return value
        }

        return "'\(value)"
    }
}
