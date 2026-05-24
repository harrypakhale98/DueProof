import Foundation
import ImageIO
import UIKit

enum FileStorageError: LocalizedError {
    case unableToCreateDirectory
    case unableToReadImage
    case unableToProtectFile
    case unableToWriteImage

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            "DueProof could not create the local proof storage folder."
        case .unableToReadImage:
            "DueProof could not prepare that proof photo for private local storage."
        case .unableToProtectFile:
            "DueProof could not apply local file protection to that proof."
        case .unableToWriteImage:
            "DueProof could not save that proof photo locally."
        }
    }
}

final class FileStorageService {
    static let shared = FileStorageService()

    private let folderName = "ProofItems"

    private init() {}

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
        let fileExtension = safeFileExtension(from: originalFileName) ?? "pdf"
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

    func fileExists(named localFileName: String?) -> Bool {
        guard let localFileName, let url = url(for: localFileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func data(for localFileName: String?) -> Data? {
        guard let localFileName, let url = url(for: localFileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    func image(for localFileName: String) -> UIImage? {
        guard let url = url(for: localFileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func thumbnail(for localFileName: String, maxPixelSize: CGFloat = 360) -> UIImage? {
        guard let url = url(for: localFileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: thumbnail)
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
        let safeName = "DueProof-Export-\(safeBaseName(baseName))-\(Self.timestamp())"
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

    func protectLocalDataDirectory(_ directory: URL) {
        try? protectFile(at: directory)
    }

    private func normalizedJPEGData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let maximumDimension: CGFloat = 2_400
        let largestDimension = max(image.size.width, image.size.height)
        let targetSize: CGSize

        if largestDimension > maximumDimension {
            let scale = maximumDimension / largestDimension
            targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        } else {
            targetSize = image.size
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.82)
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

    private func validatedLocalFileName(_ localFileName: String) -> String? {
        let trimmed = localFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed == (trimmed as NSString).lastPathComponent else { return nil }
        guard !trimmed.contains("..") else { return nil }
        return trimmed
    }

    private func safeBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let mappedScalars = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }

        let mapped = String(mappedScalars)
            .replacingOccurrences(of: "..", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        return mapped.isEmpty ? UUID().uuidString : mapped
    }

    private func safeFileExtension(from fileName: String?) -> String? {
        guard let fileName else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 8 else { return nil }
        guard ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        return ext
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
