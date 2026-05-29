import LocalAuthentication
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Claim.createdAt, order: .reverse) private var claims: [Claim]

    @State private var exportURL: URL?
    @State private var reportURL: URL?
    @State private var isImporting = false
    @State private var isConfirmingClear = false
    @State private var notificationStatus = "Unknown"
    @State private var importResult: String?
    @State private var errorMessage: String?
    @AppStorage(SyncConfiguration.iCloudSyncEnabledKey) private var iCloudSyncEnabled = false
    @AppStorage(SyncConfiguration.iCloudSyncRequiresRestartKey) private var iCloudSyncRequiresRestart = false
    @AppStorage(AppLockSettings.isEnabledKey, store: AppLockSettings.defaults) private var appLockEnabled = false
    @AppStorage(DueProofPrivacySettings.spotlightSearchEnabledKey, store: DueProofPrivacySettings.defaults) private var spotlightSearchEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                privacySummarySection
                securitySection
                dataSection
                syncSection
                notificationSection
                aboutSection
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importClaims(result)
            }
            .confirmationDialog("Clear all DueProof data?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear All Data", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This deletes claims, proof references, local proof files, pending reminders, shared-import queue items, temporary exports, Spotlight entries, and widget snapshots on this device.")
            }
            .alert("DueProof", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { clearAlertMessages() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    private var privacySummarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.brandTint)
                    .accessibilityHidden(true)

                Text(iCloudSyncEnabled ? "Your data syncs through your private iCloud." : "Your data stays on this device.")
                    .font(.headline)

                Text(iCloudSyncEnabled ? "DueProof uses your private iCloud database when iCloud Sync is on. No DueProof account, ads, analytics, or tracking." : "DueProof stores your data on this device. No DueProof account, no DueProof-operated backend, no analytics, ads, or tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)

            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised.fill")
            }
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(get: {
                appLockEnabled
            }, set: { isEnabled in
                if isEnabled {
                    enableAppLockIfAvailable()
                } else {
                    appLockEnabled = false
                }
            })) {
                Label("Require Face ID or Passcode", systemImage: "lock.shield")
            }

            Toggle(isOn: Binding(get: {
                spotlightSearchEnabled
            }, set: { isEnabled in
                spotlightSearchEnabled = isEnabled && !appLockEnabled
                if !spotlightSearchEnabled {
                    SpotlightIndexService.shared.deleteAll()
                }
            })) {
                Label("Show Claims in Spotlight", systemImage: "magnifyingglass")
            }
            .disabled(appLockEnabled)
        } header: {
            Text("Security")
        } footer: {
            Text("App Lock uses device authentication to hide claim details and proof when DueProof becomes active. Spotlight search is off by default and disabled while App Lock is on so claim details do not appear outside DueProof.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                createExport()
            } label: {
                Label("Create Complete Export", systemImage: "square.and.arrow.up")
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share Complete Export", systemImage: "doc.badge.arrow.up")
                }
            }

            Button {
                createReport()
            } label: {
                Label("Create CSV Report", systemImage: "tablecells")
            }

            if let reportURL {
                ShareLink(item: reportURL) {
                    Label("Share CSV Report", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                isImporting = true
            } label: {
                Label("Import JSON", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label("Clear All Data", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Complete export includes claim details and proof photos. Review exports before sharing them outside DueProof.")
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            LabeledContent("Permission", value: notificationStatus)

            Button {
                Task { await refreshNotificationStatus() }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
        }
    }

    private var syncSection: some View {
        Section {
            Toggle(isOn: Binding(get: {
                iCloudSyncEnabled
            }, set: { isEnabled in
                SyncConfiguration.setICloudSyncEnabled(isEnabled)
                iCloudSyncEnabled = isEnabled
                iCloudSyncRequiresRestart = SyncConfiguration.iCloudSyncRequiresRestart
            })) {
                Label("iCloud Sync", systemImage: "icloud")
            }

            LabeledContent("Container", value: DueProofShared.cloudKitContainerIdentifier)
                .font(.footnote)

            if iCloudSyncRequiresRestart {
                Label("Restart DueProof to apply this sync change.", systemImage: "arrow.clockwise.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Sync uses your private iCloud database and applies on the next app launch. Proof files are mirrored for your devices when sync is on; complete exports remain available for offline archives.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)

            NavigationLink {
                LegalView()
            } label: {
                Label("Legal", systemImage: "doc.text")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var alertMessage: String? {
        errorMessage ?? importResult
    }

    private func clearAlertMessages() {
        errorMessage = nil
        importResult = nil
    }

    private func enableAppLockIfAvailable() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            appLockEnabled = false
            errorMessage = "Set up Face ID, Touch ID, or a device passcode before turning on App Lock."
            return
        }

        appLockEnabled = true
        spotlightSearchEnabled = false
        SpotlightIndexService.shared.deleteAll()
        ClaimSnapshotService.shared.clear()
        FileStorageService.shared.cleanupTemporaryExports()
        exportURL = nil
        reportURL = nil
    }

    private func createExport() {
        do {
            let previousExportURL = exportURL
            exportURL = try ImportExportService.shared.exportClaims(claims)
            FileStorageService.shared.deleteTemporaryExport(at: previousExportURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createReport() {
        do {
            let previousReportURL = reportURL
            reportURL = try ClaimReportExportService.shared.exportCSV(claims: claims)
            FileStorageService.shared.deleteTemporaryExport(at: previousReportURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importClaims(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let importResult = try ImportExportService.shared.importClaimsWithResult(from: url, into: modelContext)
            self.importResult = importResult.insertedCount == 1 ? "Imported 1 claim." : "Imported \(importResult.insertedCount) claims."

            Task { @MainActor in
                let insertedClaimIDs = Set(importResult.insertedClaimIDs)
                guard !insertedClaimIDs.isEmpty else { return }

                do {
                    let importedClaims = try modelContext.fetch(FetchDescriptor<Claim>())
                        .filter { insertedClaimIDs.contains($0.id) }
                    for claim in importedClaims where claim.status.isOpen && claim.reminderDate != nil {
                        await NotificationService.shared.scheduleReminder(for: claim)
                    }
                } catch {
                    errorMessage = "Imported claims, but DueProof could not prepare reminders: \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAllData() {
        var pendingProofFilesClear: FileStorageService.PendingDeletion?
        let snapshots = claims.map { claim in
            (claim: claim, snapshot: ClaimMutationSnapshot(claim))
        }
        let claimIDs = claims.map(\.id)
        var didDeleteClaims = false

        do {
            pendingProofFilesClear = try FileStorageService.shared.stageProofFilesClear()
            for claim in claims {
                modelContext.delete(claim)
            }
            didDeleteClaims = true

            try modelContext.save()
            claimIDs.forEach { NotificationService.shared.cancelReminder(for: $0) }
            FileStorageService.shared.commitStagedDeletion(pendingProofFilesClear)
            SharedImportQueueStore.shared.deleteAll()
            SpotlightIndexService.shared.deleteAll()
            ClaimSnapshotService.shared.clear()
            FileStorageService.shared.cleanupTemporaryExports()
            exportURL = nil
            reportURL = nil
        } catch {
            if didDeleteClaims {
                for snapshot in snapshots {
                    snapshot.snapshot.restoreDeletedClaim(snapshot.claim, into: modelContext)
                }
                try? modelContext.save()
            }
            try? FileStorageService.shared.rollbackStagedDeletion(pendingProofFilesClear)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let status = await NotificationService.shared.authorizationStatus()
        notificationStatus = displayName(for: status)
    }

    private func displayName(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }
}

private struct PrivacyView: View {
    private let rows = [
        ("No DueProof account", "person.crop.circle.badge.xmark"),
        ("Optional private iCloud sync", "icloud"),
        ("No ads", "rectangle.slash"),
        ("No analytics", "chart.bar.xaxis"),
        ("No tracking", "location.slash"),
        ("No telemetry or crash-reporting SDK", "waveform.slash"),
        ("No remote push notification service", "bell.slash"),
        ("Optional Face ID or passcode app lock", "lock.shield"),
        ("System search is opt-in", "magnifyingglass"),
        ("Smart Fill uses on-device text recognition", "text.viewfinder"),
        ("You review suggestions before saving", "checkmark.seal"),
        ("Proof photos stay local unless you sync or share", "photo.on.rectangle.angled"),
        ("You control export and deletion", "externaldrive.badge.checkmark"),
        ("Local notifications are used only for reminders you enable", "bell.badge")
    ]

    var body: some View {
        List {
            Section {
                ForEach(rows, id: \.0) { row in
                    Label(row.0, systemImage: row.1)
                }
            } footer: {
                Text("DueProof does not upload your data to DueProof servers. If you turn on iCloud Sync, claim data and proof files use your private iCloud database. Smart Fill uses on-device text recognition, system search is opt-in, and you review suggestions before saving.")
            }
        }
        .navigationTitle("Privacy")
    }
}

private struct LegalView: View {
    var body: some View {
        List {
            Section("Legal") {
                Text("DueProof is a local-first deadline tracker. Review exported data before sharing it outside the app.")
            }

            Section("Privacy") {
                Text("No DueProof account. No DueProof-operated backend. No ads. No analytics. No tracking. Your proof photos stay on this device unless you enable private iCloud sync or choose to export or share them through system controls.")
            }

            Section("Limits") {
                Text("DueProof helps organize proof and reminders. It does not file claims for you, guarantee reimbursement, or replace merchant, employer, insurer, government, or legal deadlines.")
            }
        }
        .navigationTitle("Legal")
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewSampleData.container())
}
