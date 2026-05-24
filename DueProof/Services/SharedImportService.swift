import Foundation
import SwiftData
import UIKit

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
            count += try await importRequest(request, into: context)
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

        let claim = Claim(
            title: normalizedTitle(for: request),
            category: inferredCategory(for: request),
            merchant: nil,
            valueAtRisk: 0,
            deadline: nil,
            reminderDate: nil,
            notes: notes(for: request),
            status: .active,
            createdAt: request.createdAt,
            updatedAt: Date()
        )

        for item in request.items {
            if let proof = await makeProofItem(from: item, requestID: request.id, claim: claim) {
                context.insert(proof)
                claim.proofItemsList.append(proof)
            }
        }

        guard !claim.notes.isEmpty || !claim.proofItemsList.isEmpty else {
            SharedImportQueueStore.shared.delete(id: request.id)
            throw SharedImportError.emptyRequest
        }

        context.insert(claim)
        try context.save()
        SharedImportQueueStore.shared.delete(id: request.id)
        return 1
    }

    private func normalizedTitle(for request: SharedImportRequest) -> String {
        let title = request.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return String(title.prefix(160))
        }

        for item in request.items {
            if let originalFileName = item.originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !originalFileName.isEmpty {
                return String((originalFileName as NSString).deletingPathExtension.prefix(160))
            }

            if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return String(text.prefix(80))
            }
        }

        return "Shared Proof"
    }

    private func inferredCategory(for request: SharedImportRequest) -> ClaimCategory {
        request.items.contains { $0.kind == .document || $0.kind == .image } ? .document : .other
    }

    private func notes(for request: SharedImportRequest) -> String {
        var parts: [String] = []

        if let sourceApplication = request.sourceApplication, !sourceApplication.isEmpty {
            parts.append("Shared from \(sourceApplication).")
        }

        for item in request.items {
            if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                parts.append(String(text.prefix(4_000)))
            }

            if let urlString = item.urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
                parts.append(urlString)
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private func makeProofItem(
        from item: SharedImportItem,
        requestID: UUID,
        claim: Claim
    ) async -> ProofItem? {
        switch item.kind {
        case .text, .url:
            guard let text = item.text ?? item.urlString else { return nil }
            return ProofItem(
                type: .note,
                displayName: item.kind == .url ? "Shared Link" : "Shared Text",
                extractedText: String(text.prefix(12_000)),
                claim: claim
            )
        case .image, .document:
            guard let storedFileName = item.storedFileName,
                  let url = SharedImportQueueStore.shared.fileURL(for: requestID, storedFileName: storedFileName),
                  let data = try? Data(contentsOf: url)
            else {
                return nil
            }

            do {
                if item.kind == .image, let image = UIImage(data: data) {
                    let fileName = try FileStorageService.shared.saveImageData(data, preferredName: item.originalFileName)
                    let ocrResult = await OCRService.shared.recognizeText(in: image)
                    let extractedText = ocrResult.text.isEmpty ? nil : String(ocrResult.text.prefix(12_000))
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
}
