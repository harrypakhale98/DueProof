import Foundation

enum ClaimCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case returnItem
    case giftCard
    case warranty
    case reimbursement
    case rebate
    case subscription
    case renewal
    case document
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .returnItem: "Return"
        case .giftCard: "Gift Card"
        case .warranty: "Warranty"
        case .reimbursement: "Reimbursement"
        case .rebate: "Rebate"
        case .subscription: "Subscription"
        case .renewal: "Renewal"
        case .document: "Document"
        case .other: "Other"
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .returnItem: "Returns"
        case .giftCard: "Gift Cards"
        case .warranty: "Warranties"
        case .reimbursement: "Reimbursements"
        case .rebate: "Rebates"
        case .subscription: "Subscriptions"
        case .renewal: "Renewals"
        case .document: "Documents"
        case .other: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .returnItem: "arrow.uturn.backward.circle.fill"
        case .giftCard: "giftcard.fill"
        case .warranty: "shield.lefthalf.filled"
        case .reimbursement: "cross.case.fill"
        case .rebate: "tag.fill"
        case .subscription: "clock.arrow.circlepath"
        case .renewal: "arrow.triangle.2.circlepath.circle.fill"
        case .document: "doc.text.fill"
        case .other: "tray.fill"
        }
    }

    var tintSymbolName: String {
        switch self {
        case .returnItem: "shippingbox.fill"
        case .giftCard: "sparkles"
        case .warranty: "checkmark.shield.fill"
        case .reimbursement: "banknote.fill"
        case .rebate: "percent"
        case .subscription: "calendar.badge.clock"
        case .renewal: "repeat.circle.fill"
        case .document: "doc.badge.clock"
        case .other: "circle.grid.2x2.fill"
        }
    }
}
