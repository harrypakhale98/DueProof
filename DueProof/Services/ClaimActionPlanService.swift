import Foundation

struct ClaimActionPlan: Equatable {
    let headline: String
    let nextStep: String
    let checklist: [String]
    let messageSubject: String
    let messageBody: String

    var exportText: String {
        ([headline, nextStep, "", "Checklist:"] + checklist.map { "- \($0)" } + ["", "Message subject:", messageSubject, "", "Message body:", messageBody])
            .joined(separator: "\n")
    }
}

final class ClaimActionPlanService {
    static let shared = ClaimActionPlanService()

    private init() {}

    func plan(for claim: Claim) -> ClaimActionPlan {
        let deadlineText = DateHelpers.deadlineText(for: claim.deadline)
        let proofText = claim.proofItems.isEmpty
            ? "Attach at least one receipt, document, screenshot, or note before contacting support."
            : "\(claim.proofItems.count) proof item\(claim.proofItems.count == 1 ? "" : "s") attached."

        return ClaimActionPlan(
            headline: headline(for: claim),
            nextStep: nextStep(for: claim, deadlineText: deadlineText, proofText: proofText),
            checklist: checklist(for: claim, proofText: proofText),
            messageSubject: messageSubject(for: claim),
            messageBody: messageBody(for: claim, deadlineText: deadlineText)
        )
    }

    func exportMessage(for claim: Claim) throws -> URL {
        let plan = plan(for: claim)
        let data = Data(plan.exportText.utf8)
        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: "\(claim.title)-claim-message.txt",
            data: data
        )
    }

    private func headline(for claim: Claim) -> String {
        switch claim.category {
        case .returnItem:
            "Return request ready"
        case .giftCard:
            "Gift card proof ready"
        case .warranty:
            "Warranty claim ready"
        case .reimbursement:
            "Reimbursement request ready"
        case .rebate:
            "Rebate follow-up ready"
        case .subscription:
            "Cancellation proof ready"
        case .renewal:
            "Renewal review ready"
        case .document:
            "Document deadline ready"
        case .other:
            "Claim action ready"
        }
    }

    private func nextStep(for claim: Claim, deadlineText: String, proofText: String) -> String {
        if claim.isOverdue {
            return "Review \(claim.title) now. It is overdue, so lead with the proof and ask whether the claim can still be honored."
        }

        if claim.isUrgent {
            return "Act before \(deadlineText). \(proofText)"
        }

        if claim.proofItems.isEmpty {
            return "Attach proof before the deadline. \(claim.title) has \(claim.displayValue) at risk."
        }

        return "Keep proof ready and act before \(deadlineText)."
    }

    private func checklist(for claim: Claim, proofText: String) -> [String] {
        var items = baseChecklist(for: claim.category)

        if claim.proofItems.isEmpty {
            items.insert("Attach proof before sending the claim.", at: 0)
        } else {
            items.insert(proofText, at: 0)
        }

        if claim.deadline == nil {
            items.append("Confirm the deadline before relying on this claim.")
        }

        if claim.valueAtRisk > 0 {
            items.append("Confirm the value at risk: \(claim.displayValue).")
        }

        if let merchant = claim.merchant {
            items.append("Verify the merchant or provider: \(merchant).")
        }

        return Array(items.prefix(7))
    }

    private func baseChecklist(for category: ClaimCategory) -> [String] {
        switch category {
        case .returnItem:
            [
                "Confirm the item is inside the return window.",
                "Keep the receipt, order number, and item photos together.",
                "Check whether the merchant requires original packaging."
            ]
        case .giftCard:
            [
                "Confirm the balance before use.",
                "Keep the card number, PIN, and purchase proof ready.",
                "Check whether any expiration or inactivity terms apply."
            ]
        case .warranty:
            [
                "Gather purchase proof, serial number, and product photos.",
                "Describe the issue clearly and when it started.",
                "Check whether the warranty covers parts, labor, shipping, or replacement."
            ]
        case .reimbursement:
            [
                "Attach receipt proof and any required claim form.",
                "Confirm the submission channel and recipient.",
                "Keep a copy of what you submit."
            ]
        case .rebate:
            [
                "Confirm required UPC, receipt, promotion code, and form.",
                "Submit before the offer deadline.",
                "Save confirmation after submission."
            ]
        case .subscription:
            [
                "Confirm cancellation terms before the charge date.",
                "Save cancellation confirmation.",
                "Screenshot any support chat or email confirmation."
            ]
        case .renewal:
            [
                "Review renewal price and terms.",
                "Confirm cancellation or update deadline.",
                "Save proof of any plan change."
            ]
        case .document:
            [
                "Confirm the document is the latest version.",
                "Check who needs to receive or review it.",
                "Keep supporting proof attached."
            ]
        case .other:
            [
                "Confirm the deadline and required proof.",
                "Keep a copy of anything submitted.",
                "Save confirmation after action."
            ]
        }
    }

    private func messageSubject(for claim: Claim) -> String {
        let merchant = claim.merchant.map { "\($0) " } ?? ""
        return "\(merchant)\(claim.categoryDisplayName) - \(claim.title)"
    }

    private func messageBody(for claim: Claim, deadlineText: String) -> String {
        let merchantLine = claim.merchant.map { "Provider: \($0)\n" } ?? ""
        let proofLine = claim.proofItems.isEmpty
            ? "I can provide proof of purchase or supporting documents if needed."
            : "I have attached the relevant proof for review."

        return """
        Hello,

        I am following up about \(claim.title).

        \(merchantLine)Claim type: \(claim.categoryDisplayName)
        Value at risk: \(claim.displayValue)
        Deadline: \(deadlineText)
        Current status: \(claim.statusDisplayName)

        \(proofLine)

        Please confirm the next step needed to complete this \(claim.categoryDisplayName.lowercased()).

        Thank you.
        """
    }
}
