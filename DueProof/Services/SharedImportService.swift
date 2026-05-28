import Foundation
import SwiftData

enum SharedImportError: LocalizedError {
    case requestNotFound
    case emptyRequest

    var errorDescription: String? {
        switch self {
        case .requestNotFound:
            "DueProof could not find that shared import."
        case .emptyRequest:
            "That shared item did not include anything DueProof can import."
        }
    }
}

@MainActor
final class SharedImportService {
    static let shared = SharedImportService()

    private init() {}

    @discardableResult
    func importPendingRequests(into context: ModelContext) async throws -> Int {
        var count = 0
        for request in SharedImportQueueStore.shared.loadPendingRequests() {
            do {
                count += try await importRequest(request, into: context)
            } catch SharedImportError.emptyRequest {
                continue
            }
        }
        return count
    }

    @discardableResult
    func importRequest(id: UUID, into context: ModelContext) async throws -> Int {
        guard let request = SharedImportQueueStore.shared.load(id: id) else {
            throw SharedImportError.requestNotFound
        }
        return try await importRequest(request, into: context)
    }

    private func importRequest(_ request: SharedImportRequest, into context: ModelContext) async throws -> Int {
        guard !request.items.isEmpty else {
            SharedImportQueueStore.shared.delete(id: request.id)
            throw SharedImportError.emptyRequest
        }

        var localFileNamesCreatedByImport: [String] = []
        var proofItemsCreatedByImport: [ProofItem] = []
        let claim = Claim(
            title: Self.normalizedTitle(for: request),
            category: inferredCategory(for: request),
            merchant: nil,
            valueAtRisk: 0,
            deadline: nil,
            reminderDate: nil,
            notes: Self.notes(for: request),
            status: .active,
            createdAt: request.createdAt,
            updatedAt: Date()
        )

        for item in request.items {
            if let proof = await makeProofItem(from: item, requestID: request.id, claim: claim) {
                if let localFileName = proof.localFileName {
                    localFileNamesCreatedByImport.append(localFileName)
                }
                proofItemsCreatedByImport.append(proof)
                context.insert(proof)
                claim.proofItemsList.append(proof)
            }
        }

        guard !claim.notes.isEmpty || !claim.proofItemsList.isEmpty else {
            SharedImportQueueStore.shared.delete(id: request.id)
            throw SharedImportError.emptyRequest
        }

        context.insert(claim)
        do {
            try context.save()
            SharedImportQueueStore.shared.delete(id: request.id)
            return 1
        } catch {
            rollbackFailedImport(
                claim: claim,
                proofItems: proofItemsCreatedByImport,
                localFileNames: localFileNamesCreatedByImport,
                context: context
            )
            try? context.save()
            throw error
        }
    }

    static func normalizedTitle(for request: SharedImportRequest) -> String {
        if let title = normalizedTitleText(request.suggestedTitle, limit: ClaimTextLimits.title, stripsPathComponent: true) {
            return title
        }

        for item in request.items {
            if let originalFileName = item.originalFileName {
                let lastComponent = (originalFileName as NSString).lastPathComponent
                let baseName = (lastComponent as NSString).deletingPathExtension
                if let fileTitle = normalizedTitleText(baseName, limit: ClaimTextLimits.title, stripsPathComponent: true) {
                    return fileTitle
                }
            }

            if let textTitle = normalizedTitleText(item.text, limit: 80, stripsPathComponent: false) {
                return textTitle
            }
        }

        return "Shared Proof"
    }

    private static func normalizedTitleText(_ value: String?, limit: Int, stripsPathComponent: Bool) -> String? {
        let source = stripsPathComponent ? ((value ?? "") as NSString).lastPathComponent : (value ?? "")
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(max(1, limit)))
    }

    private func inferredCategory(for request: SharedImportRequest) -> ClaimCategory {
        request.items.contains { $0.kind == .document || $0.kind == .image } ? .document : .other
    }

    static func notes(for request: SharedImportRequest) -> String {
        var parts: [String] = []

        if let sourceApplication = ClaimTextLimits.optional(request.sourceApplication, limit: ClaimTextLimits.merchant) {
            parts.append("Shared from \(sourceApplication).")
        }

        for item in request.items {
            switch item.kind {
            case .text:
                guard let text = ClaimTextLimits.optional(item.text, limit: ClaimTextLimits.notes) else { continue }
                parts.append(String(text.prefix(4_000)))
            case .url:
                guard let urlString = Claim.normalizedActionURLString(item.urlString ?? item.text) else { continue }
                parts.append(urlString)
            case .image, .document:
                continue
            }
        }

        return ClaimTextLimits.required(parts.joined(separator: "\n\n"), limit: ClaimTextLimits.notes)
    }

    private func makeProofItem(
        from item: SharedImportItem,
        requestID: UUID,
        claim: Claim
    ) async -> ProofItem? {
        switch item.kind {
        case .text:
            guard let text = ClaimTextLimits.optional(item.text, limit: 12_000) else { return nil }
            return ProofItem(
                type: .note,
                displayName: "Shared Text",
                extractedText: text,
                claim: claim
            )
        case .url:
            guard let urlString = Claim.normalizedActionURLString(item.urlString ?? item.text) else { return nil }
            return ProofItem(
                type: .note,
                displayName: "Shared Link",
                extractedText: urlString,
                claim: claim
            )
        case .image, .document:
            guard let storedFileName = item.storedFileName,
                  let url = SharedImportQueueStore.shared.fileURL(for: requestID, storedFileName: storedFileName),
                  let data = try? FileStorageService.shared.dataForImportedProof(at: url)
            else {
                return nil
            }

            do {
                if item.kind == .image {
                    let fileName = try FileStorageService.shared.saveImageData(data, preferredName: item.originalFileName)
                    let ocrResult = await OCRService.shared.recognizeText(inImageData: data)
                    let searchableText = ocrResult.searchableText
                    let extractedText = searchableText.isEmpty ? nil : String(searchableText.prefix(12_000))
                    let intelligence = await ProofIntelligenceService.shared.analyze(
                        ocrResult: ocrResult,
                        categoryHint: .document
                    )

                    return ProofItem(
                        type: .photo,
                        localFileName: fileName,
                        displayName: item.originalFileName ?? "Shared Photo",
                        extractedText: extractedText,
                        intelligence: intelligence,
                        claim: claim
                    )
                }

                let fileName = try FileStorageService.shared.saveDocumentData(
                    data,
                    originalFileName: item.originalFileName
                )
                return ProofItem(
                    type: .document,
                    localFileName: fileName,
                    displayName: item.originalFileName ?? "Shared Document",
                    claim: claim
                )
            } catch {
                return nil
            }
        }
    }

    private func rollbackFailedImport(
        claim: Claim,
        proofItems: [ProofItem],
        localFileNames: [String],
        context: ModelContext
    ) {
        claim.proofItemsList.removeAll()
        for proof in proofItems {
            context.delete(proof)
        }
        context.delete(claim)
        localFileNames.forEach { _ = FileStorageService.shared.deleteFile(named: $0) }
    }
}
