@preconcurrency import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

final class SpotlightIndexService {
    static let shared = SpotlightIndexService()
    static let claimIdentifierPrefix = "claim:"

    private let domainIdentifier = "com.hardik.dueproof.claims"

    private init() {}

    @MainActor
    func reindex(claims: [Claim]) {
        let items = claims.map(searchableItem)

        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            guard !items.isEmpty else { return }

            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    print("DueProof Spotlight indexing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func deleteAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
    }

    private func searchableItem(for claim: Claim) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = claim.title
        attributes.displayName = claim.title
        attributes.contentDescription = contentDescription(for: claim)
        attributes.keywords = keywords(for: claim)
        attributes.textContent = searchableText(for: claim)

        if let thumbnailData = thumbnailData(for: claim) {
            attributes.thumbnailData = thumbnailData
        }

        let identifier = Self.identifier(for: claim)
        let item = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        return item
    }

    private static func identifier(for claim: Claim) -> String {
        claimIdentifierPrefix + claim.id.uuidString
    }

    private func contentDescription(for claim: Claim) -> String {
        var parts = [
            claim.categoryDisplayName,
            claim.statusDisplayName,
            "\(claim.displayValue) at risk",
            claim.urgencyLabel
        ]

        if let merchant = claim.merchant {
            parts.insert(merchant, at: 1)
        }

        if claim.proofItemsList.isEmpty {
            parts.append("Missing proof")
        } else {
            parts.append("\(claim.proofItemsList.count) proof item\(claim.proofItemsList.count == 1 ? "" : "s")")
        }

        return parts.joined(separator: " | ")
    }

    private func keywords(for claim: Claim) -> [String] {
        var values = [
            "DueProof",
            "claim",
            "proof",
            "receipt",
            "deadline",
            claim.title,
            claim.categoryDisplayName,
            claim.category.pluralDisplayName,
            claim.statusDisplayName,
            claim.urgencyLabel
        ]

        if let merchant = claim.merchant {
            values.append(merchant)
        }

        if claim.proofItemsList.isEmpty {
            values.append("missing proof")
        }

        return Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func searchableText(for claim: Claim) -> String {
        var values = [
            claim.title,
            claim.categoryDisplayName,
            claim.statusDisplayName,
            claim.urgencyLabel,
            claim.notes
        ]

        if let merchant = claim.merchant {
            values.append(merchant)
        }

        values.append(contentsOf: claim.proofItemsList.compactMap(\.extractedText))

        return String(values.joined(separator: "\n").prefix(20_000))
    }

    private func thumbnailData(for claim: Claim) -> Data? {
        for proof in claim.proofItemsList {
            guard proof.type == .photo,
                  let thumbnail = FileStorageService.shared.thumbnail(for: proof, maxPixelSize: 180)
            else {
                continue
            }

            return thumbnail.jpegData(compressionQuality: 0.72)
        }

        return nil
    }
}
