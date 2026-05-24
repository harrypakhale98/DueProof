import SwiftData
import SwiftUI
import UIKit

struct ClaimDraftReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private let proofData: Data?
    private let proofType: ProofItemType
    private let proofDisplayName: String
    private let proofImage: UIImage?
    private let ocrResult: OCRResult
    private let proofIntelligence: ProofIntelligence?
    private let onCreated: (() -> Void)?
    private let onEditManually: (() -> Void)?

    @State private var title: String
    @State private var category: ClaimCategory
    @State private var merchant: String
    @State private var valueText: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date
    @State private var notes: String
    @State private var warnings: [String]
    @State private var errorMessage: String?
    @State private var isSaving = false

    private enum Field: Hashable {
        case title
        case merchant
        case value
    }

    init(
        draft: ClaimDraft,
        ocrResult: OCRResult,
        proofData: Data?,
        proofType: ProofItemType = .photo,
        proofDisplayName: String = "Smart Fill Proof",
        proofImage: UIImage?,
        proofIntelligence: ProofIntelligence? = nil,
        onCreated: (() -> Void)? = nil,
        onEditManually: (() -> Void)? = nil
    ) {
        self.proofData = proofData
        self.proofType = proofType
        self.proofDisplayName = proofDisplayName
        self.proofImage = proofImage
        self.ocrResult = ocrResult
        self.proofIntelligence = proofIntelligence
        self.onCreated = onCreated
        self.onEditManually = onEditManually

        let resolvedCategory = draft.category ?? .other
        let resolvedDeadline = draft.suggestedDeadline ?? DateHelpers.defaultDeadline(for: resolvedCategory) ?? Date()
        let resolvedReminder = draft.reminderDate ?? DateHelpers.defaultReminderDate(for: resolvedCategory, deadline: draft.suggestedDeadline) ?? Date().addingTimeInterval(60 * 60 * 24)

        _title = State(initialValue: draft.title ?? "Proof Claim")
        _category = State(initialValue: resolvedCategory)
        _merchant = State(initialValue: draft.merchant ?? "")
        _valueText = State(initialValue: draft.valueAtRisk.map(CurrencyFormatter.editingString) ?? "")
        _hasDeadline = State(initialValue: draft.suggestedDeadline != nil)
        _deadline = State(initialValue: resolvedDeadline)
        _reminderEnabled = State(initialValue: draft.reminderDate != nil)
        _reminderDate = State(initialValue: max(resolvedReminder, Date().addingTimeInterval(60 * 60)))
        _notes = State(initialValue: draft.notes ?? "")
        _warnings = State(initialValue: draft.warnings)
    }

    var body: some View {
        Form {
            privacySection
            warningSection
            proofIntelligenceSection
            proofPreviewSection
            claimSection
            valueSection
            deadlineSection
            reminderSection
            notesSection
            extractedTextSection

            Section {
                Button("Edit Manually") {
                    if let onEditManually {
                        onEditManually()
                    } else {
                        dismiss()
                    }
                }
            } footer: {
                Text("Nothing is saved until you create the claim.")
            }
        }
        .navigationTitle("Review Claim")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Creating" : "Create Claim") {
                    Task { await createClaim() }
                }
                .disabled(!isValid || isSaving)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .alert("DueProof", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var privacySection: some View {
        Section {
            Label("Processed on this iPhone. Not uploaded.", systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Processed on this iPhone. Not uploaded.")
        }
    }

    @ViewBuilder
    private var proofIntelligenceSection: some View {
        if let proofIntelligence {
            Section("Proof Intelligence") {
                Label(proofIntelligence.summary, systemImage: "brain.head.profile")
                    .font(.subheadline)
                    .accessibilityLabel(proofIntelligence.summary)

                HStack {
                    Label("Completeness", systemImage: "checklist")
                    Spacer()
                    Text(proofIntelligence.completeness.displayPercent)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)

                if proofIntelligence.deadline != nil {
                    Label(proofIntelligence.deadlineLabel, systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let orderNumber = proofIntelligence.orderNumber {
                    LabeledContent("Order") {
                        Text(orderNumber)
                            .textSelection(.enabled)
                    }
                }

                if !proofIntelligence.completeness.missingFields.isEmpty {
                    Text("Review missing: \(proofIntelligence.completeness.missingFields.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var warningSection: some View {
        if !warnings.isEmpty {
            Section("Review") {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(warning)
                }
            }
        }
    }

    @ViewBuilder
    private var proofPreviewSection: some View {
        if let proofImage {
            Section("Proof") {
                Image(uiImage: proofImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                    .accessibilityLabel("Selected proof image")
            }
        } else if proofData != nil {
            Section("Proof") {
                Label(proofDisplayName, systemImage: proofType == .document ? "doc.text" : "photo")
                    .accessibilityLabel("\(proofDisplayName) proof selected")

                if !ocrResult.text.isEmpty {
                    Text("Readable text will be saved for search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var claimSection: some View {
        Section("Claim") {
            TextField("Title", text: $title)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .title)
                .accessibilityLabel("Claim title")

            Picker("Category", selection: $category) {
                ForEach(ClaimCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.iconName)
                        .tag(category)
                }
            }
            .pickerStyle(.navigationLink)

            TextField("Merchant or provider", text: $merchant)
                .textInputAutocapitalization(.words)
                .textContentType(.organizationName)
                .focused($focusedField, equals: .merchant)
                .accessibilityLabel("Merchant or provider")
        }
    }

    private var valueSection: some View {
        Section {
            TextField("Value at risk", text: $valueText)
                .keyboardType(.decimalPad)
                .monospacedDigit()
                .focused($focusedField, equals: .value)
                .accessibilityLabel("Value at risk")
        } header: {
            Text("Value")
        } footer: {
            Text("Leave blank if the amount is not clearly visible. Warranties and documents can be saved with $0 value.")
        }
    }

    private var deadlineSection: some View {
        Section {
            Toggle("Has deadline", isOn: $hasDeadline)

            if hasDeadline {
                DatePicker("Deadline", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
            }
        } header: {
            Text("Deadline")
        } footer: {
            Text("Suggested deadlines are not guaranteed. Review the proof and merchant terms before saving.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Remind me", isOn: $reminderEnabled)

            if reminderEnabled {
                DatePicker("Reminder date", selection: $reminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])

                if let reminderValidationMessage {
                    Label(reminderValidationMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text("DueProof uses local notifications only.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 110)
                .accessibilityLabel("Notes")
        }
    }

    @ViewBuilder
    private var extractedTextSection: some View {
        if !ocrResult.text.isEmpty {
            Section {
                DisclosureGroup("Extracted Text") {
                    Text(ocrResult.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Extracted proof text")
                }
            }
        }
    }

    private var parsedValue: Double? {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return CurrencyFormatter.parse(trimmed)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedValue ?? -1) >= 0
            && reminderValidationMessage == nil
    }

    private var reminderValidationMessage: String? {
        guard reminderEnabled else { return nil }

        if reminderDate <= Date() {
            return "Choose a future reminder."
        }

        if hasDeadline, reminderDate > deadline {
            return "Choose a reminder before the deadline."
        }

        return nil
    }

    @MainActor
    private func createClaim() async {
        guard let parsedValue, isValid else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let claim = Claim(
                title: normalizedTitle,
                category: category,
                merchant: normalizedMerchant.isEmpty ? nil : normalizedMerchant,
                valueAtRisk: parsedValue,
                deadline: hasDeadline ? deadline : nil,
                reminderDate: reminderEnabled ? reminderDate : nil,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                status: .active
            )

            modelContext.insert(claim)

            if let proofData {
                let fileName: String
                switch proofType {
                case .photo:
                    fileName = try FileStorageService.shared.saveImageData(proofData, preferredName: normalizedTitle)
                case .document, .note:
                    fileName = try FileStorageService.shared.saveDocumentData(proofData, originalFileName: proofDisplayName)
                }
                let proof = ProofItem(
                    type: proofType,
                    localFileName: fileName,
                    displayName: proofDisplayName,
                    extractedText: ocrResult.text.isEmpty ? nil : String(ocrResult.text.prefix(12_000)),
                    intelligence: proofIntelligence,
                    claim: claim
                )
                modelContext.insert(proof)
                claim.proofItems.append(proof)
            }

            try modelContext.save()

            if reminderEnabled {
                await NotificationService.shared.scheduleReminder(for: claim)
            }

            onCreated?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ClaimDraftReviewView(
            draft: ClaimDraft(
                title: "Nike return",
                category: .returnItem,
                merchant: "Nike",
                valueAtRisk: 140,
                suggestedDeadline: DateHelpers.calendar.date(byAdding: .day, value: 30, to: Date()),
                confidence: 0.72,
                warnings: [ClaimDraftValidator.reviewWarning],
                sourceSummary: "Nike total $140"
            ),
            ocrResult: OCRResult(text: "Nike\nTotal $140.00"),
            proofData: nil,
            proofImage: nil
        )
    }
    .modelContainer(PreviewSampleData.container())
}
