import SwiftData
import SwiftUI

private enum ClaimListFilter: String, CaseIterable, Identifiable {
    case all
    case urgent
    case overdue
    case returns
    case giftCards
    case warranties
    case reimbursements
    case rebates
    case subscriptions
    case renewals
    case documents
    case completed
    case expired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .urgent: "Urgent"
        case .overdue: "Overdue"
        case .returns: "Returns"
        case .giftCards: "Gift Cards"
        case .warranties: "Warranties"
        case .reimbursements: "Reimbursements"
        case .rebates: "Rebates"
        case .subscriptions: "Subscriptions"
        case .renewals: "Renewals"
        case .documents: "Documents"
        case .completed: "Completed"
        case .expired: "Expired"
        }
    }
}

private enum ClaimSortOption: String, CaseIterable, Identifiable {
    case deadline
    case highestValue
    case recentlyAdded
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deadline: "Deadline soonest"
        case .highestValue: "Highest value"
        case .recentlyAdded: "Recently added"
        case .status: "Status"
        }
    }
}

struct ClaimsListView: View {
    @Query(sort: \Claim.createdAt, order: .reverse) private var claims: [Claim]
    @State private var searchText = ""
    @State private var filter: ClaimListFilter = .all
    @State private var sortOption: ClaimSortOption = .deadline
    @State private var isAddingClaim = false

    var body: some View {
        NavigationStack {
            Group {
                if filteredClaims.isEmpty {
                    emptyState
                } else {
                    claimsList
                }
            }
            .navigationTitle("Claims")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search or ask: due this week"
            )
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    filterAndSortMenu

                    Button {
                        isAddingClaim = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add claim")
                }
            }
            .sheet(isPresented: $isAddingClaim) {
                ClaimEditorView(initialCategory: .returnItem)
            }
        }
    }

    private var claimsList: some View {
        List {
            ForEach(filteredClaims, id: \.id) { claim in
                NavigationLink {
                    ClaimDetailView(claim: claim)
                } label: {
                    ClaimRowView(claim: claim)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                claims.isEmpty ? "No Claims Yet" : "No Matching Claims",
                systemImage: claims.isEmpty ? "checklist" : "magnifyingglass"
            )
        } description: {
            Text(
                claims.isEmpty
                    ? "Add returns, gift cards, warranties, rebates, reimbursements, renewals, and documents before they expire."
                    : "Try another search or filter."
            )
        } actions: {
            if claims.isEmpty {
                Button("Add First Claim") {
                    isAddingClaim = true
                }
                .buttonStyle(.borderedProminent)
            } else if isFilteringClaims {
                Button("Clear Search and Filter") {
                    clearSearchAndFilter()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var filterAndSortMenu: some View {
        Menu {
            Section("Filter") {
                Picker("Filter", selection: $filter) {
                    ForEach(ClaimListFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section("Sort") {
                Picker("Sort", selection: $sortOption) {
                    ForEach(ClaimSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            if isFilteringClaims || sortOption != .deadline {
                Section {
                    Button {
                        clearSearchAndFilter()
                        sortOption = .deadline
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            Label("Filter and Sort", systemImage: isFilteringClaims ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter and sort claims")
    }

    private var isFilteringClaims: Bool {
        filter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearSearchAndFilter() {
        searchText = ""
        filter = .all
    }

    private var filteredClaims: [Claim] {
        claims
            .filter(matchesSearch)
            .filter(matchesFilter)
            .sorted(by: sort)
    }

    private func matchesSearch(_ claim: Claim) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return ClaimSearchIntent.parse(query).matches(claim)
    }

    private func matchesFilter(_ claim: Claim) -> Bool {
        switch filter {
        case .all: true
        case .urgent: claim.isUrgent
        case .overdue: claim.isOverdue
        case .returns: claim.category == .returnItem
        case .giftCards: claim.category == .giftCard
        case .warranties: claim.category == .warranty
        case .reimbursements: claim.category == .reimbursement
        case .rebates: claim.category == .rebate
        case .subscriptions: claim.category == .subscription
        case .renewals: claim.category == .renewal
        case .documents: claim.category == .document
        case .completed: claim.status.isComplete
        case .expired: claim.isExpired
        }
    }

    private func sort(_ lhs: Claim, _ rhs: Claim) -> Bool {
        switch sortOption {
        case .deadline:
            return (lhs.deadline ?? .distantFuture) < (rhs.deadline ?? .distantFuture)
        case .highestValue:
            return lhs.valueAtRisk > rhs.valueAtRisk
        case .recentlyAdded:
            return lhs.createdAt > rhs.createdAt
        case .status:
            return lhs.statusDisplayName < rhs.statusDisplayName
        }
    }
}

#Preview {
    ClaimsListView()
        .modelContainer(PreviewSampleData.container())
}
