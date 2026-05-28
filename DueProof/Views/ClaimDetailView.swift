import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ClaimDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let claim: Claim

    @State private var isEditing = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImportingProofFile = false
    @State private var showingDeleteConfirmation = false
    @State private var calendarURL: URL?
    @State private var proofPacketURL: URL?
    @State private var claimMessageURL: URL?
    @State private var errorMessage: String?
    @State private var actionPulse = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                detailSection
                actionDetailsSection
                reminderSection
                calendarSection
                claimActionSection
                proofSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .contentMargins(.bottom, claim.status.isOpen ? 104 : 24, for: .scrollContent)
        .navigationTitle(claim.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button("Edit") {
                        isEditing = true
                    }

                    moreMenu
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if claim.status.isOpen {
                bottomActionBar
            }
        }
            .sheet(isPresented: $isEditing) {
                ClaimEditorView(claim: claim)
            }
            .fileImporter(isPresented: $isImportingProofFile, allowedContentTypes: [.image, .pdf]) { result in
                Task { await importProofFile(result) }
            }
            .confirmationDialog("Delete this claim?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Claim", role: .destructive) {
                deleteClaim()
            }
        } message: {
            Text("This removes the claim, proof references, and local reminder.")
        }
        .alert("DueProof", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await addPhoto(newItem) }
        }
        .sensoryFeedback(.success, trigger: actionPulse)
    }

    private var headerCard: some View {
        ClaimCardView(claim: claim, style: .detailHeader)
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 0) {
                DetailRow(title: "Category", value: claim.categoryDisplayName, systemImage: claim.category.tintSymbolName)
                Divider().padding(.leading, 42)
                DetailRow(title: "Status", value: claim.statusDisplayName, systemImage: claim.effectiveStatus.symbolName)
                Divider().padding(.leading, 42)
                DetailRow(title: "Created", value: DateHelpers.shortDate(claim.createdAt), systemImage: "calendar.badge.plus")
                Divider().padding(.leading, 42)
                DetailRow(title: "Updated", value: DateHelpers.shortDate(claim.updatedAt), systemImage: "clock")

                if let completedAt = claim.completedAt {
                    Divider().padding(.leading, 42)
                    DetailRow(title: "Completed", value: DateHelpers.shortDate(completedAt), systemImage: "checkmark.circle")
                }
            }
            .padding(14)
            .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)

            if !claim.notes.isEmpty {
                Text(claim.notes)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
            }
        }
    }

    @ViewBuilder
    private var actionDetailsSection: some View {
        let reference = claim.primaryReference
        let policy = claim.policySummary.trimmingCharacters(in: .whitespacesAndNewlines)

        if reference != nil || !policy.isEmpty || claim.actionURL != nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("Action Details")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    if let reference {
                        LabeledContent("Reference") {
                            Text(reference)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if !policy.isEmpty {
                        Text(policy)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }

                    if let actionURL = claim.actionURL {
                        Link(destination: actionURL) {
                            Label("Open Action Link", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Reminder")
                    .font(.headline)

                Spacer()

                Button {
                    isEditing = true
                } label: {
                    Label(claim.reminderDate == nil ? "Add Reminder" : "Change", systemImage: "bell.badge")
                }
                .buttonStyle(.glass)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    claim.reminderDate.map { DateHelpers.fullDateTime($0) } ?? "No reminder set",
                    systemImage: claim.reminderDate == nil ? "bell.slash" : "bell"
                )
                .font(.subheadline)
                .foregroundStyle(claim.reminderDate == nil ? Color.secondary : Color.primary)

                Text("Local notifications stay on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
        }
    }

    private var proofSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Proof")
                    .font(.headline)

                Spacer()

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                    }
                    .accessibilityLabel("Add proof photo")

                    Button {
                        isImportingProofFile = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("Import proof file")
                }
                .buttonStyle(.glass)
            }

            ProofGalleryView(claim: claim)

            Text("Proof files stay on this device unless you share or export them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calendar")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                if let calendarURL {
                    ShareLink(item: calendarURL) {
                        Label("Share Calendar File", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                } else if claim.deadline == nil {
                    Label("Add a deadline before exporting to Calendar.", systemImage: "calendar.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        createCalendarFile()
                    } label: {
                        Label("Create Calendar File", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                Text("Calendar files may sync through the calendar provider you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
        }
    }

    private var claimActionSection: some View {
        let plan = ClaimActionPlanService.shared.plan(for: claim)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Claim Help")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Label(plan.headline, systemImage: "checklist.checked")
                    .font(.subheadline.weight(.semibold))

                Text(plan.nextStep)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.checklist, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button {
                        createProofPacket()
                    } label: {
                        Label("Create Proof Packet", systemImage: "doc.richtext")
                    }
                    .buttonStyle(.bordered)

                    if let proofPacketURL {
                        ShareLink(item: proofPacketURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Share proof packet")
                    }
                }

                HStack {
                    Button {
                        createClaimMessage()
                    } label: {
                        Label("Create Claim Message", systemImage: "envelope")
                    }
                    .buttonStyle(.bordered)

                    if let claimMessageURL {
                        ShareLink(item: claimMessageURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Share claim message")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                if updateClaim({
                    claim.markRecovered()
                }) {
                    NotificationService.shared.cancelReminder(for: claim)
                }
            } label: {
                Label("Recovered", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)

            Button {
                if updateClaim({
                    claim.markUsed()
                }) {
                    NotificationService.shared.cancelReminder(for: claim)
                }
            } label: {
                Label("Used", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var moreMenu: some View {
        Menu {
            Section("Claim") {
                Button {
                    if updateClaim({
                        claim.markExpired()
                    }) {
                        NotificationService.shared.cancelReminder(for: claim)
                    }
                } label: {
                    Label("Mark as Expired", systemImage: "xmark.circle")
                }

                Button {
                    if updateClaim({
                        claim.markIgnored()
                    }) {
                        NotificationService.shared.cancelReminder(for: claim)
                    }
                } label: {
                    Label("Mark as Ignored", systemImage: "minus.circle")
                }
            }

            Section("Calendar") {
                if let calendarURL {
                    ShareLink(item: calendarURL) {
                        Label("Share Calendar File", systemImage: "square.and.arrow.up")
                    }
                } else if claim.deadline == nil {
                    Label("No Deadline to Export", systemImage: "calendar.badge.exclamationmark")
                } else {
                    Button {
                        createCalendarFile()
                    } label: {
                        Label("Create Calendar File", systemImage: "calendar.badge.plus")
                    }
                    .disabled(claim.deadline == nil)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Claim", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More actions")
    }

    @discardableResult
    private func updateClaim(_ changes: () -> Void) -> Bool {
        let snapshot = ClaimMutationSnapshot(claim)
        changes()
        claim.normalizeStoredFields()
        do {
            try modelContext.save()
            actionPulse += 1
            return true
        } catch {
            snapshot.restore(to: claim)
            try? modelContext.save()
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func addPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let snapshot = ClaimMutationSnapshot(claim)
        var createdLocalFileName: String?
        var createdProof: ProofItem?

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let fileName = try FileStorageService.shared.saveImageData(data, preferredName: claim.title)
            createdLocalFileName = fileName
            let result = await OCRService.shared.recognizeText(inImageData: data)
            let searchableText = result.searchableText
            let extractedText = searchableText.isEmpty ? nil : String(searchableText.prefix(12_000))
            let intelligence = await ProofIntelligenceService.shared.analyze(ocrResult: result, categoryHint: claim.category)
            let proof = ProofItem(
                type: .photo,
                localFileName: fileName,
                displayName: "Proof Photo",
                extractedText: extractedText,
                intelligence: intelligence,
                claim: claim
            )
            createdProof = proof
            modelContext.insert(proof)
            claim.proofItemsList.append(proof)
            claim.touch()
            try modelContext.save()
            createdLocalFileName = nil
        } catch {
            if let createdProof {
                modelContext.delete(createdProof)
            }
            snapshot.restore(to: claim)
            _ = FileStorageService.shared.deleteFile(named: createdLocalFileName)
            try? modelContext.save()
            errorMessage = error.localizedDescription
        }
    }

    private func createCalendarFile() {
        do {
            let previousCalendarURL = calendarURL
            calendarURL = try CalendarExportService.shared.exportDeadline(for: claim)
            FileStorageService.shared.deleteTemporaryExport(at: previousCalendarURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createProofPacket() {
        do {
            let previousProofPacketURL = proofPacketURL
            proofPacketURL = try ProofPacketExportService.shared.exportPacket(for: claim)
            FileStorageService.shared.deleteTemporaryExport(at: previousProofPacketURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createClaimMessage() {
        do {
            let previousClaimMessageURL = claimMessageURL
            claimMessageURL = try ClaimActionPlanService.shared.exportMessage(for: claim)
            FileStorageService.shared.deleteTemporaryExport(at: previousClaimMessageURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importProofFile(_ result: Result<URL, Error>) async {
        let snapshot = ClaimMutationSnapshot(claim)
        var createdLocalFileName: String?
        var createdProof: ProofItem?

        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try FileStorageService.shared.dataForImportedProof(at: url)
            let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            let proofType: ProofItemType = isImage ? .photo : .document
            let fileName: String
            if isImage {
                fileName = try FileStorageService.shared.saveImageData(data)
            } else {
                fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: url.lastPathComponent)
            }
            createdLocalFileName = fileName

            let extractedText: String?
            let intelligence: ProofIntelligence?
            if isImage {
                let result = await OCRService.shared.recognizeText(inImageData: data)
                let searchableText = result.searchableText
                extractedText = searchableText.isEmpty ? nil : String(searchableText.prefix(12_000))
                intelligence = await ProofIntelligenceService.shared.analyze(ocrResult: result, categoryHint: claim.category)
            } else if let localURL = FileStorageService.shared.url(for: fileName) {
                extractedText = await OCRService.shared.searchableText(at: localURL, type: proofType)
                intelligence = await ProofIntelligenceService.shared.analyze(
                    ocrResult: OCRResult(
                        text: extractedText ?? "",
                        warnings: extractedText?.isEmpty == false ? [] : ["No readable text was found in that proof."]
                    ),
                    categoryHint: claim.category
                )
            } else {
                extractedText = nil
                intelligence = nil
            }

            let proof = ProofItem(
                type: proofType,
                localFileName: fileName,
                displayName: url.deletingPathExtension().lastPathComponent,
                extractedText: extractedText,
                intelligence: intelligence,
                claim: claim
            )
            createdProof = proof
            modelContext.insert(proof)
            claim.proofItemsList.append(proof)
            claim.touch()
            try modelContext.save()
            createdLocalFileName = nil
        } catch {
            if let createdProof {
                modelContext.delete(createdProof)
            }
            snapshot.restore(to: claim)
            _ = FileStorageService.shared.deleteFile(named: createdLocalFileName)
            try? modelContext.save()
            errorMessage = error.localizedDescription
        }
    }

    private func deleteClaim() {
        let snapshot = ClaimMutationSnapshot(claim)
        let localFileNames = claim.proofItemsList.compactMap(\.localFileName)
        let claimID = claim.id
        var pendingDeletions: [FileStorageService.PendingDeletion] = []
        var didDeleteClaim = false

        do {
            pendingDeletions = try FileStorageService.shared.stageFileDeletions(named: localFileNames)
            modelContext.delete(claim)
            didDeleteClaim = true

            try modelContext.save()
            NotificationService.shared.cancelReminder(for: claimID)
            FileStorageService.shared.commitStagedDeletions(pendingDeletions)
            dismiss()
        } catch {
            if didDeleteClaim {
                snapshot.restoreDeletedClaim(claim, into: modelContext)
            } else {
                snapshot.restore(to: claim)
            }
            FileStorageService.shared.rollbackStagedDeletions(pendingDeletions)
            try? modelContext.save()
            errorMessage = error.localizedDescription
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    NavigationStack {
        ClaimDetailView(claim: PreviewSampleData.sampleClaims[0])
    }
    .modelContainer(PreviewSampleData.container())
}
