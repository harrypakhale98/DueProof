import SwiftData
import SwiftUI
import UIKit

struct ProofGalleryView: View {
    @Environment(\.modelContext) private var modelContext

    let claim: Claim
    @State private var proofPendingRemoval: ProofItem?
    @State private var selectedProof: ProofItem?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 12)
    ]

    var body: some View {
        let proofs = claim.proofItems.sorted { $0.createdAt > $1.createdAt }

        Group {
            if proofs.isEmpty {
                ContentUnavailableView(
                    "No Proof Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Add proof before you forget.")
                )
                .frame(minHeight: 180)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(proofs, id: \.id) { proof in
                        proofTile(proof)
                    }
                }
            }
        }
        .confirmationDialog("Remove this proof?", isPresented: Binding(get: { proofPendingRemoval != nil }, set: { if !$0 { proofPendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove Proof", role: .destructive) {
                if let proofPendingRemoval {
                    remove(proofPendingRemoval)
                }
                proofPendingRemoval = nil
            }
        } message: {
            Text("This removes the proof reference and its local file from this device.")
        }
        .sheet(item: $selectedProof) { proof in
            ProofPreviewView(proof: proof)
        }
        .alert("DueProof", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func proofTile(_ proof: ProofItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedProof = proof
            } label: {
                proofThumbnail(proof)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens proof preview")

            proofFooter(proof)
        }
        .padding(10)
        .dueProofCardBackground(cornerRadius: AppTheme.compactCornerRadius)
    }

    @ViewBuilder
    private func proofThumbnail(_ proof: ProofItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                .fill(.quaternary)

            if let localFileName = proof.localFileName,
               let image = FileStorageService.shared.thumbnail(for: localFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                    .accessibilityLabel(proof.displayName)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: proof.type == .document ? "doc.text" : "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(proof.type == .document ? "Document" : "Missing Photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(proof.type == .document ? "Proof document" : "Missing proof photo")
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    private func proofFooter(_ proof: ProofItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(proof.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(DateHelpers.shortDate(proof.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if proof.extractedText?.isEmpty == false {
                    Label("Searchable", systemImage: "text.viewfinder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                if let completeness = proof.intelligence?.completeness.displayPercent {
                    Label("\(completeness) complete", systemImage: "brain.head.profile")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer()

            Button(role: .destructive) {
                proofPendingRemoval = proof
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove proof")
        }
    }

    private func remove(_ proof: ProofItem) {
        let localFileName = proof.localFileName
        modelContext.delete(proof)
        claim.touch()

        do {
            try modelContext.save()
            let removedFile = FileStorageService.shared.deleteFile(named: localFileName)
            if !removedFile {
                errorMessage = "DueProof removed the proof record, but could not remove the local proof file."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProofPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let proof: ProofItem

    var body: some View {
        NavigationStack {
            List {
                if let localFileName = proof.localFileName,
                   let image = FileStorageService.shared.image(for: localFileName) {
                    Section("Proof") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                            .accessibilityLabel(proof.displayName)
                    }
                } else if proof.type == .document,
                          FileStorageService.shared.fileExists(named: proof.localFileName) {
                    Section("Proof") {
                        ContentUnavailableView(
                            "Document Ready",
                            systemImage: "doc.text",
                            description: Text("Use Share to open or save this proof document.")
                        )
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Proof Unavailable",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text("The local proof file could not be found on this device.")
                        )
                    }
                }

                intelligenceSection
                extractedTextSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(proof.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let localFileName = proof.localFileName,
                       let url = FileStorageService.shared.url(for: localFileName) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share proof")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var intelligenceSection: some View {
        if let intelligence = proof.intelligence {
            Section("Proof Intelligence") {
                Label(intelligence.summary, systemImage: "brain.head.profile")
                    .font(.subheadline)

                LabeledContent("Completeness", value: intelligence.completeness.displayPercent)
                    .monospacedDigit()

                if let deadline = intelligence.deadline {
                    LabeledContent(intelligence.deadlineLabel, value: DateHelpers.fullDate(deadline))
                }

                if let orderNumber = intelligence.orderNumber {
                    LabeledContent("Order", value: orderNumber)
                }

                if !intelligence.completeness.missingFields.isEmpty {
                    Text("Missing: \(intelligence.completeness.missingFields.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(intelligence.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var extractedTextSection: some View {
        if let extractedText = proof.extractedText, !extractedText.isEmpty {
            Section("Extracted Text") {
                Text(extractedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    ProofGalleryView(claim: PreviewSampleData.sampleClaims[0])
        .modelContainer(PreviewSampleData.container())
        .padding()
}
