import CoreSpotlight
import LocalAuthentication
import SwiftData
import SwiftUI
import TipKit

@main
struct DueProofApp: App {
    private let modelContainer: ModelContainer?
    private let launchWarning: String?
    private let launchError: String?
    @State private var isShowingLaunchWarning: Bool
    @StateObject private var route = AppRoute()

    init() {
        AppLockSettings.migrateLegacyStandardDefaultIfNeeded()
        FileStorageService.shared.cleanupTemporaryExports()
        Self.configureTips()

        do {
            modelContainer = try Self.makeModelContainer()
            SyncConfiguration.markLaunchConfigurationApplied()
            launchWarning = nil
            launchError = nil
        } catch {
            do {
                modelContainer = try Self.makeInMemoryModelContainer()
                launchWarning = "DueProof opened with temporary storage because the local store could not be prepared. Export any visible data before closing the app."
                launchError = nil
            } catch {
                modelContainer = nil
                launchWarning = nil
                launchError = "DueProof could not prepare local storage. Restart your iPhone and try again before adding new proof."
            }
        }

        _isShowingLaunchWarning = State(initialValue: launchWarning != nil)
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
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
                .modelContainer(modelContainer)
            } else {
                StorageUnavailableView(message: launchError ?? "DueProof could not prepare local storage.")
            }
        }
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

    private static func configureTips() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate)
            ])
        } catch {
            #if DEBUG
            print("Error initializing TipKit \(error.localizedDescription)")
            #endif
        }
    }
}

private struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .tint(AppTheme.brandTint)
    }
}

private struct AppLockGate<Content: View>: View {
    @AppStorage(AppLockSettings.isEnabledKey, store: AppLockSettings.defaults) private var isAppLockEnabled = false
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
                isUnlocked = false
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
        guard scenePhase == .active else {
            isUnlocked = false
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
            let shouldAcceptUnlock = didUnlock && isAppLockEnabled && scenePhase == .active
            isUnlocked = shouldAcceptUnlock
            authenticationMessage = shouldAcceptUnlock ? nil : "DueProof is locked."
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
    @AppStorage(AppLockSettings.isEnabledKey, store: AppLockSettings.defaults) private var appLockEnabled = false
    @AppStorage(DueProofPrivacySettings.spotlightSearchEnabledKey, store: DueProofPrivacySettings.defaults) private var spotlightSearchEnabled = false
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
        .task(id: privateSurfaceSignature) {
            normalizeClaimsForStorageIfNeeded()
            backfillProofFilesForSyncIfNeeded()
            publishPrivateSurfaces()
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
                    claim.status.rawValue,
                    proofSignature(for: claim)
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private func proofSignature(for claim: Claim) -> String {
        claim.proofItemsList
            .map { proof in
                let displayName = ClaimTextLimits.required(proof.displayName, limit: ProofItemTextLimits.displayName)
                let localFileName = ClaimTextLimits.required(proof.localFileName ?? "", limit: 160)
                let extractedText = ClaimTextLimits.required(proof.extractedText ?? "", limit: ProofItemTextLimits.extractedText)
                let primaryIdentifier = ClaimTextLimits.optional(proof.intelligence?.primaryIdentifier, limit: ClaimTextLimits.reference) ?? ""

                return [
                    proof.id.uuidString,
                    displayName,
                    localFileName,
                    "\(extractedText.hashValue)",
                    "\(proof.intelligenceData?.count ?? 0)",
                    primaryIdentifier
                ].joined(separator: ":")
            }
            .joined(separator: ",")
    }

    private var privateSurfaceSignature: String {
        "\(spotlightSignature)|appLock:\(appLockEnabled)|spotlight:\(spotlightSearchEnabled)"
    }

    private func publishPrivateSurfaces() {
        if spotlightSearchEnabled && !appLockEnabled {
            SpotlightIndexService.shared.reindex(claims: claims)
        } else {
            SpotlightIndexService.shared.deleteAll()
        }

        if appLockEnabled {
            ClaimSnapshotService.shared.clear()
        } else {
            ClaimSnapshotService.shared.publish(claims: claims)
        }
    }

    private func normalizeClaimsForStorageIfNeeded() {
        var didNormalize = false
        for claim in claims {
            didNormalize = claim.normalizeStoredFields() || didNormalize
        }
        guard didNormalize else { return }

        do {
            try modelContext.save()
        } catch {
            sharedImportError = "DueProof could not finish repairing saved claim data: \(error.localizedDescription)"
        }
    }

    private func backfillProofFilesForSyncIfNeeded() {
        guard SyncConfiguration.isICloudSyncEnabled else { return }
        let proofs = claims.flatMap(\.proofItemsList)
        guard FileStorageService.shared.backfillSyncedFileData(for: proofs) > 0 else { return }

        do {
            try modelContext.save()
        } catch {
            sharedImportError = "DueProof could not finish preparing proof files for iCloud Sync: \(error.localizedDescription)"
        }
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
