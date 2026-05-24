import SwiftData
import SwiftUI

@main
struct DueProofApp: App {
    private let modelContainer: ModelContainer
    private let launchWarning: String?
    @State private var isShowingLaunchWarning: Bool

    init() {
        FileStorageService.shared.cleanupTemporaryExports()

        do {
            modelContainer = try Self.makeModelContainer()
            launchWarning = nil
        } catch {
            do {
                modelContainer = try Self.makeInMemoryModelContainer()
                launchWarning = "DueProof opened with temporary storage because the local store could not be prepared. Export any visible data before closing the app."
            } catch {
                fatalError("Unable to create any DueProof SwiftData store: \(error)")
            }
        }

        _isShowingLaunchWarning = State(initialValue: launchWarning != nil)
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    }

                ClaimsListView()
                    .tabItem {
                        Label("Claims", systemImage: "checklist")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .tint(AppTheme.brandTint)
            .alert("Storage Needs Attention", isPresented: $isShowingLaunchWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launchWarning ?? "")
            }
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([Claim.self, ProofItem.self])
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        FileStorageService.shared.protectLocalDataDirectory(applicationSupportDirectory)

        let storeURL = applicationSupportDirectory.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(for: schema, configurations: [configuration])
        FileStorageService.shared.protectLocalDataDirectory(applicationSupportDirectory)
        return container
    }

    private static func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([Claim.self, ProofItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
