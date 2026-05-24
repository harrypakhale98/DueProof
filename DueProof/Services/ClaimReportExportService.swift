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
            "Proof Count",
            "Created",
            "Updated",
            "Notes"
        ]

        let rows = claims
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .map(row)

        let csv = ([header] + rows)
            .map { $0.map(Self.escape).joined(separator: ",") }
            .joined(separator: "\n")

        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: "DueProof-Claims-Report.csv",
            data: Data(csv.utf8)
        )
    }

    private func row(for claim: Claim) -> [String] {
        [
            claim.title,
            claim.categoryDisplayName,
            claim.merchant ?? "",
            claim.statusDisplayName,
            CurrencyFormatter.editingString(claim.valueAtRisk),
            CurrencyFormatter.editingString(claim.recoveredValue),
            claim.deadline.map(DateHelpers.fullDate) ?? "",
            claim.reminderDate.map(DateHelpers.fullDate) ?? "",
            "\(claim.proofItemsList.count)",
            DateHelpers.fullDate(claim.createdAt),
            DateHelpers.fullDate(claim.updatedAt),
            claim.notes
        ]
    }

    private static func escape(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let needsQuotes = normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n")
        let escaped = normalized.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
