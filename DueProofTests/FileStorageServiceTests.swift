import UIKit
import XCTest
@testable import DueProof

final class FileStorageServiceTests: XCTestCase {
    func testProofImageSaveLoadAndDeleteUsesLocalFileReference() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let data = try XCTUnwrap(image.pngData())

        let fileName = try FileStorageService.shared.saveImageData(data, preferredName: "Proof")
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.localizedCaseInsensitiveContains("Proof"))
        XCTAssertTrue(fileName.hasSuffix(".jpg"))

        let url = try XCTUnwrap(FileStorageService.shared.url(for: fileName))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(FileStorageService.shared.image(for: fileName))
        XCTAssertNotNil(FileStorageService.shared.thumbnail(for: fileName))

        XCTAssertTrue(FileStorageService.shared.deleteFile(named: fileName))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testProofImageSaveDownsamplesLargeImages() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3_200, height: 1_600)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_200, height: 1_600))
        }
        let data = try XCTUnwrap(image.pngData())

        let fileName = try FileStorageService.shared.saveImageData(data, preferredName: "Large Proof")
        defer { FileStorageService.shared.deleteFile(named: fileName) }

        let savedImage = try XCTUnwrap(FileStorageService.shared.image(for: fileName))
        XCTAssertLessThanOrEqual(max(savedImage.size.width, savedImage.size.height), 2_400)
    }

    func testRejectsUnsafeLocalFileNames() {
        XCTAssertNil(FileStorageService.shared.url(for: "../outside.jpg"))
        XCTAssertNil(FileStorageService.shared.url(for: "/tmp/outside.jpg"))
        XCTAssertFalse(FileStorageService.shared.fileExists(named: "../outside.jpg"))
        XCTAssertFalse(FileStorageService.shared.deleteFile(named: "../outside.jpg"))
    }

    func testDocumentProofSaveLoadAndDeleteUsesProtectedLocalFile() throws {
        let data = Data("PDF placeholder".utf8)
        let fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: "receipt.pdf")

        XCTAssertFalse(fileName.contains("/"))
        XCTAssertTrue(fileName.hasSuffix(".pdf"))

        let url = try XCTUnwrap(FileStorageService.shared.url(for: fileName))
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertTrue(FileStorageService.shared.deleteFile(named: fileName))
    }

    func testDocumentProofRejectsUnexpectedImportedExtensions() throws {
        let data = Data("Untrusted placeholder".utf8)
        let fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: "receipt.exe")

        XCTAssertTrue(fileName.hasSuffix(".pdf"))
        XCTAssertFalse(fileName.hasSuffix(".exe"))
        XCTAssertTrue(FileStorageService.shared.deleteFile(named: fileName))
    }

    func testImportedProofDataRejectsOversizedFilesBeforeSave() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let oversizedData = Data(repeating: 0x41, count: FileStorageService.maximumProofFileBytes + 1)
        try oversizedData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try FileStorageService.shared.dataForImportedProof(at: url)) { error in
            XCTAssertEqual(error as? FileStorageError, .proofFileTooLarge)
        }
        XCTAssertThrowsError(try FileStorageService.shared.saveDocumentData(oversizedData, originalFileName: "oversized.pdf")) { error in
            XCTAssertEqual(error as? FileStorageError, .proofFileTooLarge)
        }
    }

    func testSyncedProofDataRestoresMissingLocalFile() throws {
        let data = Data("Cloud mirrored proof".utf8)
        let fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: "warranty.pdf")
        let proof = ProofItem(
            type: .document,
            localFileName: fileName,
            syncedFileData: data,
            displayName: "Warranty"
        )

        XCTAssertTrue(FileStorageService.shared.deleteFile(named: fileName))
        XCTAssertFalse(FileStorageService.shared.fileExists(named: fileName))

        XCTAssertEqual(FileStorageService.shared.data(for: proof), data)
        XCTAssertTrue(FileStorageService.shared.fileExists(named: fileName))

        XCTAssertTrue(FileStorageService.shared.deleteFile(named: fileName))
    }

    func testReadingLocalProofDataDoesNotImplicitlyBackfillSyncPayload() throws {
        let data = Data("Local only proof".utf8)
        let fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: "local.pdf")
        defer { FileStorageService.shared.deleteFile(named: fileName) }
        let proof = ProofItem(
            type: .document,
            localFileName: fileName,
            displayName: "Local Only"
        )

        XCTAssertNil(proof.syncedFileData)
        XCTAssertEqual(FileStorageService.shared.data(for: proof), data)
        XCTAssertNil(proof.syncedFileData)
    }

    func testExplicitSyncBackfillCopiesLocalProofData() throws {
        let data = Data("Backfill proof".utf8)
        let fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: "sync.pdf")
        defer { FileStorageService.shared.deleteFile(named: fileName) }
        let proof = ProofItem(
            type: .document,
            localFileName: fileName,
            displayName: "Sync"
        )

        XCTAssertEqual(FileStorageService.shared.backfillSyncedFileData(for: [proof]), 1)
        XCTAssertEqual(proof.syncedFileData, data)
    }

    func testOversizedSyncedProofDataDoesNotRestoreLocalFile() {
        let fileName = "\(UUID().uuidString).pdf"
        let proof = ProofItem(
            type: .document,
            localFileName: fileName,
            syncedFileData: Data(repeating: 0x41, count: FileStorageService.maximumProofFileBytes + 1),
            displayName: "Oversized Cloud Proof"
        )

        XCTAssertNil(FileStorageService.shared.data(for: proof))
        XCTAssertFalse(FileStorageService.shared.fileExists(named: fileName))
    }

    func testOversizedLocalProofDataDoesNotLoadForExportOrBackfill() throws {
        let fileName = "\(UUID().uuidString).pdf"
        let url = try FileStorageService.shared.proofsDirectory().appendingPathComponent(fileName)
        try Data(repeating: 0x41, count: FileStorageService.maximumProofFileBytes + 1)
            .write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(FileStorageService.shared.data(for: fileName))
    }

    func testImageDisplayPathRejectsOversizedAndInvalidPixelLoads() throws {
        let oversizedFileName = "\(UUID().uuidString).jpg"
        let oversizedURL = try FileStorageService.shared.proofsDirectory().appendingPathComponent(oversizedFileName)
        try Data(repeating: 0x41, count: FileStorageService.maximumProofFileBytes + 1)
            .write(to: oversizedURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: oversizedURL) }

        XCTAssertNil(FileStorageService.shared.image(for: oversizedFileName))
        XCTAssertNil(FileStorageService.shared.thumbnail(for: oversizedFileName))

        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let fileName = try FileStorageService.shared.saveImageData(try XCTUnwrap(image.pngData()))
        defer { FileStorageService.shared.deleteFile(named: fileName) }

        XCTAssertNil(FileStorageService.shared.thumbnail(for: fileName, maxPixelSize: .infinity))
        XCTAssertNil(FileStorageService.shared.thumbnail(for: fileName, maxPixelSize: 0))
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(FileStorageService.shared.thumbnail(for: fileName, maxPixelSize: 10_000)).size.width,
            FileStorageService.maximumDisplayImagePixelSize
        )
    }

    func testStagedProofFileDeletionCanRollbackOrCommit() throws {
        let data = Data("Rollback proof".utf8)
        let fileName = try FileStorageService.shared.saveDocumentData(data, originalFileName: "rollback.pdf")

        let rollbackDeletion = try XCTUnwrap(FileStorageService.shared.stageFileDeletion(named: fileName))
        XCTAssertFalse(FileStorageService.shared.fileExists(named: fileName))

        try FileStorageService.shared.rollbackStagedDeletion(rollbackDeletion)
        XCTAssertTrue(FileStorageService.shared.fileExists(named: fileName))
        XCTAssertEqual(FileStorageService.shared.data(for: fileName), data)

        let commitDeletion = try XCTUnwrap(FileStorageService.shared.stageFileDeletion(named: fileName))
        FileStorageService.shared.commitStagedDeletion(commitDeletion)
        XCTAssertFalse(FileStorageService.shared.fileExists(named: fileName))
    }

    func testStagedProofDirectoryClearCanRollbackAfterEmptyDirectoryRecreated() throws {
        let firstFileName = try FileStorageService.shared.saveDocumentData(Data("First".utf8), originalFileName: "first.pdf")
        let secondFileName = try FileStorageService.shared.saveDocumentData(Data("Second".utf8), originalFileName: "second.pdf")

        let pendingDeletion = try XCTUnwrap(FileStorageService.shared.stageProofFilesClear())
        _ = try FileStorageService.shared.proofsDirectory()

        try FileStorageService.shared.rollbackStagedDeletion(pendingDeletion)
        XCTAssertEqual(FileStorageService.shared.data(for: firstFileName), Data("First".utf8))
        XCTAssertEqual(FileStorageService.shared.data(for: secondFileName), Data("Second".utf8))

        let commitDeletion = try XCTUnwrap(FileStorageService.shared.stageProofFilesClear())
        FileStorageService.shared.commitStagedDeletion(commitDeletion)
        XCTAssertFalse(FileStorageService.shared.fileExists(named: firstFileName))
        XCTAssertFalse(FileStorageService.shared.fileExists(named: secondFileName))
    }

    func testTemporaryExportFileNamesAreBoundedAndProtected() throws {
        let longTitle = String(repeating: "Very Long Claim Title ", count: 20) + ".json"
        let url = try FileStorageService.shared.protectedTemporaryURL(
            fileName: longTitle,
            data: Data("{}".utf8)
        )
        let secondURL = try FileStorageService.shared.protectedTemporaryURL(
            fileName: longTitle,
            data: Data("{\"second\":true}".utf8)
        )

        XCTAssertLessThanOrEqual(url.lastPathComponent.count, 120)
        XCTAssertLessThanOrEqual(secondURL.lastPathComponent.count, 120)
        XCTAssertNotEqual(url, secondURL)
        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("DueProof-Export-"))
        XCTAssertEqual(try Data(contentsOf: url), Data("{}".utf8))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("{\"second\":true}".utf8))
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: secondURL)
    }

    func testTemporaryExportCleanupRemovesGeneratedPrivateArtifacts() throws {
        let exportURL = try FileStorageService.shared.protectedTemporaryURL(
            fileName: "private-claims.json",
            data: Data("{\"claims\":[]}".utf8)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        FileStorageService.shared.cleanupTemporaryExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    }

    func testTemporaryExportDeletionOnlyRemovesGeneratedExportArtifacts() throws {
        let exportURL = try FileStorageService.shared.protectedTemporaryURL(
            fileName: "private-claims.json",
            data: Data("{\"claims\":[]}".utf8)
        )
        let unrelatedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unrelated-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: unrelatedURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: unrelatedURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))

        FileStorageService.shared.deleteTemporaryExport(at: unrelatedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))

        FileStorageService.shared.deleteTemporaryExport(at: exportURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }
}
