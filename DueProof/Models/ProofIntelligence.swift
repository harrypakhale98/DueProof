import Foundation

struct ProofIntelligence: Codable, Equatable {
    var merchant: String?
    var category: ClaimCategory?
    var valueAtRisk: Double?
    var purchaseDate: Date?
    var deadline: Date?
    var deadlineIsExplicit: Bool
    var orderNumber: String?
    var confidence: Double
    var warnings: [String]
    var summary: String
    var completeness: ProofCompleteness

    var deadlineLabel: String {
        guard deadline != nil else { return "No deadline found" }
        return deadlineIsExplicit ? "Deadline found in proof" : "Deadline suggested"
    }
}

struct ProofCompleteness: Codable, Equatable {
    var score: Double
    var hasMerchant: Bool
    var hasValue: Bool
    var hasPurchaseDate: Bool
    var hasDeadline: Bool
    var hasReadableText: Bool
    var missingFields: [String]

    var displayPercent: String {
        "\(Int((score * 100).rounded()))%"
    }
}
