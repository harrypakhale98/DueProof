import Foundation

enum AppTab: Hashable {
    case dashboard
    case claims
    case settings
}

enum AppRouteDestination: Equatable {
    case claim(UUID)
    case addClaim(ClaimCategory)
    case search(String)
    case sharedImport(UUID?)
}

struct AppRouteRequest: Identifiable, Equatable {
    let id = UUID()
    let destination: AppRouteDestination
}

final class AppRoute: ObservableObject {
    @Published var selectedTab: AppTab = .dashboard
    @Published var request: AppRouteRequest?

    func openClaim(id: UUID) {
        selectedTab = .claims
        request = AppRouteRequest(destination: .claim(id))
    }

    func addClaim(category: ClaimCategory = .returnItem) {
        selectedTab = .claims
        request = AppRouteRequest(destination: .addClaim(category))
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedTab = .claims
        request = AppRouteRequest(destination: .search(trimmed))
    }

    func importSharedRequest(id: UUID?) {
        selectedTab = .claims
        request = AppRouteRequest(destination: .sharedImport(id))
    }

    func handle(_ url: URL) {
        guard url.scheme == "dueproof" else { return }

        switch url.host {
        case "claim":
            let rawID = url.pathComponents.dropFirst().first
            if let rawID, let claimID = UUID(uuidString: rawID) {
                openClaim(id: claimID)
            }
        case "add":
            let category = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "category" })?
                .value
                .flatMap(ClaimCategory.init(rawValue:)) ?? .returnItem
            addClaim(category: category)
        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value ?? ""
            search(query)
        case "import-shared":
            let rawID = url.pathComponents.dropFirst().first
            importSharedRequest(id: rawID.flatMap(UUID.init(uuidString:)))
        default:
            selectedTab = .dashboard
        }
    }

    func handleSpotlightIdentifier(_ identifier: String) {
        guard identifier.hasPrefix(SpotlightIndexService.claimIdentifierPrefix) else { return }
        let rawID = identifier.replacingOccurrences(of: SpotlightIndexService.claimIdentifierPrefix, with: "")
        if let claimID = UUID(uuidString: rawID) {
            openClaim(id: claimID)
        }
    }
}
