import SwiftData
import UIKit
import XCTest
@testable import DueProof

@MainActor
final class ExportImportTests: XCTestCase {
    func testJSONExportImportRoundTripAndDuplicateProtection() throws {
        let claim = Claim(
            title: "Nike return",
            category: .returnItem,
            merchant: "Nike",
            valueAtRisk: 140,
            deadline: DateHelpers.calendar.date(byAdding: .day, value: 7, to: Date()),
            notes: "Receipt in bag."
        )

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertEqual(try ImportExportService.shared.importClaims(from: exportURL, into: context), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Claim>()).count, 1)
        XCTAssertEqual(try ImportExportService.shared.importClaims(from: exportURL, into: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Claim>()).count, 1)
    }

    func testImportHandlesMissingOptionalFields() throws {
        let json = """
        {
          "claims": [
            {
              "id": "8EED90D8-87E6-4F1F-B978-7CE78F8D9071",
              "title": "Minimal import",
              "category": "giftCard",
              "valueAtRisk": 12.5,
              "status": "active"
            }
          ]
        }
        """

        let url = try writeTemporaryJSON(json)
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertEqual(try ImportExportService.shared.importClaims(from: url, into: context), 1)
        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Claim>()).first)
        XCTAssertEqual(imported.title, "Minimal import")
        XCTAssertEqual(imported.category, .giftCard)
        XCTAssertNil(imported.deadline)
    }

    func testMalformedJSONThrowsWithoutCreatingRecords() throws {
        let url = try writeTemporaryJSON("{ not valid json")
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertThrowsError(try ImportExportService.shared.importClaims(from: url, into: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Claim>()).count, 0)
    }

    func testImportSkipsMissingProofFileReferences() throws {
        let json = """
        {
          "claims": [
            {
              "id": "4924EDCB-1B01-44CC-9477-D00CD7D3804D",
              "title": "Imported claim",
              "category": "returnItem",
              "valueAtRisk": 48,
              "status": "active",
              "proofItems": [
                {
                  "id": "6A0DB98F-53DE-4505-A13A-A5B1C2756F9D",
                  "type": "photo",
                  "localFileName": "missing-proof.jpg",
                  "displayName": "Missing proof",
                  "createdAt": "2026-05-21T12:00:00Z"
                }
              ]
            }
          ]
        }
        """

        let url = try writeTemporaryJSON(json)
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertEqual(try ImportExportService.shared.importClaims(from: url, into: context), 1)
        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Claim>()).first)
        XCTAssertTrue(imported.proofItems.isEmpty)
    }

    func testCompleteExportCarriesProofImageDataAcrossContainers() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let originalFileName = try FileStorageService.shared.saveImageData(try XCTUnwrap(image.pngData()))
        defer { FileStorageService.shared.deleteFile(named: originalFileName) }

        let claim = Claim(
            title: "Proof export",
            category: .returnItem,
            valueAtRisk: 50
        )
        let proof = ProofItem(
            type: .photo,
            localFileName: originalFileName,
            displayName: "Receipt",
            extractedText: "Nike total 50 return by June 20",
            intelligence: ProofIntelligence(
                merchant: "Nike",
                category: .returnItem,
                valueAtRisk: 50,
                purchaseDate: nil,
                deadline: DateHelpers.calendar.date(byAdding: .day, value: 7, to: Date()),
                deadlineIsExplicit: true,
                orderNumber: "NKE-5000",
                confidence: 0.86,
                warnings: [],
                summary: "Nike return proof is ready.",
                completeness: ProofCompleteness(
                    score: 0.8,
                    hasMerchant: true,
                    hasValue: true,
                    hasPurchaseDate: false,
                    hasDeadline: true,
                    hasReadableText: true,
                    missingFields: ["purchase date"]
                )
            ),
            claim: claim
        )
        claim.proofItems.append(proof)

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ClaimExportBundle.self, from: Data(contentsOf: exportURL))
        XCTAssertTrue(bundle.includesBinaryProofData)
        XCTAssertNotNil(bundle.claims.first?.proofItems.first?.binaryProofData)
        XCTAssertEqual(bundle.claims.first?.proofItems.first?.extractedText, "Nike total 50 return by June 20")
        XCTAssertEqual(bundle.claims.first?.proofItems.first?.intelligence?.orderNumber, "NKE-5000")

        let container = try makeContainer()
        let context = container.mainContext
        XCTAssertEqual(try ImportExportService.shared.importClaims(from: exportURL, into: context), 1)

        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Claim>()).first)
        let importedProof = try XCTUnwrap(imported.proofItems.first)
        XCTAssertEqual(importedProof.extractedText, "Nike total 50 return by June 20")
        XCTAssertEqual(importedProof.intelligence?.summary, "Nike return proof is ready.")
        XCTAssertTrue(FileStorageService.shared.fileExists(named: importedProof.localFileName))
        FileStorageService.shared.deleteFile(named: importedProof.localFileName)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Claim.self, ProofItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func writeTemporaryJSON(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try Data(json.utf8).write(to: url, options: [.atomic])
        return url
    }
}
