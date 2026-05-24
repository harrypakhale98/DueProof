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

    var body: some View {
        NavigationStack {
            Form {
                privacySummarySection
                dataSection
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
                Text("This deletes claims, proof references, local proof files, and pending reminders on this device.")
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

                Text("Your data stays on this device.")
                    .font(.headline)

                Text("DueProof stores your data on this device. No account. No cloud backend. No analytics, ads, or tracking.")
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

    private func createExport() {
        do {
            exportURL = try ImportExportService.shared.exportClaims(claims)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createReport() {
        do {
            reportURL = try ClaimReportExportService.shared.exportCSV(claims: claims)
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

            let importedCount = try ImportExportService.shared.importClaims(from: url, into: modelContext)
            let importedClaims = try modelContext.fetch(FetchDescriptor<Claim>())
            importResult = importedCount == 1 ? "Imported 1 claim." : "Imported \(importedCount) claims."

            Task { @MainActor in
                for claim in importedClaims where claim.status.isOpen && claim.reminderDate != nil {
                    await NotificationService.shared.scheduleReminder(for: claim)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAllData() {
        do {
            let localFileNames = claims.flatMap { claim in
                claim.proofItems.compactMap(\.localFileName)
            }

            for claim in claims {
                NotificationService.shared.cancelReminder(for: claim)
                modelContext.delete(claim)
            }

            try modelContext.save()
            localFileNames.forEach { _ = FileStorageService.shared.deleteFile(named: $0) }
            try FileStorageService.shared.clearProofFiles()
            SpotlightIndexService.shared.deleteAll()
            exportURL = nil
            reportURL = nil
        } catch {
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
        ("No account", "person.crop.circle.badge.xmark"),
        ("No cloud backend", "cloud.slash"),
        ("No ads", "rectangle.slash"),
        ("No analytics", "chart.bar.xaxis"),
        ("No tracking", "location.slash"),
        ("Smart Fill uses on-device text recognition", "text.viewfinder"),
        ("You review suggestions before saving", "checkmark.seal"),
        ("Proof photos stay on this device", "photo.on.rectangle.angled"),
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
                Text("DueProof does not upload your data to our servers. Smart Fill uses on-device text recognition. When available, DueProof uses Apple's on-device intelligence to suggest claim details. Proof is not uploaded to DueProof servers, and you review suggestions before saving.")
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
                Text("No account. No cloud backend. No ads. No analytics. No tracking. Your proof photos stay on this device unless you choose to export or share them through system controls.")
            }
        }
        .navigationTitle("Legal")
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewSampleData.container())
}
