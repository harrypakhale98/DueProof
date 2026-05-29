import SwiftData
import SwiftUI
import TipKit

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Claim.createdAt, order: .reverse) private var claims: [Claim]
    @State private var editorCategory: ClaimCategory?
    @State private var isSmartFilling = false
    @State private var isChoosingFirstClaimType = false
    @State private var savedPulse = false
    private let firstRunTip = DueProofFirstClaimTip()

    var body: some View {
        NavigationStack {
            ScrollView {
                if claims.isEmpty {
                    emptyDashboard
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        moneyAtRiskCard
                        nextActionCard

                        LazyVGrid(columns: metricColumns, spacing: 12) {
                            MetricCardView(
                                title: "Urgent",
                                value: "\(metrics.urgentCount)",
                                systemImage: "exclamationmark.circle.fill",
                                tint: .orange
                            )

                            MetricCardView(
                                title: "Active",
                                value: "\(metrics.activeCount)",
                                systemImage: "checklist.checked",
                                tint: AppTheme.brandTint
                            )

                            MetricCardView(
                                title: "Recovered",
                                value: CurrencyFormatter.string(recoveredValue),
                                systemImage: "checkmark.circle.fill",
                                tint: .green
                            )
                        }

                        expiringSoonSection

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add a claim")
                                .font(.title3.weight(.semibold))

                            smartFillButton

                            QuickAddGridView { category in
                                editorCategory = category
                            }
                        }

                        Label("Stored locally by default. No DueProof account. No tracking.", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .contentMargins(.bottom, bottomScrollClearance, for: .scrollContent)
            .navigationTitle("DueProof")
            .background(.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorCategory = .returnItem
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add claim")
                }
            }
            .sheet(item: $editorCategory) { category in
                ClaimEditorView(initialCategory: category)
            }
            .sheet(isPresented: $isSmartFilling) {
                SmartFillView(
                    onEditManually: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            editorCategory = .returnItem
                        }
                    }
                )
            }
            .confirmationDialog("Choose a claim type", isPresented: $isChoosingFirstClaimType, titleVisibility: .visible) {
                ForEach(firstRunManualCategories) { category in
                    Button(category.displayName) {
                        editorCategory = category
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Start with the type that matches the proof or deadline you want to protect.")
            }
            .sensoryFeedback(.success, trigger: savedPulse)
            .task(id: claims.isEmpty) {
                DueProofFirstClaimTip.hasSavedClaim = !claims.isEmpty
            }
        }
    }

    private var metricColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var bottomScrollClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 168
    }

    private var expiringSoonClaims: [Claim] {
        metrics.expiringSoonClaims
    }

    private var moneyAtRisk: Double {
        metrics.moneyAtRisk
    }

    private var recoveredValue: Double {
        metrics.recoveredValue
    }

    private var nextActionClaim: Claim? {
        metrics.nextActionClaim
    }

    private var metrics: DashboardMetrics {
        DashboardMetrics(claims: claims)
    }

    private var firstRunManualCategories: [ClaimCategory] {
        ClaimCategory.allCases
    }

    private var firstRunTipView: some View {
        TipView(firstRunTip, arrowEdge: .bottom) { action in
            handleFirstRunTipAction(action)
        }
        .tipBackground(.regularMaterial)
        .tipCornerRadius(AppTheme.compactCornerRadius)
        .tipImageStyle(AppTheme.brandTint, AppTheme.receiptAqua)
        .tipImageSize(CGSize(width: 30, height: 30))
    }

    private var smartFillButton: some View {
        Button {
            isSmartFilling = true
        } label: {
            Label("Smart Fill from Proof", systemImage: "doc.viewfinder")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(AppTheme.brandTint)
        .accessibilityLabel("Smart Fill from Proof")
        .accessibilityHint("Choose a proof image and review suggested claim details before saving.")
    }

    private var emptyDashboard: some View {
        VStack(alignment: .leading, spacing: 28) {
            EmptyStateView(
                systemImage: "doc.text.magnifyingglass",
                title: "Nothing at risk yet",
                message: "Add a return, gift card, warranty, rebate, reimbursement, renewal, or document before it slips away. Stored on this iPhone.",
                buttonTitle: "Add First Claim"
            ) {
                editorCategory = .returnItem
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260)

            firstRunTipView

            VStack(alignment: .leading, spacing: 12) {
                Text("Start with")
                    .font(.title3.weight(.semibold))

                smartFillButton

                QuickAddGridView { category in
                    editorCategory = category
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var moneyAtRiskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Money at Risk")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Label("On-device", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }

                    Text(CurrencyFormatter.string(moneyAtRisk))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text("Across active claims")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "shield.checkered")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.brandTint)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.receiptAqua.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
            }

            Text("Keep proof. Beat deadlines.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dueProofCardBackground(cornerRadius: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Money at risk \(CurrencyFormatter.string(moneyAtRisk)) across active claims. Your data stays on this device.")
    }

    @ViewBuilder
    private var nextActionCard: some View {
        if let claim = nextActionClaim {
            NavigationLink {
                ClaimDetailView(claim: claim)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: nextActionIcon(for: claim))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(nextActionTint(for: claim))
                        .frame(width: 42, height: 42)
                        .background(nextActionTint(for: claim).opacity(0.14), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Next Action")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(nextActionTitle(for: claim))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(nextActionDetail(for: claim))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next action. \(nextActionTitle(for: claim)). \(nextActionDetail(for: claim))")
            .accessibilityHint("Opens claim details")
        }
    }

    @ViewBuilder
    private var expiringSoonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Needs Attention")
                    .font(.title3.weight(.semibold))

                Spacer()

                if !expiringSoonClaims.isEmpty {
                    Text("\(expiringSoonClaims.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }

            if expiringSoonClaims.isEmpty {
                Text("No overdue or upcoming active deadlines need attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(expiringSoonClaims, id: \.id) { claim in
                            NavigationLink {
                                ClaimDetailView(claim: claim)
                            } label: {
                                ClaimCardView(claim: claim, style: .attention)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 1, for: .scrollContent)
                .scrollClipDisabled()
            }
        }
    }

    private func nextActionTitle(for claim: Claim) -> String {
        if claim.isOverdue {
            return "Review overdue \(claim.categoryDisplayName.lowercased())"
        }

        if claim.isUrgent {
            return "Beat this deadline"
        }

        if claim.proofItemsList.isEmpty {
            return "Attach proof"
        }

        if claim.deadline == nil {
            return "Add a deadline"
        }

        return "Keep this moving"
    }

    private func nextActionDetail(for claim: Claim) -> String {
        let value = claim.displayValue
        let deadline = DateHelpers.deadlineText(for: claim.deadline)

        if claim.proofItemsList.isEmpty {
            return "\(claim.title) has \(value) at risk and no proof attached."
        }

        if claim.deadline == nil {
            return "\(claim.title) has proof, but no deadline."
        }

        return "\(claim.title) has \(value) at risk. Deadline: \(deadline)."
    }

    private func nextActionIcon(for claim: Claim) -> String {
        if claim.isOverdue { return "clock.badge.exclamationmark.fill" }
        if claim.isUrgent { return "exclamationmark.circle.fill" }
        if claim.proofItemsList.isEmpty { return "paperclip.badge.plus" }
        if claim.deadline == nil { return "calendar.badge.plus" }
        return "checkmark.seal.fill"
    }

    private func nextActionTint(for claim: Claim) -> Color {
        if claim.isOverdue { return .red }
        if claim.isUrgent { return .orange }
        if claim.proofItemsList.isEmpty { return AppTheme.brandTint }
        if claim.deadline == nil { return .purple }
        return .green
    }

    private func handleFirstRunTipAction(_ action: Tips.Action) {
        firstRunTip.invalidate(reason: .actionPerformed)

        switch action.id {
        case DueProofFirstClaimTip.smartFillActionID:
            isSmartFilling = true
        case DueProofFirstClaimTip.chooseTypeActionID:
            isChoosingFirstClaimType = true
        default:
            break
        }
    }
}

private struct DueProofFirstClaimTip: Tip {
    static let smartFillActionID = "dueproof.firstClaim.smartFill"
    static let chooseTypeActionID = "dueproof.firstClaim.chooseType"

    @Parameter(.transient)
    static var hasSavedClaim: Bool = false

    var title: Text {
        Text("Start with one claim")
    }

    var message: Text? {
        Text("Choose a receipt or screenshot for Smart Fill, or pick a claim type to enter the deadline, value, and proof yourself.")
    }

    var image: Image? {
        Image(systemName: "checkmark.shield.fill")
    }

    var actions: [Action] {
        Action(id: Self.smartFillActionID, title: "Smart Fill")
        Action(id: Self.chooseTypeActionID, title: "Choose Type")
    }

    var rules: [Rule] {
        #Rule(Self.$hasSavedClaim) { hasSavedClaim in
            hasSavedClaim == false
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

#Preview {
    DashboardView()
        .modelContainer(PreviewSampleData.container())
}
