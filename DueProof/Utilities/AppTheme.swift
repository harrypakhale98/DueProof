import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 20
    static let compactCornerRadius: CGFloat = 16
    static let minimumTapTarget: CGFloat = 44
    static let brandTint = Color.accentColor
    static let receiptAqua = Color(red: 0.48, green: 0.79, blue: 0.81)
    static let receiptSky = Color(red: 0.60, green: 0.78, blue: 0.89)
    static let receiptMist = Color(red: 0.95, green: 0.97, blue: 0.98)

    static func categoryColor(_ category: ClaimCategory) -> Color {
        switch category {
        case .returnItem: brandTint
        case .giftCard: .teal
        case .warranty: .cyan
        case .reimbursement: .green
        case .rebate: .mint
        case .subscription: .orange
        case .renewal: brandTint
        case .document: .gray
        case .other: .secondary
        }
    }

    static func urgencyColor(for claim: Claim) -> Color {
        if claim.isExpired { return .red }
        if claim.isOverdue { return .red }
        if claim.isUrgent { return .orange }
        return claim.status.effectiveTintColor
    }
}

private extension ClaimStatus {
    var effectiveTintColor: Color {
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

extension View {
    func dueProofCardBackground(cornerRadius: CGFloat = AppTheme.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return background(.regularMaterial, in: shape)
            .overlay {
                shape.strokeBorder(.quaternary, lineWidth: 0.5)
            }
    }

    func dueProofGlassButton(cornerRadius: CGFloat = 999, tint: Color? = nil) -> some View {
        glassEffect(
            .regular.tint(tint).interactive(),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
