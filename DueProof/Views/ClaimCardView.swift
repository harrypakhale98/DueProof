import SwiftUI

struct ClaimCardView: View {
    enum Style {
        case row
        case attention
        case detailHeader
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let claim: Claim
    var style: Style = .row

    var body: some View {
        switch style {
        case .row:
            rowLayout
        case .attention:
            attentionLayout
        case .detailHeader:
            detailHeaderLayout
        }
    }

    private var rowLayout: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                rowAccessibilityLayout
            } else {
                rowStandardLayout
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var rowStandardLayout: some View {
        HStack(spacing: 14) {
            categoryIcon(size: 44, font: .title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text(claim.title)
                    .font(.headline)
                    .lineLimit(2)

                compactMetadataLine
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 7) {
                Text(claim.displayValue)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                StatusPillView(status: claim.effectiveStatus)
            }
        }
        .padding(.vertical, 8)
    }

    private var rowAccessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                categoryIcon(size: 44, font: .title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 5) {
                    Text(claim.title)
                        .font(.headline)
                        .lineLimit(3)

                    compactMetadataLine
                }
            }

            HStack {
                Text(claim.displayValue)
                    .font(.headline)
                    .monospacedDigit()

                Spacer()

                StatusPillView(status: claim.effectiveStatus)
            }
        }
        .padding(.vertical, 8)
    }

    private var attentionLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                categoryIcon(size: 38, font: .headline.weight(.semibold))

                Spacer()

                urgencyLabel
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(claim.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 44, alignment: .topLeading)

                if let merchant = claim.merchant, !merchant.isEmpty {
                    Text(merchant)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text(claim.displayValue)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                proofReminderLine
            }
        }
        .padding(16)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 260 : 220, alignment: .leading)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 210 : 174, alignment: .leading)
        .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens claim details")
    }

    private var detailHeaderLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                categoryIcon(size: 52, font: .title2.weight(.semibold))

                Spacer()

                StatusPillView(status: claim.effectiveStatus)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(claim.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                if let merchant = claim.merchant, !merchant.isEmpty {
                    Text(merchant)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    valueBlock
                    deadlineBlock(alignment: .leading, textAlignment: .leading)
                }
            } else {
                HStack(alignment: .lastTextBaseline) {
                    valueBlock
                    Spacer(minLength: 16)
                    deadlineBlock(alignment: .trailing, textAlignment: .trailing)
                }
            }

            proofReminderLine
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dueProofCardBackground(cornerRadius: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func categoryIcon(size: CGFloat, font: Font) -> some View {
        Image(systemName: claim.categoryIcon)
            .font(font)
            .foregroundStyle(AppTheme.categoryColor(claim.category))
            .frame(width: size, height: size)
            .background(AppTheme.categoryColor(claim.category).opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    private var compactMetadataLine: some View {
        HStack(spacing: 6) {
            Text(claim.merchant?.isEmpty == false ? claim.merchant! : claim.categoryDisplayName)

            Text("|")
                .accessibilityHidden(true)

            Text(claim.urgencyLabel)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    private var urgencyLabel: some View {
        Label(claim.urgencyLabel, systemImage: claim.isUrgent || claim.isOverdue ? "clock.badge.exclamationmark" : "calendar")
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(AppTheme.urgencyColor(for: claim))
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
    }

    private var proofReminderLine: some View {
        HStack(spacing: 8) {
            FactLabel(
                text: claim.proofItemsList.isEmpty ? "No proof" : "Proof",
                systemImage: claim.proofItemsList.isEmpty ? "paperclip" : "paperclip.circle.fill"
            )

            if claim.reminderDate != nil {
                FactLabel(text: "Reminder", systemImage: "bell.fill")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Value at risk")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(claim.displayValue)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func deadlineBlock(alignment: HorizontalAlignment, textAlignment: TextAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text("Deadline")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(DateHelpers.deadlineText(for: claim.deadline))
                .font(.headline)
                .foregroundStyle(AppTheme.urgencyColor(for: claim))
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            claim.title,
            "\(claim.displayValue) at risk",
            claim.urgencyLabel,
            "Status \(claim.statusDisplayName)",
            claim.proofItemsList.isEmpty ? "No proof attached" : "Proof attached"
        ]

        if claim.reminderDate != nil {
            parts.append("Reminder set")
        }

        return parts.joined(separator: ". ")
    }
}

private struct FactLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(text)
    }
}

#Preview {
    VStack(spacing: 16) {
        ClaimCardView(claim: PreviewSampleData.sampleClaims[0], style: .detailHeader)
        ClaimCardView(claim: PreviewSampleData.sampleClaims[4], style: .attention)
        ClaimCardView(claim: PreviewSampleData.sampleClaims[2], style: .row)
    }
    .padding()
}
