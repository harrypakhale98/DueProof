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
}
