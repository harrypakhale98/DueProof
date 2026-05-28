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
    @State private var referenceNumber: String
    @State private var policySummary: String
    @State private var actionURLString: String
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
        case reference
        case actionURL
    }

    init(claim: Claim? = nil, initialCategory: ClaimCategory = .returnItem) {
        self.claim = claim
        self.isEditing = claim != nil

        let resolvedCategory = claim?.category ?? initialCategory
        let categoryDefaultDeadline = DateHelpers.defaultDeadline(for: resolvedCategory)
        let resolvedDeadline = claim == nil ? categoryDefaultDeadline : claim?.deadline
        let deadlinePickerDate = resolvedDeadline ?? categoryDefaultDeadline ?? Date()
        let defaultReminder = DateHelpers.defaultReminderDate(
            for: resolvedCategory,
            deadline: deadlinePickerDate
        )
        let resolvedReminder = claim?.reminderDate ?? (claim == nil ? defaultReminder : nil)

        _title = State(initialValue: claim?.title ?? "")
        _category = State(initialValue: resolvedCategory)
        _merchant = State(initialValue: claim?.merchant ?? "")
        _valueText = State(initialValue: claim.map { CurrencyFormatter.editingString($0.valueAtRisk) } ?? "0")
        _hasDeadline = State(initialValue: resolvedDeadline != nil)
        _deadline = State(initialValue: deadlinePickerDate)
        _status = State(initialValue: ClaimStatus.normalizedStoredStatus(claim?.status ?? .active))
        _referenceNumber = State(initialValue: claim?.referenceNumber ?? "")
        _policySummary = State(initialValue: claim?.policySummary ?? "")
        _actionURLString = State(initialValue: claim?.actionURLString ?? "")
        _notes = State(initialValue: claim?.notes ?? "")
        _reminderEnabled = State(initialValue: claim == nil ? Self.defaultReminderEnabled(for: resolvedCategory) : claim?.reminderDate != nil)
        _reminderDate = State(initialValue: resolvedReminder ?? defaultReminder ?? Date().addingTimeInterval(60 * 60 * 24))
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
                        ForEach(ClaimStatus.editableCases) { status in
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
                    TextField("Reference, order, serial, or claim number", text: $referenceNumber)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .reference)
                        .accessibilityLabel("Reference, order, serial, or claim number")

                    TextField("Action, support, or cancellation URL", text: $actionURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .actionURL)
                        .accessibilityLabel("Action, support, or cancellation URL")

                    TextEditor(text: $policySummary)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Policy, terms, or next-step summary")
                } header: {
                    Text("Action Details")
                } footer: {
                    Text("Use this for warranty terms, return policy notes, gift card balance rules, claim numbers, or cancellation links.")
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
            && actionURLValidationMessage == nil
            && reminderValidationMessage == nil
    }

    private var validationMessage: String? {
        if hasEditedTitle, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Title is required."
        }

        if hasEditedValue, parsedValue == nil || (parsedValue ?? -1) < 0 {
            return "Enter a valid value at risk."
        }

        if let actionURLValidationMessage {
            return actionURLValidationMessage
        }

        if let reminderValidationMessage {
            return reminderValidationMessage
        }

        return nil
    }

    private var actionURLValidationMessage: String? {
        let trimmed = actionURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Claim.normalizedActionURLString(trimmed) == nil
            ? "Enter a valid support link, email address link, or phone link."
            : nil
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
        let existingClaimSnapshot = claim.map(ClaimMutationSnapshot.init)
        var createdLocalFileName: String?
        var insertedClaim: Claim?
        var createdProof: ProofItem?

        do {
            let normalizedTitle = ClaimTextLimits.required(title, limit: ClaimTextLimits.title)
            let normalizedMerchant = ClaimTextLimits.required(merchant, limit: ClaimTextLimits.merchant)
            let normalizedActionURL = Claim.normalizedActionURLString(actionURLString)
            let resolvedDeadline = hasDeadline ? deadline : nil
            let resolvedStatus = ClaimStatus.normalizedStoredStatus(status)
            let resolvedReminder = reminderEnabled && resolvedStatus.isOpen ? reminderDate : nil
            let targetClaim: Claim

            if let claim {
                claim.title = normalizedTitle
                claim.category = category
                claim.merchant = normalizedMerchant.isEmpty ? nil : normalizedMerchant
                claim.valueAtRisk = value
                claim.deadline = resolvedDeadline
                claim.reminderDate = resolvedReminder
                claim.referenceNumber = ClaimTextLimits.optional(referenceNumber, limit: ClaimTextLimits.reference)
                claim.policySummary = ClaimTextLimits.required(policySummary, limit: ClaimTextLimits.policySummary)
                claim.actionURLString = normalizedActionURL
                claim.notes = ClaimTextLimits.required(notes, limit: ClaimTextLimits.notes)
                claim.status = resolvedStatus
                applyCompletionState(to: claim)
                claim.normalizeStoredFields()
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
                    referenceNumber: ClaimTextLimits.optional(referenceNumber, limit: ClaimTextLimits.reference),
                    policySummary: ClaimTextLimits.required(policySummary, limit: ClaimTextLimits.policySummary),
                    actionURLString: normalizedActionURL,
                    notes: ClaimTextLimits.required(notes, limit: ClaimTextLimits.notes),
                    status: resolvedStatus
                )
                applyCompletionState(to: claim)
                claim.normalizeStoredFields()
                modelContext.insert(claim)
                insertedClaim = claim
                targetClaim = claim
            }

            if let pendingPhotoData {
                let fileName = try FileStorageService.shared.saveImageData(pendingPhotoData, preferredName: normalizedTitle)
                createdLocalFileName = fileName
                let proof = ProofItem(
                    type: .photo,
                    localFileName: fileName,
                    displayName: pendingPhotoName ?? "Proof Photo",
                    extractedText: pendingExtractedText,
                    intelligence: pendingProofIntelligence,
                    claim: targetClaim
                )
                createdProof = proof
                modelContext.insert(proof)
                targetClaim.proofItemsList.append(proof)
                targetClaim.touch()
            }

            try modelContext.save()
            createdLocalFileName = nil

            if reminderEnabled, targetClaim.status.isOpen {
                await NotificationService.shared.scheduleReminder(for: targetClaim)
            } else {
                NotificationService.shared.cancelReminder(for: targetClaim)
            }

            dismiss()
        } catch {
            if let createdProof {
                modelContext.delete(createdProof)
            }
            if let insertedClaim {
                modelContext.delete(insertedClaim)
            } else if let claim, let existingClaimSnapshot {
                existingClaimSnapshot.restore(to: claim)
            }
            _ = FileStorageService.shared.deleteFile(named: createdLocalFileName)
            try? modelContext.save()
            errorMessage = error.localizedDescription
        }
    }

    private func applyCompletionState(to claim: Claim) {
        switch claim.status {
        case .recovered:
            claim.completedAt = claim.completedAt ?? Date()
            let recoveredValue = CurrencyFormatter.sanitizedAmount(claim.recoveredValue)
            let valueAtRisk = CurrencyFormatter.sanitizedAmount(claim.valueAtRisk)
            claim.recoveredValue = recoveredValue > 0 ? min(recoveredValue, valueAtRisk) : valueAtRisk
        case .used, .expired, .ignored:
            claim.completedAt = claim.completedAt ?? Date()
            claim.recoveredValue = 0
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
            guard data.count <= FileStorageService.maximumProofFileBytes else {
                errorMessage = FileStorageError.proofFileTooLarge.localizedDescription
                return
            }
            pendingPhotoData = data
            pendingPhotoName = "Proof Photo"
            let result = await OCRService.shared.recognizeText(inImageData: data)
            let searchableText = result.searchableText
            pendingExtractedText = searchableText.isEmpty ? nil : String(searchableText.prefix(12_000))
            pendingProofIntelligence = await ProofIntelligenceService.shared.analyze(ocrResult: result, categoryHint: category)
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
