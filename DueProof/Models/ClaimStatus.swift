import Foundation
import SwiftUI

enum ClaimStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case active
    case urgent
    case overdue
    case recovered
    case used
    case expired
    case ignored

    var id: String { rawValue }

    static let editableCases: [ClaimStatus] = [.active, .recovered, .used, .expired, .ignored]

    static func normalizedStoredStatus(_ status: ClaimStatus) -> ClaimStatus {
        switch status {
        case .urgent, .overdue:
            return .active
        case .active, .recovered, .used, .expired, .ignored:
            return status
        }
    }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .urgent: "Urgent"
        case .overdue: "Overdue"
        case .recovered: "Recovered"
        case .used: "Used"
        case .expired: "Expired"
        case .ignored: "Ignored"
        }
    }

    var isOpen: Bool {
        self == .active || self == .urgent || self == .overdue
    }

    var isComplete: Bool {
        switch self {
        case .recovered, .used, .expired, .ignored: true
        case .active, .urgent, .overdue: false
        }
    }

    var symbolName: String {
        switch self {
        case .active: "circle"
        case .urgent: "exclamationmark.circle.fill"
        case .overdue: "clock.badge.exclamationmark.fill"
        case .recovered: "checkmark.circle.fill"
        case .used: "checkmark.seal.fill"
        case .expired: "xmark.circle.fill"
        case .ignored: "minus.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .active: AppTheme.brandTint
        case .urgent: .orange
        case .overdue: .red
        case .recovered: .green
        case .used: AppTheme.brandTint
        case .expired: .red
        case .ignored: .secondary
        }
    }
}
