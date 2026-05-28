import Foundation
import ImageIO
import UIKit

enum FileStorageError: LocalizedError, Equatable {
    case unableToCreateDirectory
    case unableToReadImage
    case unableToDeleteFile
    case unableToProtectFile
    case unableToRestoreFile
    case unableToWriteImage
    case proofFileTooLarge

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            "DueProof could not create the local proof storage folder."
        case .unableToReadImage:
            "DueProof could not prepare that proof photo for private local storage."
        case .unableToDeleteFile:
            "DueProof could not remove that local proof file."
        case .unableToProtectFile:
            "DueProof could not apply local file protection to that proof."
        case .unableToRestoreFile:
            "DueProof could not restore a local proof file."
        case .unableToWriteImage:
            "DueProof could not save that proof photo locally."
        case .proofFileTooLarge:
            "That proof file is too large to import safely."
        }
    }
}

final class FileStorageService {
    static let shared = FileStorageService()
    static let maximumProofFileBytes = 25_000_000
    static let maximumDisplayImagePixelSize: CGFloat = 2_400

    private let folderName = "ProofItems"
    private let deletionStagingPrefix = "DueProof-Delete-"

    private init() {}

    struct PendingDeletion {
        fileprivate let originalURL: URL
        fileprivate let stagedURL: URL
        fileprivate let stagingDirectory: URL
    }

