import SwiftUI

struct QuickAddGridView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onSelect: (ClaimCategory) -> Void

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 10)]
        }

        return Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }

    private let categories: [ClaimCategory] = [
        .returnItem,
        .giftCard,
        .warranty,
        .reimbursement,
        .rebate,
        .subscription,
        .renewal,
        .document
    ]

    private var buttonHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 118 : 86
    }

    private var iconSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 34 : 30
    }

    private var tilePadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 14 : 12
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(categories) { category in
                Button {
                    onSelect(category)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: category.iconName)
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppTheme.categoryColor(category))
                            .frame(width: iconSize, height: iconSize)
                            .background(AppTheme.categoryColor(category).opacity(0.12), in: Circle())
                            .accessibilityHidden(true)

                        Spacer(minLength: 6)

                        Text(buttonTitle(for: category))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)
                            .allowsTightening(true)
                    }
                    .padding(tilePadding)
                    .frame(height: buttonHeight, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(buttonTitle(for: category))
            }
        }
    }

    private func buttonTitle(for category: ClaimCategory) -> String {
        switch category {
        case .returnItem: "Add Return"
        case .giftCard: "Add Gift Card"
        case .warranty: "Add Warranty"
        case .reimbursement: "Add Reimbursement"
        case .subscription: "Add Trial"
        case .renewal: "Add Renewal"
        case .rebate: "Add Rebate"
        case .document: "Add Document"
        case .other: "Add Claim"
        }
    }
}

#Preview {
    QuickAddGridView { _ in }
        .padding()
}
