import AppIntents
import Foundation

enum DueProofShortcutCategory: String, AppEnum {
    case returnItem
    case giftCard
    case warranty
    case reimbursement
    case rebate
    case subscription
    case renewal
    case document
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Claim Category")
    static var caseDisplayRepresentations: [DueProofShortcutCategory: DisplayRepresentation] = [
        .returnItem: "Return",
        .giftCard: "Gift Card",
        .warranty: "Warranty",
        .reimbursement: "Reimbursement",
        .rebate: "Rebate",
        .subscription: "Subscription",
        .renewal: "Renewal",
        .document: "Document",
        .other: "Other"
    ]

    var claimCategory: ClaimCategory {
        ClaimCategory(rawValue: rawValue) ?? .other
    }
}

struct DueProofAddClaimIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Claim"
    static var description = IntentDescription("Open DueProof to add a private claim card.")
    static var openAppWhenRun = true

    @Parameter(title: "Category", default: .returnItem)
    var category: DueProofShortcutCategory

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = DueProofShortcutURL.addClaim(category: category.claimCategory)
        return .result(opensIntent: OpenURLIntent(url), dialog: "Opening DueProof.")
    }
}

struct DueProofOpenUrgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Urgent Claims"
    static var description = IntentDescription("Open DueProof to claims that need attention.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = DueProofShortcutURL.search("urgent")
        return .result(opensIntent: OpenURLIntent(url), dialog: "Opening urgent claims.")
    }
}

struct DueProofSearchClaimsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Claims"
    static var description = IntentDescription("Open DueProof with a claim search.")
    static var openAppWhenRun = true

    @Parameter(title: "Search")
    var query: String

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = DueProofShortcutURL.search(query)
        return .result(opensIntent: OpenURLIntent(url), dialog: "Searching DueProof.")
    }
}

struct DueProofShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DueProofAddClaimIntent(),
            phrases: [
                "Add a claim in \(.applicationName)",
                "Add proof in \(.applicationName)"
            ],
            shortTitle: "Add Claim",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: DueProofOpenUrgentIntent(),
            phrases: [
                "Open urgent claims in \(.applicationName)",
                "Show deadlines in \(.applicationName)"
            ],
            shortTitle: "Urgent Claims",
            systemImageName: "exclamationmark.circle"
        )

        AppShortcut(
            intent: DueProofSearchClaimsIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find claims in \(.applicationName)"
            ],
            shortTitle: "Search Claims",
            systemImageName: "magnifyingglass"
        )
    }
}

private enum DueProofShortcutURL {
    static func addClaim(category: ClaimCategory) -> URL {
        URL(string: "dueproof://add?category=\(category.rawValue)")!
    }

    static func search(_ query: String) -> URL {
        var components = URLComponents()
        components.scheme = "dueproof"
        components.host = "search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url!
    }
}