    func proofsDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw FileStorageError.unableToCreateDirectory
            }
        }

        try protectFile(at: directory)
        return directory
    }

    func saveImageData(_ data: Data, preferredName: String? = nil) throws -> String {
        guard data.count <= Self.maximumProofFileBytes else {
            throw FileStorageError.proofFileTooLarge
        }

        guard let imageData = normalizedJPEGData(from: data) else {
            throw FileStorageError.unableToReadImage
        }

        let fileName = "\(UUID().uuidString).jpg"
        let url = try proofsDirectory().appendingPathComponent(fileName)
        do {
            try imageData.write(to: url, options: [.atomic])
            try protectFile(at: url)
            return fileName
        } catch {
            throw FileStorageError.unableToWriteImage
        }
    }

    func saveDocumentData(_ data: Data, originalFileName: String? = nil) throws -> String {
        guard data.count <= Self.maximumProofFileBytes else {
            throw FileStorageError.proofFileTooLarge
        }

        let fileExtension = safeDocumentFileExtension(from: originalFileName) ?? "pdf"
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let url = try proofsDirectory().appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: [.atomic])
            try protectFile(at: url)
            return fileName
        } catch {
            throw FileStorageError.unableToWriteImage
        }
    }

    func url(for localFileName: String) -> URL? {
        guard let localFileName = validatedLocalFileName(localFileName) else { return nil }
        guard let directory = try? proofsDirectory() else { return nil }
        return directory.appendingPathComponent(localFileName)
    }

    func url(for proof: ProofItem) -> URL? {
        guard let localFileName = proof.localFileName else { return nil }
        _ = restoreSyncedFileIfNeeded(for: proof)
        return url(for: localFileName)
    }

    func fileExists(named localFileName: String?) -> Bool {
        guard let localFileName, let url = url(for: localFileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func dataForImportedProof(at url: URL) throws -> Data {
        try DueProofBoundedFileReader.data(
            at: url,
            maximumBytes: Self.maximumProofFileBytes,
            tooLargeError: FileStorageError.proofFileTooLarge
        )
    }

    func fileExists(for proof: ProofItem) -> Bool {
        guard let localFileName = proof.localFileName else { return false }
        return fileExists(named: localFileName) || restoreSyncedFileIfNeeded(for: proof)
    }

    func data(for localFileName: String?) -> Data? {
        guard let localFileName, let url = url(for: localFileName) else { return nil }
        return try? DueProofBoundedFileReader.data(
            at: url,
            maximumBytes: Self.maximumProofFileBytes,
            tooLargeError: FileStorageError.proofFileTooLarge
        )
    }

    func data(for proof: ProofItem) -> Data? {
        if let localData = data(for: proof.localFileName) {
            return localData
        }

        guard let syncedFileData = proof.syncedFileData,
              syncedFileData.count <= Self.maximumProofFileBytes
        else {
            return nil
        }
        _ = restoreSyncedFileIfNeeded(for: proof)
        return syncedFileData
    }

    func image(for localFileName: String) -> UIImage? {
        thumbnail(for: localFileName, maxPixelSize: Self.maximumDisplayImagePixelSize)
    }

    func image(for proof: ProofItem) -> UIImage? {
        guard let localFileName = proof.localFileName else { return nil }
        _ = restoreSyncedFileIfNeeded(for: proof)
        return image(for: localFileName)
    }

    func thumbnail(for localFileName: String, maxPixelSize: CGFloat = 360) -> UIImage? {
        guard let url = url(for: localFileName),
              let pixelSize = normalizedImagePixelSize(maxPixelSize),
              isProofFileWithinReadLimit(at: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: thumbnail)
    }

    func thumbnail(for proof: ProofItem, maxPixelSize: CGFloat = 360) -> UIImage? {
        guard let localFileName = proof.localFileName else { return nil }
        _ = restoreSyncedFileIfNeeded(for: proof)
        return thumbnail(for: localFileName, maxPixelSize: maxPixelSize)
    }

    @discardableResult
    func restoreSyncedFileIfNeeded(for proof: ProofItem) -> Bool {
        guard let localFileName = proof.localFileName else { return false }
        if fileExists(named: localFileName) { return true }
        guard let syncedFileData = proof.syncedFileData,
              syncedFileData.count <= Self.maximumProofFileBytes,
              let url = url(for: localFileName)
        else {
            return false
        }

        do {
            try syncedFileData.write(to: url, options: [.atomic])
            try protectFile(at: url)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func backfillSyncedFileData(for proofs: [ProofItem]) -> Int {
        var updatedCount = 0
        for proof in proofs where proof.syncedFileData == nil {
            guard let data = data(for: proof.localFileName) else { continue }
            proof.syncedFileData = data
            updatedCount += 1
        }
        return updatedCount
    }

    @discardableResult
    func deleteFile(named localFileName: String?) -> Bool {
        guard let localFileName, let url = url(for: localFileName) else { return false }

        guard FileManager.default.fileExists(atPath: url.path) else { return true }

        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    func stageFileDeletion(named localFileName: String?) throws -> PendingDeletion? {
        guard let localFileName, let url = url(for: localFileName) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return try stageDeletion(at: url)
    }

    func stageFileDeletions(named localFileNames: [String]) throws -> [PendingDeletion] {
        var pendingDeletions: [PendingDeletion] = []

        do {
            for localFileName in Set(localFileNames) {
                if let pendingDeletion = try stageFileDeletion(named: localFileName) {
                    pendingDeletions.append(pendingDeletion)
                }
            }
            return pendingDeletions
        } catch {
            rollbackStagedDeletions(pendingDeletions)
            throw error
        }
    }

    func stageProofFilesClear() throws -> PendingDeletion? {
        let directory = try proofsDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        return try stageDeletion(at: directory)
    }

    func commitStagedDeletion(_ pendingDeletion: PendingDeletion?) {
        guard let pendingDeletion else { return }
        try? FileManager.default.removeItem(at: pendingDeletion.stagingDirectory)
    }

    func commitStagedDeletions(_ pendingDeletions: [PendingDeletion]) {
        for pendingDeletion in pendingDeletions {
            commitStagedDeletion(pendingDeletion)
        }
    }

    func rollbackStagedDeletion(_ pendingDeletion: PendingDeletion?) throws {
        guard let pendingDeletion else { return }
        guard FileManager.default.fileExists(atPath: pendingDeletion.stagedURL.path) else { return }

        do {
            try FileManager.default.createDirectory(
                at: pendingDeletion.originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: pendingDeletion.originalURL.path) {
                if isDirectory(pendingDeletion.stagedURL),
                   isDirectory(pendingDeletion.originalURL),
                   isDirectoryEmpty(pendingDeletion.originalURL) {
                    try FileManager.default.removeItem(at: pendingDeletion.originalURL)
                    try FileManager.default.moveItem(at: pendingDeletion.stagedURL, to: pendingDeletion.originalURL)
                    try protectFile(at: pendingDeletion.originalURL)
                } else {
                    try FileManager.default.removeItem(at: pendingDeletion.stagedURL)
                }
            } else {
                try FileManager.default.moveItem(at: pendingDeletion.stagedURL, to: pendingDeletion.originalURL)
                try protectFile(at: pendingDeletion.originalURL)
            }
            try? FileManager.default.removeItem(at: pendingDeletion.stagingDirectory)
        } catch {
            throw FileStorageError.unableToRestoreFile
        }
    }

    func rollbackStagedDeletions(_ pendingDeletions: [PendingDeletion]) {
        for pendingDeletion in pendingDeletions.reversed() {
            try? rollbackStagedDeletion(pendingDeletion)
        }
    }

    func clearProofFiles() throws {
        let directory = try proofsDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func isValidLocalFileName(_ localFileName: String?) -> Bool {
        guard let localFileName else { return false }
        return validatedLocalFileName(localFileName) != nil
    }

    func protectedTemporaryURL(fileName: String, data: Data) throws -> URL {
        let baseName = (fileName as NSString).deletingPathExtension
        let fileExtension = safeFileExtension(from: fileName)
        let uniqueSuffix = String(UUID().uuidString.prefix(8))
        let safeName = "DueProof-Export-\(safeBaseName(baseName, limit: 48))-\(Self.timestamp())-\(uniqueSuffix)"
        let finalName = fileExtension.map { "\(safeName).\($0)" } ?? safeName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(finalName)
        try data.write(to: url, options: [.atomic])
        try protectFile(at: url, excludeFromBackup: true)
        return url
    }

    func cleanupTemporaryExports() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in contents where url.lastPathComponent.hasPrefix("DueProof-Export-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteTemporaryExport(at url: URL?) {
        guard let url, isGeneratedTemporaryExport(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func protectLocalDataDirectory(_ directory: URL) {
        try? protectFile(at: directory)
    }

    private func normalizedJPEGData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_400
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let targetSize = CGSize(width: cgImage.width, height: cgImage.height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.82)
    }

    private func normalizedImagePixelSize(_ maxPixelSize: CGFloat) -> CGFloat? {
        guard maxPixelSize.isFinite, maxPixelSize > 0 else { return nil }
        return min(maxPixelSize, Self.maximumDisplayImagePixelSize)
    }

    private func isProofFileWithinReadLimit(at url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }
        return size <= Self.maximumProofFileBytes
    }

    private func protectFile(at url: URL, excludeFromBackup: Bool = false) throws {
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )

            var protectedURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = excludeFromBackup
            try protectedURL.setResourceValues(resourceValues)
        } catch {
            throw FileStorageError.unableToProtectFile
        }
    }

    private func stageDeletion(at url: URL) throws -> PendingDeletion {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(deletionStagingPrefix)\(UUID().uuidString)", isDirectory: true)
        let stagedURL = stagingDirectory.appendingPathComponent(url.lastPathComponent, isDirectory: url.hasDirectoryPath)

        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try protectFile(at: stagingDirectory, excludeFromBackup: true)
            try FileManager.default.moveItem(at: url, to: stagedURL)
            try protectFile(at: stagedURL, excludeFromBackup: true)
            return PendingDeletion(originalURL: url, stagedURL: stagedURL, stagingDirectory: stagingDirectory)
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            throw FileStorageError.unableToDeleteFile
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isDirectoryEmpty(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return contents.isEmpty
    }

    private func isGeneratedTemporaryExport(_ url: URL) -> Bool {
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        let exportURL = url.standardizedFileURL
        return exportURL.deletingLastPathComponent() == temporaryDirectory
            && exportURL.lastPathComponent.hasPrefix("DueProof-Export-")
    }

    private func validatedLocalFileName(_ localFileName: String) -> String? {
        let trimmed = localFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed == (trimmed as NSString).lastPathComponent else { return nil }
        guard !trimmed.contains("..") else { return nil }
        return trimmed
    }

    private func safeBaseName(_ name: String, limit: Int = 80) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let mappedScalars = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }

        let mapped = String(mappedScalars)
            .replacingOccurrences(of: "..", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        return mapped.isEmpty ? UUID().uuidString : String(mapped.prefix(max(1, limit)))
    }

    private func safeFileExtension(from fileName: String?) -> String? {
        guard let fileName else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 8 else { return nil }
        guard ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return ext
    }

    private func safeDocumentFileExtension(from fileName: String?) -> String? {
        guard let ext = safeFileExtension(from: fileName) else { return nil }
        return ext == "pdf" ? ext : nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
