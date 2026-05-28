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
        let context = ActionPlanContext(claim: claim)
        let proofText = claim.proofItemsList.isEmpty
            ? "Attach at least one receipt, document, screenshot, or note before contacting support."
            : "\(claim.proofItemsList.count) proof item\(claim.proofItemsList.count == 1 ? "" : "s") attached."

        return ClaimActionPlan(
            headline: headline(for: claim),
            nextStep: nextStep(for: claim, context: context, proofText: proofText),
            checklist: checklist(for: claim, context: context, proofText: proofText),
            messageSubject: messageSubject(for: claim, context: context),
            messageBody: messageBody(for: claim, context: context)
        )
    }

    func exportMessage(for claim: Claim) throws -> URL {
        let plan = plan(for: claim)
        let context = ActionPlanContext(claim: claim)
        let data = Data(plan.exportText.utf8)
        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: "\(context.title)-claim-message.txt",
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

    private func nextStep(for claim: Claim, context: ActionPlanContext, proofText: String) -> String {
        if context.hasUsableDeadline, claim.isOverdue {
            return "Review \(context.title) now. It is overdue, so lead with the proof and ask whether the claim can still be honored."
        }

        if context.hasUsableDeadline, claim.isUrgent {
            return "Act before \(context.deadlineText). \(proofText)"
        }

        if !context.hasUsableDeadline {
            if claim.proofItemsList.isEmpty {
                let deadlineAction = context.hasStoredDeadline ? "Confirm the saved deadline" : "Set a deadline"
                return "\(deadlineAction) and attach proof for \(context.title). \(claim.displayValue) is at risk."
            }

            return "Confirm the deadline for \(context.title). \(proofText)"
        }

        if claim.proofItemsList.isEmpty {
            return "Attach proof before the deadline. \(context.title) has \(claim.displayValue) at risk."
        }

        return "Keep proof ready and act before \(context.deadlineText)."
    }

    private func checklist(for claim: Claim, context: ActionPlanContext, proofText: String) -> [String] {
        var items = baseChecklist(for: claim.category)

        if claim.proofItemsList.isEmpty {
            items.insert("Attach proof before sending the claim.", at: 0)
        } else {
            items.insert(proofText, at: 0)
        }

        if !context.hasUsableDeadline {
            items.append("Confirm the deadline before relying on this claim.")
        }

        if CurrencyFormatter.sanitizedAmount(claim.valueAtRisk) > 0 {
            items.append("Confirm the value at risk: \(claim.displayValue).")
        }

        if let merchant = context.merchant {
            items.append("Verify the merchant or provider: \(merchant).")
        }

        if let identifier = context.reference {
            items.append("Keep this reference ready: \(identifier).")
        }

        if context.policySummary != nil {
            items.append("Review the saved policy note before acting.")
        }

        if claim.actionURL != nil {
            items.append("Use the saved action link for support, cancellation, or submission.")
        }

        return Array(items.prefix(9))
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

    private func messageSubject(for claim: Claim, context: ActionPlanContext) -> String {
        let merchant = context.merchant.map { "\($0) " } ?? ""
        return "\(merchant)\(claim.categoryDisplayName) - \(context.title)"
    }

    private func messageBody(for claim: Claim, context: ActionPlanContext) -> String {
        let merchantLine = context.merchant.map { "Provider: \($0)\n" } ?? ""
        let referenceLine = context.reference.map { "Reference: \($0)\n" } ?? ""
        let policyLine = context.policySummary.map { "Policy note: \($0)\n" } ?? ""
        let actionLine = claim.actionURL.map { "Action link: \($0.absoluteString)\n" } ?? ""
        let proofLine = claim.proofItemsList.isEmpty
            ? "I can provide proof of purchase or supporting documents if needed."
            : "I have attached the relevant proof for review."

        return """
        Hello,

        I am following up about \(context.title).

        \(merchantLine)Claim type: \(claim.categoryDisplayName)
        Value at risk: \(claim.displayValue)
        Deadline: \(context.deadlineText)
        \(referenceLine)\(policyLine)\(actionLine)Current status: \(claim.statusDisplayName)

        \(proofLine)

        Please confirm the next step needed to complete this \(claim.categoryDisplayName.lowercased()).

        Thank you.
        """
    }
}

private struct ActionPlanContext {
    let title: String
    let merchant: String?
    let reference: String?
    let policySummary: String?
    let deadlineText: String
    let hasStoredDeadline: Bool
    let hasUsableDeadline: Bool

    init(claim: Claim) {
        title = Self.inlineText(claim.title, limit: ClaimTextLimits.title) ?? "Untitled claim"
        merchant = Self.inlineText(claim.merchant, limit: ClaimTextLimits.merchant)
        reference = Self.inlineText(claim.primaryReference, limit: ClaimTextLimits.reference)
        policySummary = Self.inlineText(claim.policySummary, limit: ClaimTextLimits.policySummary)
        hasStoredDeadline = claim.deadline != nil
        hasUsableDeadline = claim.deadline?.timeIntervalSinceReferenceDate.isFinite == true
        deadlineText = DateHelpers.deadlineText(for: claim.deadline)
    }

    private static func inlineText(_ value: String?, limit: Int) -> String? {
        let normalized = ClaimTextLimits.required(value ?? "", limit: limit)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}
