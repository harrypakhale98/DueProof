import CoreSpotlight
import LocalAuthentication
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
            AppLockGate {
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

private struct AppLockGate<Content: View>: View {
    @AppStorage(AppLockSettings.isEnabledKey) private var isAppLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked = false
    @State private var authenticationMessage: String?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shouldLock: Bool {
        isAppLockEnabled && !isUnlocked
    }

    var body: some View {
        ZStack {
            content
                .privacySensitive(isAppLockEnabled)
                .blur(radius: shouldLock ? 16 : 0)
                .disabled(shouldLock)
                .accessibilityHidden(shouldLock)

            if shouldLock {
                lockedView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldLock)
        .task {
            guard isAppLockEnabled else {
                isUnlocked = true
                return
            }
            await authenticate()
        }
        .onChange(of: isAppLockEnabled) { _, enabled in
            if enabled {
                isUnlocked = false
                Task { await authenticate() }
            } else {
                isUnlocked = true
                authenticationMessage = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard isAppLockEnabled else { return }
            if phase == .active {
                Task { await authenticate() }
            } else {
                isUnlocked = false
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppTheme.brandTint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("DueProof Locked")
                    .font(.title2.weight(.semibold))

                Text(authenticationMessage ?? "Unlock to view private claims and proof.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await authenticate() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.brandTint)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        .padding(24)
    }

    @MainActor
    private func authenticate() async {
        guard isAppLockEnabled else {
            isUnlocked = true
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationMessage = nil
            isAppLockEnabled = false
            isUnlocked = true
            return
        }

        do {
            let didUnlock = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock DueProof to view private claims and proof."
            )
            isUnlocked = didUnlock
            authenticationMessage = didUnlock ? nil : "DueProof is locked."
        } catch {
            authenticationMessage = "DueProof is locked."
            isUnlocked = false
        }
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
