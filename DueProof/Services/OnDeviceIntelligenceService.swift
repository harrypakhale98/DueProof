import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

final class OnDeviceIntelligenceService {
    static let shared = OnDeviceIntelligenceService()

    private let availabilityService: IntelligenceAvailabilityService

    init(availabilityService: IntelligenceAvailabilityService = .shared) {
        self.availabilityService = availabilityService
    }

    func generateDraft(from ocrText: String) async -> ClaimDraft? {
        guard availabilityService.availability().isAvailable else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generateWithFoundationModels(from: ocrText)
        }
        #endif

        return nil
    }

    func analyzeProof(from ocrText: String, categoryHint: ClaimCategory? = nil) async -> ProofIntelligence? {
        guard availabilityService.availability().isAvailable else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await analyzeProofWithFoundationModels(from: ocrText, categoryHint: categoryHint)
        }
        #endif

        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithFoundationModels(from ocrText: String) async -> ClaimDraft? {
        let instructions = """
        Convert OCR text from a receipt, gift card, warranty, reimbursement, rebate, renewal, subscription, or document into a concise claim draft.
        Return only fields that are visible or strongly implied by the text.
        Do not claim any deadline is guaranteed.
        If a deadline is inferred from a purchase date, include a warning that it is suggested.
        For gift cards, do not suggest an expiration date unless the text clearly says one exists.
        """

        let prompt = """
        OCR text:
        \(ocrText.prefix(4_000))

        Category raw values you may use:
        returnItem, giftCard, warranty, reimbursement, rebate, subscription, renewal, document, other
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: FoundationClaimDraftPayload.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 450)
            )
            return response.content.claimDraft()
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    private func analyzeProofWithFoundationModels(
        from ocrText: String,
        categoryHint: ClaimCategory?
    ) async -> ProofIntelligence? {
        let instructions = """
        Analyze OCR text from a receipt, gift card, warranty, reimbursement, rebate, renewal, subscription, or document.
        Extract only information visible in the proof. Do not invent merchant terms.
        Extract visible order numbers, serial numbers, UPC, EAN, QR, or barcode values when present.
        Distinguish an explicit proof deadline from a deadline inferred from policy defaults.
        Keep warnings practical and short. The result is reviewed by the user before use.
        """

        let prompt = """
        OCR text:
        \(ocrText.prefix(4_000))

        Category hint:
        \(categoryHint?.rawValue ?? "none")

        Category raw values you may use:
        returnItem, giftCard, warranty, reimbursement, rebate, subscription, renewal, document, other
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: FoundationProofIntelligencePayload.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 520)
            )
            return response.content.proofIntelligence(categoryHint: categoryHint, sourceText: ocrText)
        } catch {
            return nil
        }
    }

    @Generable
    struct FoundationClaimDraftPayload {
        var title: String?
        var categoryRawValue: String?
        var merchant: String?
        var valueAtRisk: Double?
        var purchaseDateText: String?
        var suggestedDeadlineText: String?
        var reminderDateText: String?
        var notes: String?
        var confidence: Double?
        var warnings: [String]?
        var sourceSummary: String?

        func claimDraft() -> ClaimDraft {
            let category = categoryRawValue.flatMap(ClaimCategory.init(rawValue:))

            return ClaimDraft(
                title: normalized(title),
                category: category,
                merchant: normalized(merchant),
                valueAtRisk: valueAtRisk,
                purchaseDate: purchaseDateText.flatMap(ClaimDraftGenerator.parseFirstDate),
                suggestedDeadline: suggestedDeadlineText.flatMap(ClaimDraftGenerator.parseFirstDate),
                reminderDate: reminderDateText.flatMap(ClaimDraftGenerator.parseFirstDate),
                notes: normalized(notes),
                confidence: min(max(confidence ?? 0.65, 0), 1),
                warnings: warnings ?? [],
                sourceSummary: normalized(sourceSummary)
            )
        }

        private func normalized(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    @Generable
    struct FoundationProofIntelligencePayload {
        var merchant: String?
        var categoryRawValue: String?
        var valueAtRisk: Double?
        var purchaseDateText: String?
        var deadlineText: String?
        var deadlineIsExplicit: Bool?
        var orderNumber: String?
        var serialNumber: String?
        var barcodeValues: [String]?
        var confidence: Double?
        var warnings: [String]?
        var summary: String?

        func proofIntelligence(categoryHint: ClaimCategory?, sourceText: String) -> ProofIntelligence {
            let resolvedMerchant = normalized(merchant)
            let category = categoryRawValue.flatMap(ClaimCategory.init(rawValue:)) ?? categoryHint
            let value = valueAtRisk.flatMap { $0 >= 0 ? $0 : nil }
            let purchaseDate = purchaseDateText.flatMap(ClaimDraftGenerator.parseFirstDate)
            let deadline = deadlineText.flatMap(ClaimDraftGenerator.parseFirstDate)
            let hasReadableText = !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let normalizedBarcodeValues = (barcodeValues ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { String($0.prefix(120)) }
            let completeness = ProofIntelligenceService.completeness(
                merchant: resolvedMerchant,
                value: value,
                purchaseDate: purchaseDate,
                deadline: deadline,
                hasReadableText: hasReadableText
            )
            let deadlineIsExplicit = deadline == nil ? false : (deadlineIsExplicit ?? false)

            return ProofIntelligence(
                merchant: resolvedMerchant,
                category: category,
                valueAtRisk: value,
                purchaseDate: purchaseDate,
                deadline: deadline,
                deadlineIsExplicit: deadlineIsExplicit,
                orderNumber: normalized(orderNumber),
                serialNumber: normalized(serialNumber),
                barcodeValues: Array(Set(normalizedBarcodeValues)).sorted(),
                confidence: min(max(confidence ?? 0.65, 0), 1),
                warnings: warnings ?? [],
                summary: normalized(summary) ?? Self.summary(
                    merchant: resolvedMerchant,
                    category: category,
                    value: value,
                    deadline: deadline,
                    deadlineIsExplicit: deadlineIsExplicit,
                    identifier: normalized(orderNumber) ?? normalized(serialNumber) ?? normalizedBarcodeValues.first,
                    completeness: completeness
                ),
                completeness: completeness
            )
        }

        private func normalized(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
        }

        private static func summary(
            merchant: String?,
            category: ClaimCategory?,
            value: Double?,
            deadline: Date?,
            deadlineIsExplicit: Bool,
            identifier: String?,
            completeness: ProofCompleteness
        ) -> String {
            let subject = merchant ?? category?.displayName ?? "Proof"
            let valueText = value.map(CurrencyFormatter.string) ?? "no clear value"
            let deadlineText = deadline.map { DateHelpers.deadlineText(for: $0).lowercased() } ?? "no clear deadline"
            let deadlineSource = deadlineIsExplicit ? "found in the proof" : "suggested"
            let identifierText = identifier.map { " Identifier: \($0)." } ?? ""

            if completeness.score >= 0.8 {
                return "\(subject) proof includes \(valueText) and a \(deadlineText) deadline \(deadlineSource).\(identifierText)"
            }

            if completeness.missingFields.isEmpty {
                return "\(subject) proof is ready to review.\(identifierText)"
            }

            return "\(subject) proof needs review: missing \(completeness.missingFields.joined(separator: ", ")).\(identifierText)"
        }
    }
    #endif
}
