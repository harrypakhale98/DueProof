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

enum ClaimListOrdering {
    static func deadlineSoonest(_ lhs: Claim, _ rhs: Claim, referenceDate: Date = Date()) -> Bool {
        let lhsRank = deadlineRank(for: lhs, referenceDate: referenceDate)
        let rhsRank = deadlineRank(for: rhs, referenceDate: referenceDate)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        let lhsDeadline = finiteDate(lhs.deadline) ?? .distantFuture
        let rhsDeadline = finiteDate(rhs.deadline) ?? .distantFuture
        if lhsDeadline != rhsDeadline { return lhsDeadline < rhsDeadline }

        let lhsUpdatedAt = finiteDate(lhs.updatedAt) ?? .distantPast
        let rhsUpdatedAt = finiteDate(rhs.updatedAt) ?? .distantPast
        if lhsUpdatedAt != rhsUpdatedAt { return lhsUpdatedAt > rhsUpdatedAt }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func deadlineRank(for claim: Claim, referenceDate: Date) -> Int {
        guard claim.status.isOpen else { return 3 }
        guard let deadline = finiteDate(claim.deadline) else { return 2 }
        return DateHelpers.daysUntil(deadline, from: referenceDate) < 0 ? 0 : 1
    }

    private static func finiteDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }
}

struct ClaimsListView: View {
    @EnvironmentObject private var route: AppRoute
    @Query(sort: \Claim.createdAt, order: .reverse) private var claims: [Claim]
    @State private var searchText = ""
    @State private var filter: ClaimListFilter = .all
    @State private var sortOption: ClaimSortOption = .deadline
    @State private var editorCategory: ClaimCategory?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
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
                        editorCategory = .returnItem
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add claim")
                }
            }
            .navigationDestination(for: UUID.self) { claimID in
                if let claim = claims.first(where: { $0.id == claimID }) {
                    ClaimDetailView(claim: claim)
                } else {
                    ContentUnavailableView("Claim Not Found", systemImage: "magnifyingglass")
                }
            }
            .sheet(item: $editorCategory) { category in
                ClaimEditorView(initialCategory: category)
            }
            .onAppear {
                handleRouteRequest(route.request)
            }
            .onChange(of: route.request?.id) { _, _ in
                handleRouteRequest(route.request)
            }
        }
    }

    private var claimsList: some View {
        List {
            ForEach(filteredClaims, id: \.id) { claim in
                NavigationLink(value: claim.id) {
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
                    editorCategory = .returnItem
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

    private func handleRouteRequest(_ request: AppRouteRequest?) {
        guard let request else { return }

        switch request.destination {
        case .claim(let claimID):
            clearSearchAndFilter()
            path = [claimID]
            route.consume(request)
        case .addClaim(let category):
            editorCategory = category
            route.consume(request)
        case .search(let query):
            filter = .all
            searchText = query
            path = []
            route.consume(request)
        case .sharedImport:
            path = []
        }
    }

    private var filteredClaims: [Claim] {
        let query = ClaimSearchIntent.normalizedQuery(searchText)
        let searchIntent = query.isEmpty ? nil : ClaimSearchIntent.parse(query)

        return claims
            .filter { claim in
                guard let searchIntent else { return true }
                return searchIntent.matches(claim)
            }
            .filter(matchesFilter)
            .sorted(by: sort)
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
            return ClaimListOrdering.deadlineSoonest(lhs, rhs)
        case .highestValue:
            return CurrencyFormatter.sanitizedAmount(lhs.valueAtRisk) > CurrencyFormatter.sanitizedAmount(rhs.valueAtRisk)
        case .recentlyAdded:
            return lhs.createdAt > rhs.createdAt
        case .status:
            return lhs.statusDisplayName < rhs.statusDisplayName
        }
    }
}

#Preview {
    ClaimsListView()
        .environmentObject(AppRoute())
        .modelContainer(PreviewSampleData.container())
}
