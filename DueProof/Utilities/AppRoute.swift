import Combine
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
        let trimmed = ClaimSearchIntent.normalizedQuery(query)
        guard !trimmed.isEmpty else { return }
        selectedTab = .claims
        request = AppRouteRequest(destination: .search(trimmed))
    }

    func importSharedRequest(id: UUID?) {
        selectedTab = .claims
        request = AppRouteRequest(destination: .sharedImport(id))
    }

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "dueproof" else { return }

        switch url.host?.lowercased() {
        case "claim":
            let payloads = Self.pathPayloads(from: url)
            guard payloads.count == 1,
                  let rawID = payloads.first,
                  let claimID = UUID(uuidString: rawID)
            else {
                return
            }
            openClaim(id: claimID)
        case "add":
            guard Self.pathPayloads(from: url).isEmpty else { return }
            let category = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "category" })?
                .value
                .flatMap(ClaimCategory.init(rawValue:)) ?? .returnItem
            addClaim(category: category)
        case "search":
            guard Self.pathPayloads(from: url).isEmpty else { return }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value ?? ""
            search(query)
        case "import-shared":
            let payloads = Self.pathPayloads(from: url)
            switch payloads.count {
            case 0:
                importSharedRequest(id: nil)
            case 1:
                guard let rawID = payloads.first,
                      let id = UUID(uuidString: rawID)
                else {
                    return
                }
                importSharedRequest(id: id)
            default:
                return
            }
        default:
            selectedTab = .dashboard
        }
    }

    func handleSpotlightIdentifier(_ identifier: String) {
        let prefix = SpotlightIndexService.claimIdentifierPrefix
        guard identifier.hasPrefix(prefix) else { return }
        let rawID = String(identifier.dropFirst(prefix.count))
        if let claimID = UUID(uuidString: rawID) {
            openClaim(id: claimID)
        }
    }

    private static func pathPayloads(from url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }
}
