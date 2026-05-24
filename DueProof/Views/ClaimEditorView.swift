import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ClaimEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?

    private let claim: Claim?
    private let isEditing: Bool

    @State private var title: String
    @State private var category: ClaimCategory
    @State private var merchant: String
    @State private var valueText: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var status: ClaimStatus
    @State private var notes: String
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var pendingPhotoName: String?
    @State private var pendingExtractedText: String?
    @State private var pendingProofIntelligence: ProofIntelligence?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var hasEditedTitle = false
    @State private var hasEditedValue = false
    @State private var isSmartFilling = false

    private enum Field: Hashable {
        case title
        case merchant
        case value
    }

    init(claim: Claim? = nil, initialCategory: ClaimCategory = .returnItem) {
        self.claim = claim
        self.isEditing = claim != nil

        let resolvedCategory = claim?.category ?? initialCategory
        let defaultDeadline = claim?.deadline ?? DateHelpers.defaultDeadline(for: resolvedCategory)
        let defaultReminder = claim?.reminderDate ?? DateHelpers.defaultReminderDate(for: resolvedCategory, deadline: defaultDeadline)

        _title = State(initialValue: claim?.title ?? "")
        _category = State(initialValue: resolvedCategory)
        _merchant = State(initialValue: claim?.merchant ?? "")
        _valueText = State(initialValue: claim.map { CurrencyFormatter.editingString($0.valueAtRisk) } ?? "0")
        _hasDeadline = State(initialValue: defaultDeadline != nil)
        _deadline = State(initialValue: defaultDeadline ?? Date())
        _status = State(initialValue: claim?.status ?? .active)
        _notes = State(initialValue: claim?.notes ?? "")
        _reminderEnabled = State(initialValue: claim == nil ? Self.defaultReminderEnabled(for: resolvedCategory) : claim?.reminderDate != nil)
        _reminderDate = State(initialValue: defaultReminder ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        Button {
                            isSmartFilling = true
                        } label: {
                            Label("Smart Fill from Proof", systemImage: "doc.viewfinder")
                        }
                        .accessibilityLabel("Smart Fill from Proof")
                        .accessibilityHint("Choose a proof image and review suggested claim details before saving.")
                    } footer: {
                        Text("Uses on-device text recognition. Suggestions are reviewed before anything is saved.")
                    }
                }

                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .title)

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
                        .submitLabel(.next)
                        .focused($focusedField, equals: .merchant)

                    TextField("Value at risk", text: $valueText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .focused($focusedField, equals: .value)
                        .accessibilityLabel("Value at risk")

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Claim")
                } footer: {
                    Text("Use the amount you could recover or lose if this deadline is missed.")
                }

                Section {
                    Toggle("Has deadline", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    }

                    Picker("Status", selection: $status) {
                        ForEach(ClaimStatus.allCases) { status in
                            Label(status.displayName, systemImage: status.symbolName)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Deadline")
                } footer: {
                    Text(defaultsSummary)
                }

                Section {
                    Toggle("Remind me", isOn: $reminderEnabled)

                    if reminderEnabled {
                        DatePicker("Reminder date", selection: $reminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        Text("DueProof uses local notifications only. No remote push service is used.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text("Reminder permission is requested only when you save a claim with reminders enabled.")
                }

                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(pendingPhotoName ?? "Add Proof Photo", systemImage: "photo.badge.plus")
                    }

                    if pendingPhotoData != nil {
                        Label("Photo ready to save", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    if pendingExtractedText != nil {
                        Label("Proof text will be searchable", systemImage: "text.viewfinder")
                            .foregroundStyle(.secondary)
                    }

                    if let pendingProofIntelligence {
                        Label("Proof analyzed: \(pendingProofIntelligence.completeness.displayPercent) complete", systemImage: "brain.head.profile")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Proof analyzed on device. \(pendingProofIntelligence.completeness.displayPercent) complete.")
                    }
                } header: {
                    Text("Proof")
                } footer: {
                    Text("Proof photos are copied into local app storage. Readable text is kept on device for search.")
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Notes")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Claim" : "Add Claim")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
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
            .onAppear {
                guard !isEditing else { return }
                focusedField = .title
            }
            .onChange(of: title) { _, _ in
                hasEditedTitle = true
            }
            .onChange(of: valueText) { _, _ in
                hasEditedValue = true
            }
            .onChange(of: category) { _, newCategory in
                guard !isEditing else { return }
                applyDefaults(for: newCategory)
            }
            .onChange(of: hasDeadline) { _, _ in
                normalizeReminderDateIfNeeded()
            }
            .onChange(of: deadline) { _, _ in
                normalizeReminderDateIfNeeded()
            }
            .onChange(of: reminderEnabled) { _, isEnabled in
                if isEnabled {
                    normalizeReminderDateIfNeeded()
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadPhoto(newItem) }
            }
            .sheet(isPresented: $isSmartFilling) {
                SmartFillView(initialCategory: category, onCreated: {
                    dismiss()
                })
            }
        }
    }

    private var parsedValue: Double? {
        CurrencyFormatter.parse(valueText)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedValue ?? -1) >= 0
            && reminderValidationMessage == nil
    }

    private var validationMessage: String? {
        if hasEditedTitle, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Title is required."
        }

        if hasEditedValue, parsedValue == nil || (parsedValue ?? -1) < 0 {
            return "Enter a valid value at risk."
        }

        if let reminderValidationMessage {
            return reminderValidationMessage
        }

        return nil
    }

    private var reminderValidationMessage: String? {
        guard reminderEnabled, status.isOpen else { return nil }

        if reminderDate <= Date() {
            return "Choose a future reminder."
        }

        if hasDeadline, reminderDate > deadline {
            return "Choose a reminder before the deadline."
        }

        return nil
    }

    private var defaultsSummary: String {
        if isEditing {
            return "Changing the deadline updates this claim only."
        }

        switch category {
        case .returnItem:
            return "Returns default to 30 days, with a reminder 7 days before."
        case .giftCard:
            return "Gift cards default to no strict deadline and a reminder in 30 days."
        case .warranty:
            return "Warranties default to one year, with a reminder 30 days before."
        case .reimbursement, .rebate:
            return "Claims default to 30 days, with a reminder 7 days before."
        case .subscription:
            return "Trials default to a reminder before cancellation."
        case .renewal:
            return "Renewals default to a reminder before the renewal date."
        case .document:
            return "Documents default to a 30-day review deadline, with a reminder 7 days before."
        case .other:
            return "You can adjust the deadline, reminder, or turn them off."
        }
    }

    @MainActor
    private func save() async {
        guard let value = parsedValue, isValid else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedDeadline = hasDeadline ? deadline : nil
            let resolvedReminder = reminderEnabled && status.isOpen ? reminderDate : nil
            let targetClaim: Claim

            if let claim {
                claim.title = normalizedTitle
                claim.category = category
                claim.merchant = normalizedMerchant.isEmpty ? nil : normalizedMerchant
                claim.valueAtRisk = value
                claim.deadline = resolvedDeadline
                claim.reminderDate = resolvedReminder
                claim.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                claim.status = status
                applyCompletionState(to: claim)
                claim.touch()
                targetClaim = claim
            } else {
                let claim = Claim(
                    title: normalizedTitle,
                    category: category,
                    merchant: normalizedMerchant.isEmpty ? nil : normalizedMerchant,
                    valueAtRisk: value,
                    deadline: resolvedDeadline,
                    reminderDate: resolvedReminder,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: status
                )
                applyCompletionState(to: claim)
                modelContext.insert(claim)
                targetClaim = claim
            }

            if let pendingPhotoData {
                let fileName = try FileStorageService.shared.saveImageData(pendingPhotoData, preferredName: normalizedTitle)
                let proof = ProofItem(
                    type: .photo,
                    localFileName: fileName,
                    displayName: pendingPhotoName ?? "Proof Photo",
                    extractedText: pendingExtractedText,
                    intelligence: pendingProofIntelligence,
                    claim: targetClaim
                )
                modelContext.insert(proof)
                targetClaim.proofItems.append(proof)
                targetClaim.touch()
            }

            try modelContext.save()

            if reminderEnabled, targetClaim.status.isOpen {
                await NotificationService.shared.scheduleReminder(for: targetClaim)
            } else {
                NotificationService.shared.cancelReminder(for: targetClaim)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyCompletionState(to claim: Claim) {
        switch claim.status {
        case .recovered:
            claim.completedAt = claim.completedAt ?? Date()
            claim.recoveredValue = claim.recoveredValue == 0 ? claim.valueAtRisk : claim.recoveredValue
        case .used, .ignored:
            claim.completedAt = claim.completedAt ?? Date()
        case .expired:
            claim.completedAt = claim.completedAt
        case .active, .urgent, .overdue:
            claim.completedAt = nil
            claim.recoveredValue = 0
        }
    }

    private func applyDefaults(for category: ClaimCategory) {
        let defaultDeadline = DateHelpers.defaultDeadline(for: category)
        hasDeadline = defaultDeadline != nil
        deadline = defaultDeadline ?? Date()

        let defaultReminder = DateHelpers.defaultReminderDate(for: category, deadline: defaultDeadline)
        reminderDate = defaultReminder ?? Date()
        reminderEnabled = Self.defaultReminderEnabled(for: category)
        normalizeReminderDateIfNeeded()
    }

    private static func defaultReminderEnabled(for category: ClaimCategory) -> Bool {
        switch category {
        case .returnItem, .giftCard, .warranty, .reimbursement, .rebate, .subscription, .renewal, .document:
            true
        case .other:
            false
        }
    }

    private func normalizeReminderDateIfNeeded() {
        guard reminderEnabled else { return }

        let fallback = Date().addingTimeInterval(60 * 60 * 24)

        if hasDeadline {
            let defaultReminder = DateHelpers.defaultReminderDate(for: category, deadline: deadline) ?? fallback
            reminderDate = min(max(reminderDate, fallback), deadline)

            if reminderDate >= deadline {
                reminderDate = min(defaultReminder, deadline.addingTimeInterval(-60 * 60))
            }
        } else if reminderDate <= Date() {
            reminderDate = fallback
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not load that photo."
                return
            }
            pendingPhotoData = data
            pendingPhotoName = "Proof Photo"
            if let image = UIImage(data: data) {
                let result = await OCRService.shared.recognizeText(in: image)
                pendingExtractedText = result.text.isEmpty ? nil : String(result.text.prefix(12_000))
                pendingProofIntelligence = await ProofIntelligenceService.shared.analyze(ocrResult: result, categoryHint: category)
            } else {
                pendingExtractedText = nil
                pendingProofIntelligence = nil
            }
        } catch {
            errorMessage = "Could not load that photo."
        }
    }
}

#Preview("Add") {
    ClaimEditorView(initialCategory: .returnItem)
        .modelContainer(PreviewSampleData.container())
}

#Preview("Edit") {
    ClaimEditorView(claim: PreviewSampleData.sampleClaims[0])
        .modelContainer(PreviewSampleData.container())
}
