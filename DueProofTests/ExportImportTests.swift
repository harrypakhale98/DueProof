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
            referenceNumber: "NKE-RETURN-140",
            policySummary: "30 day return window; original packaging requested.",
            actionURLString: "https://nike.example/returns",
            notes: "Receipt in bag."
        )

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let container = try makeContainer()
        let context = container.mainContext

        let importResult = try ImportExportService.shared.importClaimsWithResult(from: exportURL, into: context)
        XCTAssertEqual(importResult.insertedCount, 1)
        XCTAssertEqual(importResult.insertedClaimIDs, [claim.id])
        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Claim>()).first)
        XCTAssertEqual(imported.referenceNumber, "NKE-RETURN-140")
        XCTAssertEqual(imported.policySummary, "30 day return window; original packaging requested.")
        XCTAssertEqual(imported.actionURLString, "https://nike.example/returns")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Claim>()).count, 1)
        let duplicateImportResult = try ImportExportService.shared.importClaimsWithResult(from: exportURL, into: context)
        XCTAssertEqual(duplicateImportResult.insertedCount, 0)
        XCTAssertTrue(duplicateImportResult.insertedClaimIDs.isEmpty)
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
        XCTAssertNil(imported.referenceNumber)
        XCTAssertEqual(imported.policySummary, "")
        XCTAssertNil(imported.actionURLString)
    }

    func testImportIgnoresMalformedDatesWithoutDroppingClaim() throws {
        let json = """
        {
          "exportedAt": "not-a-date",
          "claims": [
            {
              "id": "8EED90D8-87E6-4F1F-B978-7CE78F8D9071",
              "title": "Malformed dates",
              "category": "returnItem",
              "valueAtRisk": 42,
              "status": "active",
              "deadline": "not-a-date",
              "reminderDate": "also-not-a-date",
              "createdAt": "bad-created-date",
              "updatedAt": "bad-updated-date",
              "completedAt": "bad-completed-date",
              "proofItems": [
                {
                  "id": "B88F61E2-14C8-45EC-A8CE-954570E4B7B8",
                  "type": "note",
                  "displayName": "Imported note",
                  "createdAt": "bad-proof-date",
                  "intelligence": {
                    "merchant": "Store",
                    "category": "unknown",
                    "valueAtRisk": "not-money",
                    "purchaseDate": "bad-purchase-date",
                    "deadline": "bad-intelligence-deadline",
                    "deadlineIsExplicit": true,
                    "orderNumber": "ORD-1",
                    "barcodeValues": "not-an-array",
                    "confidence": "not-confidence",
                    "warnings": "not-an-array",
                    "summary": "   ",
                    "completeness": {
                      "score": "bad-score",
                      "hasMerchant": "yes",
                      "hasValue": "yes",
                      "hasPurchaseDate": "no",
                      "hasDeadline": "no",
                      "hasReadableText": "yes",
                      "missingFields": "not-an-array"
                    }
                  }
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
        let importedProof = try XCTUnwrap(imported.proofItemsList.first)

        XCTAssertNil(imported.deadline)
        XCTAssertNil(imported.reminderDate)
        XCTAssertNil(imported.completedAt)
        XCTAssertTrue(imported.createdAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertTrue(imported.updatedAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertTrue(importedProof.createdAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertEqual(importedProof.intelligence?.merchant, "Store")
        XCTAssertNil(importedProof.intelligence?.category)
        XCTAssertNil(importedProof.intelligence?.valueAtRisk)
        XCTAssertNil(importedProof.intelligence?.purchaseDate)
        XCTAssertNil(importedProof.intelligence?.deadline)
        XCTAssertFalse(importedProof.intelligence?.deadlineIsExplicit ?? true)
        XCTAssertEqual(importedProof.intelligence?.summary, "Proof needs review.")
    }

    func testImportNormalizesCompletionAndReminderState() throws {
        let json = """
        {
          "claims": [
            {
              "id": "8EED90D8-87E6-4F1F-B978-7CE78F8D9071",
              "title": "Open claim with stale completion",
              "category": "giftCard",
              "valueAtRisk": 25,
              "status": "active",
              "recoveredValue": 25,
              "completedAt": "2026-05-21T12:00:00Z",
              "reminderDate": "2020-05-21T12:00:00Z"
            },
            {
              "id": "4924EDCB-1B01-44CC-9477-D00CD7D3804D",
              "title": "Recovered claim missing value",
              "category": "rebate",
              "valueAtRisk": 80,
              "status": "recovered",
              "recoveredValue": 0,
              "updatedAt": "2026-05-22T12:00:00Z"
            },
            {
              "id": "F451D63E-8065-4F36-BE59-3D161B596994",
              "title": "Used claim with stale recovery",
              "category": "warranty",
              "valueAtRisk": 120,
              "status": "used",
              "recoveredValue": 120,
              "reminderDate": "2099-05-21T12:00:00Z",
              "updatedAt": "2026-05-23T12:00:00Z"
            },
            {
              "id": "5D1FD83D-C069-40DF-BA5E-DDB8B66574D5",
              "title": "Open claim with reminder after deadline",
              "category": "returnItem",
              "valueAtRisk": 55,
              "status": "active",
              "deadline": "2099-05-21T12:00:00Z",
              "reminderDate": "2099-05-22T12:00:00Z"
            }
          ]
        }
        """

        let url = try writeTemporaryJSON(json)
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertEqual(try ImportExportService.shared.importClaims(from: url, into: context), 4)
        let imported = try context.fetch(FetchDescriptor<Claim>())
        let open = try XCTUnwrap(imported.first { $0.title == "Open claim with stale completion" })
        let recovered = try XCTUnwrap(imported.first { $0.title == "Recovered claim missing value" })
        let used = try XCTUnwrap(imported.first { $0.title == "Used claim with stale recovery" })
        let reminderAfterDeadline = try XCTUnwrap(imported.first { $0.title == "Open claim with reminder after deadline" })

        XCTAssertEqual(open.recoveredValue, 0)
        XCTAssertNil(open.completedAt)
        XCTAssertNil(open.reminderDate)
        XCTAssertEqual(recovered.recoveredValue, 80)
        XCTAssertNotNil(recovered.completedAt)
        XCTAssertEqual(used.recoveredValue, 0)
        XCTAssertNotNil(used.completedAt)
        XCTAssertNil(used.reminderDate)
        XCTAssertNil(reminderAfterDeadline.reminderDate)
    }

    func testMalformedJSONThrowsWithoutCreatingRecords() throws {
        let url = try writeTemporaryJSON("{ not valid json")
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertThrowsError(try ImportExportService.shared.importClaims(from: url, into: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Claim>()).count, 0)
    }

    func testImportNormalizesActionLinksAndDropsUnsafeSchemes() throws {
        let json = """
        {
          "claims": [
            {
              "id": "4924EDCB-1B01-44CC-9477-D00CD7D3804D",
              "title": "Safe support link",
              "category": "returnItem",
              "valueAtRisk": 48,
              "status": "active",
              "actionURLString": "support.example/returns"
            },
            {
              "id": "F451D63E-8065-4F36-BE59-3D161B596994",
              "title": "Unsafe support link",
              "category": "returnItem",
              "valueAtRisk": 49,
              "status": "active",
              "actionURLString": "javascript:alert(1)"
            },
            {
              "id": "5D1FD83D-C069-40DF-BA5E-DDB8B66574D5",
              "title": "Malformed explicit scheme",
              "category": "returnItem",
              "valueAtRisk": 50,
              "status": "active",
              "actionURLString": "http:example.com"
            }
          ]
        }
        """

        let url = try writeTemporaryJSON(json)
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertEqual(try ImportExportService.shared.importClaims(from: url, into: context), 3)
        let imported = try context.fetch(FetchDescriptor<Claim>())
        let safe = try XCTUnwrap(imported.first { $0.title == "Safe support link" })
        let unsafe = try XCTUnwrap(imported.first { $0.title == "Unsafe support link" })
        let malformed = try XCTUnwrap(imported.first { $0.title == "Malformed explicit scheme" })
        XCTAssertEqual(safe.actionURLString, "https://support.example/returns")
        XCTAssertNil(unsafe.actionURLString)
        XCTAssertNil(malformed.actionURLString)
    }

    func testFailedBinaryProofImportCleansUpRestoredFiles() throws {
        let proofFileNamesBeforeImport = try proofFileNames()
        let documentData = Data("Restored document".utf8).base64EncodedString()
        let invalidImageData = Data("Not an image".utf8).base64EncodedString()
        let json = """
        {
          "claims": [
            {
              "id": "4924EDCB-1B01-44CC-9477-D00CD7D3804D",
              "title": "Partially bad proof import",
              "category": "returnItem",
              "valueAtRisk": 48,
              "status": "active",
              "proofItems": [
                {
                  "id": "6A0DB98F-53DE-4505-A13A-A5B1C2756F9D",
                  "type": "document",
                  "localFileName": "receipt.pdf",
                  "displayName": "Receipt",
                  "createdAt": "2026-05-21T12:00:00Z",
                  "binaryProofData": "\(documentData)"
                },
                {
                  "id": "D9207719-F227-4C2C-8FAD-EAE1E673A122",
                  "type": "photo",
                  "localFileName": "bad-photo.jpg",
                  "displayName": "Bad Photo",
                  "createdAt": "2026-05-21T12:00:00Z",
                  "binaryProofData": "\(invalidImageData)"
                }
              ]
            }
          ]
        }
        """

        let url = try writeTemporaryJSON(json)
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertThrowsError(try ImportExportService.shared.importClaims(from: url, into: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Claim>()).count, 0)
        XCTAssertEqual(try proofFileNames(), proofFileNamesBeforeImport)
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
        XCTAssertTrue(imported.proofItemsList.isEmpty)
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
        claim.proofItemsList.append(proof)

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ClaimExportBundle.self, from: Data(contentsOf: exportURL))
        XCTAssertTrue(bundle.includesBinaryProofData)
        XCTAssertEqual(bundle.claims.first?.policySummary, "")
        XCTAssertNotNil(bundle.claims.first?.proofItems.first?.binaryProofData)
        XCTAssertEqual(bundle.claims.first?.proofItems.first?.extractedText, "Nike total 50 return by June 20")
        XCTAssertEqual(bundle.claims.first?.proofItems.first?.intelligence?.orderNumber, "NKE-5000")

        let container = try makeContainer()
        let context = container.mainContext
        XCTAssertEqual(try ImportExportService.shared.importClaims(from: exportURL, into: context), 1)

        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Claim>()).first)
        let importedProof = try XCTUnwrap(imported.proofItemsList.first)
        XCTAssertEqual(importedProof.extractedText, "Nike total 50 return by June 20")
        XCTAssertEqual(importedProof.intelligence?.summary, "Nike return proof is ready.")
        XCTAssertTrue(FileStorageService.shared.fileExists(named: importedProof.localFileName))
        FileStorageService.shared.deleteFile(named: importedProof.localFileName)
    }

    func testCompleteExportDropsUnsafeSavedActionLinks() throws {
        let claim = Claim(
            title: "Unsafe export link",
            category: .returnItem,
            valueAtRisk: 12,
            actionURLString: "javascript:alert(1)"
        )

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ClaimExportBundle.self, from: Data(contentsOf: exportURL))

        XCTAssertNil(bundle.claims.first?.actionURLString)
    }

    func testCompleteExportSanitizesCorruptMoneyValues() throws {
        let claim = Claim(
            title: "Corrupt money",
            category: .returnItem,
            valueAtRisk: .infinity,
            status: .recovered,
            recoveredValue: .nan
        )

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ClaimExportBundle.self, from: Data(contentsOf: exportURL))
        let exportedClaim = try XCTUnwrap(bundle.claims.first)

        XCTAssertEqual(exportedClaim.valueAtRisk, 0)
        XCTAssertEqual(exportedClaim.recoveredValue, 0)
    }

    func testCompleteExportSanitizesCorruptStoredClaimAndProofFields() throws {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let claim = Claim(title: "Baseline", category: .document, valueAtRisk: 25)
        claim.title = "   "
        claim.merchant = "   "
        claim.valueAtRisk = .infinity
        claim.deadline = invalidDate
        claim.reminderDate = invalidDate
        claim.referenceNumber = String(repeating: "R", count: ClaimTextLimits.reference + 50)
        claim.policySummary = String(repeating: "P", count: ClaimTextLimits.policySummary + 50)
        claim.actionURLString = "javascript:alert(1)"
        claim.notes = String(repeating: "N", count: ClaimTextLimits.notes + 50)
        claim.status = .overdue
        claim.createdAt = invalidDate
        claim.updatedAt = invalidDate
        claim.recoveredValue = .nan
        claim.completedAt = invalidDate

        let proof = ProofItem(type: .note, displayName: "Proof note", claim: claim)
        proof.localFileName = "../secret.pdf"
        proof.displayName = "   "
        proof.extractedText = String(repeating: "E", count: ProofItemTextLimits.extractedText + 50)
        proof.createdAt = invalidDate
        proof.intelligence = ProofIntelligence(
            merchant: String(repeating: "M", count: ClaimTextLimits.merchant + 50),
            category: .document,
            valueAtRisk: .infinity,
            purchaseDate: nil,
            deadline: nil,
            deadlineIsExplicit: true,
            orderNumber: String(repeating: "O", count: ClaimTextLimits.reference + 50),
            confidence: -1,
            warnings: [String(repeating: "W", count: 300)],
            summary: "   ",
            completeness: ProofCompleteness(
                score: .infinity,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: false,
                hasDeadline: false,
                hasReadableText: true,
                missingFields: [String(repeating: "F", count: 200)]
            )
        )
        claim.proofItemsList = [proof]

        let exportURL = try ImportExportService.shared.exportClaims([claim])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportedClaim = try XCTUnwrap(
            try decoder.decode(ClaimExportBundle.self, from: Data(contentsOf: exportURL)).claims.first
        )
        let exportedProof = try XCTUnwrap(exportedClaim.proofItems.first)

        XCTAssertEqual(exportedClaim.title, "Untitled claim")
        XCTAssertNil(exportedClaim.merchant)
        XCTAssertEqual(exportedClaim.valueAtRisk, 0)
        XCTAssertNil(exportedClaim.deadline)
        XCTAssertNil(exportedClaim.reminderDate)
        XCTAssertEqual(exportedClaim.referenceNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(exportedClaim.policySummary.count, ClaimTextLimits.policySummary)
        XCTAssertNil(exportedClaim.actionURLString)
        XCTAssertEqual(exportedClaim.notes.count, ClaimTextLimits.notes)
        XCTAssertEqual(exportedClaim.status, .active)
        XCTAssertTrue(exportedClaim.createdAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertTrue(exportedClaim.updatedAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertEqual(exportedClaim.recoveredValue, 0)
        XCTAssertNil(exportedClaim.completedAt)
        XCTAssertNil(exportedProof.localFileName)
        XCTAssertEqual(exportedProof.displayName, ProofItemType.note.displayName)
        XCTAssertEqual(exportedProof.extractedText?.count, ProofItemTextLimits.extractedText)
        XCTAssertTrue(exportedProof.createdAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertNil(exportedProof.binaryProofData)
        XCTAssertEqual(exportedProof.intelligence?.merchant?.count, ClaimTextLimits.merchant)
        XCTAssertNil(exportedProof.intelligence?.valueAtRisk)
        XCTAssertEqual(exportedProof.intelligence?.deadlineIsExplicit, false)
        XCTAssertEqual(exportedProof.intelligence?.orderNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(exportedProof.intelligence?.confidence, 0)
        XCTAssertEqual(exportedProof.intelligence?.summary, "Proof needs review.")
        XCTAssertEqual(exportedProof.intelligence?.completeness.hasValue, false)
    }

    func testSharedImportQueueCleansOnlyStaleOrphanDirectories() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let store = SharedImportQueueStore(containerURL: containerURL)
        let staleID = UUID()
        let staleFileName = try store.writeFile(
            data: Data("stale shared proof".utf8),
            originalFileName: "receipt.jpg",
            requestID: staleID
        )

        let freshID = UUID()
        _ = try store.writeFile(
            data: Data("fresh shared proof".utf8),
            originalFileName: "receipt.jpg",
            requestID: freshID
        )

        let validID = UUID()
        let validFileName = try store.writeFile(
            data: Data("valid shared proof".utf8),
            originalFileName: "receipt.pdf",
            requestID: validID
        )
        let validRequest = SharedImportRequest(
            id: validID,
            createdAt: Date(timeIntervalSince1970: 20),
            suggestedTitle: "Shared receipt",
            items: [
                SharedImportItem(
                    kind: .document,
                    originalFileName: "receipt.pdf",
                    storedFileName: validFileName
                )
            ]
        )
        try store.save(validRequest)

        let oldDate = Date(timeIntervalSince1970: 10)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: sharedQueueDirectory(in: containerURL, id: staleID).path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: sharedQueueDirectory(in: containerURL, id: validID).path
        )

        XCTAssertEqual(store.cleanupOrphanedRequests(olderThan: Date(timeIntervalSince1970: 15)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedQueueDirectory(in: containerURL, id: staleID).path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sharedQueueDirectory(in: containerURL, id: staleID)
                    .appendingPathComponent(staleFileName)
                    .path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedQueueDirectory(in: containerURL, id: freshID).path))
        XCTAssertEqual(store.loadPendingRequests().map(\.id), [validID])
    }

    func testSharedImportQueueRejectsOversizedBinaryItems() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let store = SharedImportQueueStore(containerURL: containerURL)
        let oversizedData = Data(repeating: 0x41, count: SharedImportQueueStore.maximumSharedItemBytes + 1)

        XCTAssertThrowsError(
            try store.writeFile(data: oversizedData, originalFileName: "oversized.pdf", requestID: UUID())
        ) { error in
            XCTAssertEqual(error as? DueProofSharedStorageError, .sharedItemTooLarge)
        }
    }

    func testSharedImportQueueRejectsOversizedFileRepresentations() throws {
        let containerURL = try makeTemporaryDirectory()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer {
            try? FileManager.default.removeItem(at: containerURL)
            try? FileManager.default.removeItem(at: sourceURL)
        }

        try Data(repeating: 0x41, count: SharedImportQueueStore.maximumSharedItemBytes + 1)
            .write(to: sourceURL, options: [.atomic])

        let store = SharedImportQueueStore(containerURL: containerURL)
        XCTAssertThrowsError(
            try store.writeFile(from: sourceURL, originalFileName: "oversized.pdf", requestID: UUID())
        ) { error in
            XCTAssertEqual(error as? DueProofSharedStorageError, .sharedItemTooLarge)
        }
    }

    func testSharedImportQueueRejectsOversizedRequestManifests() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let store = SharedImportQueueStore(containerURL: containerURL)
        let requestID = UUID()
        _ = try store.writeFile(
            data: Data("valid shared proof".utf8),
            originalFileName: "receipt.pdf",
            requestID: requestID
        )

        let requestURL = sharedQueueDirectory(in: containerURL, id: requestID)
            .appendingPathComponent("request.json")
        try Data(repeating: 0x41, count: SharedImportQueueStore.maximumRequestBytes + 1).write(to: requestURL, options: [.atomic])

        XCTAssertNil(store.load(id: requestID))
        XCTAssertEqual(store.cleanupOrphanedRequests(olderThan: Date.distantFuture), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedQueueDirectory(in: containerURL, id: requestID).path))
    }

    func testSharedImportQueueRejectsOversizedRequestBeforeHandoff() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let store = SharedImportQueueStore(containerURL: containerURL)
        let requestID = UUID()
        let request = SharedImportRequest(
            id: requestID,
            suggestedTitle: String(repeating: "A", count: SharedImportQueueStore.maximumRequestBytes + 1),
            items: [
                SharedImportItem(kind: .text, text: "Proof")
            ]
        )

        XCTAssertThrowsError(try store.save(request)) { error in
            XCTAssertEqual(error as? DueProofSharedStorageError, .sharedItemTooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedQueueDirectory(in: containerURL, id: requestID).path))
    }

    func testSharedImportQueueRejectsEmptyAndMismatchedRequests() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let store = SharedImportQueueStore(containerURL: containerURL)
        let emptyID = UUID()
        let emptyRequest = SharedImportRequest(
            id: emptyID,
            suggestedTitle: "Empty",
            items: []
        )
        _ = try store.writeFile(
            data: Data("orphaned proof".utf8),
            originalFileName: "orphan.pdf",
            requestID: emptyID
        )

        XCTAssertThrowsError(try store.save(emptyRequest)) { error in
            XCTAssertEqual(error as? DueProofSharedStorageError, .emptyImportRequest)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedQueueDirectory(in: containerURL, id: emptyID).path))

        let directoryID = UUID()
        let mismatchedID = UUID()
        let fileName = try store.writeFile(
            data: Data("queued proof".utf8),
            originalFileName: "receipt.pdf",
            requestID: directoryID
        )
        let mismatchedRequest = SharedImportRequest(
            id: mismatchedID,
            suggestedTitle: "Mismatched",
            items: [
                SharedImportItem(kind: .document, originalFileName: "receipt.pdf", storedFileName: fileName)
            ]
        )
        let requestURL = sharedQueueDirectory(in: containerURL, id: directoryID)
            .appendingPathComponent("request.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(mismatchedRequest).write(to: requestURL, options: [.atomic])

        XCTAssertNil(store.load(id: directoryID))
        XCTAssertTrue(store.loadPendingRequests().isEmpty)
        XCTAssertEqual(store.cleanupOrphanedRequests(olderThan: Date.distantFuture), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedQueueDirectory(in: containerURL, id: directoryID).path))
    }

    func testSharedImportNotesNormalizeURLsOnceAndStayBounded() {
        let request = SharedImportRequest(
            sourceApplication: "Safari",
            suggestedTitle: "Shared support link",
            items: [
                SharedImportItem(
                    kind: .url,
                    text: "support.example/returns",
                    urlString: "support.example/returns"
                ),
                SharedImportItem(
                    kind: .url,
                    text: "javascript:alert(1)",
                    urlString: "javascript:alert(1)"
                ),
                SharedImportItem(
                    kind: .text,
                    text: String(repeating: "A", count: ClaimTextLimits.notes + 500)
                )
            ]
        )

        let notes = SharedImportService.notes(for: request)

        XCTAssertLessThanOrEqual(notes.count, ClaimTextLimits.notes)
        XCTAssertTrue(notes.contains("Shared from Safari."))
        XCTAssertTrue(notes.contains("https://support.example/returns"))
        XCTAssertEqual(notes.components(separatedBy: "https://support.example/returns").count - 1, 1)
        XCTAssertFalse(notes.localizedCaseInsensitiveContains("javascript:"))
    }

    func testSharedImportTitleNormalizesExternalMetadata() {
        let titleFromSuggestedName = SharedImportService.normalizedTitle(
            for: SharedImportRequest(
                suggestedTitle: "/private/tmp/\(String(repeating: "R", count: ClaimTextLimits.title + 40)).pdf",
                items: [
                    SharedImportItem(kind: .text, text: "Fallback")
                ]
            )
        )

        XCTAssertLessThanOrEqual(titleFromSuggestedName.count, ClaimTextLimits.title)
        XCTAssertFalse(titleFromSuggestedName.contains("/"))

        let titleFromFile = SharedImportService.normalizedTitle(
            for: SharedImportRequest(
                suggestedTitle: "   ",
                items: [
                    SharedImportItem(
                        kind: .document,
                        originalFileName: "../Receipt Final.pdf",
                        storedFileName: "queued.pdf"
                    )
                ]
            )
        )

        XCTAssertEqual(titleFromFile, "Receipt Final")

        let titleFromText = SharedImportService.normalizedTitle(
            for: SharedImportRequest(
                suggestedTitle: "   ",
                items: [
                    SharedImportItem(kind: .text, text: "  \(String(repeating: "A", count: 120))  ")
                ]
            )
        )

        XCTAssertEqual(titleFromText.count, 80)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Claim.self, ProofItem.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeTemporaryJSON(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try Data(json.utf8).write(to: url, options: [.atomic])
        return url
    }

    private func sharedQueueDirectory(in containerURL: URL, id: UUID) -> URL {
        containerURL
            .appendingPathComponent("QueuedImports", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func proofFileNames() throws -> Set<String> {
        let directory = try FileStorageService.shared.proofsDirectory()
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return Set(contents.map(\.lastPathComponent))
    }
}
