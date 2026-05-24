import CoreSpotlight
import SwiftData
import SwiftUI

@main
struct DueProofApp: App {
    private let modelContainer: ModelContainer
    private let launchWarning: String?
    @State private var isShowingLaunchWarning: Bool
    @StateObject private var route = AppRoute()

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
            RootTabView()
            .environmentObject(route)
            .tint(AppTheme.brandTint)
            .alert("Storage Needs Attention", isPresented: $isShowingLaunchWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launchWarning ?? "")
            }
            .onOpenURL { url in
                route.handle(url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                route.handleSpotlightIdentifier(identifier)
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
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = SyncConfiguration.isICloudSyncEnabled
            ? .private(DueProofShared.cloudKitContainerIdentifier)
            : .none

        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: cloudKitDatabase
        )

        let container = try ModelContainer(for: schema, configurations: [configuration])
        FileStorageService.shared.protectLocalDataDirectory(applicationSupportDirectory)
        return container
    }

    private static func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([Claim.self, ProofItem.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var route: AppRoute
    @Query(sort: \Claim.updatedAt, order: .reverse) private var claims: [Claim]
    @State private var sharedImportMessage: String?
    @State private var sharedImportError: String?

    var body: some View {
        TabView(selection: $route.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(AppTab.dashboard)

            ClaimsListView()
                .tabItem {
                    Label("Claims", systemImage: "checklist")
                }
                .tag(AppTab.claims)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .task(id: spotlightSignature) {
            backfillProofFilesForSyncIfNeeded()
            SpotlightIndexService.shared.reindex(claims: claims)
            ClaimSnapshotService.shared.publish(claims: claims)
        }
        .task {
            await importPendingSharedRequests()
        }
        .onChange(of: route.request) { _, request in
            guard case let .sharedImport(id) = request?.destination else { return }
            Task { await importSharedRequest(id: id) }
        }
        .alert("DueProof", isPresented: Binding(get: { sharedImportAlertMessage != nil }, set: { if !$0 { clearSharedImportMessages() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharedImportAlertMessage ?? "")
        }
    }

    private var sharedImportAlertMessage: String? {
        sharedImportError ?? sharedImportMessage
    }

    private var spotlightSignature: String {
        claims
            .map { claim in
                [
                    claim.id.uuidString,
                    "\(claim.updatedAt.timeIntervalSince1970)",
                    "\(claim.proofItemsList.count)",
                    claim.status.rawValue
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private func backfillProofFilesForSyncIfNeeded() {
        guard SyncConfiguration.isICloudSyncEnabled else { return }
        let proofs = claims.flatMap(\.proofItemsList)
        guard FileStorageService.shared.backfillSyncedFileData(for: proofs) > 0 else { return }
        try? modelContext.save()
    }

    private func importPendingSharedRequests() async {
        do {
            let count = try await SharedImportService.shared.importPendingRequests(into: modelContext)
            if count > 0 {
                sharedImportMessage = count == 1 ? "Imported 1 shared item." : "Imported \(count) shared items."
            }
        } catch {
            sharedImportError = error.localizedDescription
        }
    }

    private func importSharedRequest(id: UUID?) async {
        do {
            let count: Int
            if let id {
                count = try await SharedImportService.shared.importRequest(id: id, into: modelContext)
            } else {
                count = try await SharedImportService.shared.importPendingRequests(into: modelContext)
            }

            if count > 0 {
                sharedImportMessage = count == 1 ? "Imported 1 shared item." : "Imported \(count) shared items."
            }
        } catch {
            sharedImportError = error.localizedDescription
        }
    }

    private func clearSharedImportMessages() {
        sharedImportMessage = nil
        sharedImportError = nil
    }
}
