import Foundation

enum DueProofShared {
    static let appGroupIdentifier = "group.com.hardik.dueproof"
    static let cloudKitContainerIdentifier = "iCloud.com.hardik.dueproof"

    static func appGroupContainerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

enum DueProofPrivacySettings {
    static let appLockEnabledKey = "DueProof.appLockEnabled"
    static let spotlightSearchEnabledKey = "DueProof.spotlightSearchEnabled"

    private static var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: DueProofShared.appGroupIdentifier)
    }

    static var defaults: UserDefaults {
        appGroupDefaults ?? .standard
    }

    static var isAppLockEnabled: Bool {
        guard let defaults = appGroupDefaults else {
            return true
        }
        defaults.bool(forKey: appLockEnabledKey)
    }

    static var isSpotlightSearchEnabled: Bool {
        guard let defaults = appGroupDefaults else {
            return false
        }
        defaults.bool(forKey: spotlightSearchEnabledKey)
    }
}

enum DueProofBoundedFileReader {
    private static let chunkSize = 1_048_576

    static func data(at url: URL, maximumBytes: Int, tooLargeError: Error) throws -> Data {
        guard maximumBytes >= 0 else {
            throw tooLargeError
        }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maximumBytes {
            throw tooLargeError
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var data = Data()
        let limit = maximumBytes + 1

        while true {
            let remainingBytes = limit - data.count
            guard remainingBytes > 0 else {
                throw tooLargeError
            }

            guard let chunk = try fileHandle.read(upToCount: min(chunkSize, remainingBytes)),
                  !chunk.isEmpty
            else {
                return data
            }

            data.append(chunk)
            guard data.count <= maximumBytes else {
                throw tooLargeError
            }
        }
    }
}

enum DueProofActionURL {
    static let maximumLength = 500

    static func normalizedString(from value: String?) -> String? {
        guard let url = url(from: value) else { return nil }
        return url.absoluteString
    }

    static func url(from value: String?) -> URL? {
        let bounded = String((value ?? "").prefix(Self.maximumLength))
        let trimmed = bounded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowedSchemes = Set(["http", "https", "mailto", "tel"])
        let explicitScheme = URLComponents(string: trimmed)?.scheme?.lowercased()
        if let explicitScheme, !allowedSchemes.contains(explicitScheme) { return nil }

        let lowercased = trimmed.lowercased()
        let candidate: String
        if let explicitScheme, explicitScheme == "http" || explicitScheme == "https" {
            guard lowercased.hasPrefix("\(explicitScheme)://") else { return nil }
            candidate = trimmed
        } else if explicitScheme == "mailto" || explicitScheme == "tel" {
            candidate = trimmed
        } else if trimmed.contains("@"),
                  !trimmed.contains("/"),
                  !trimmed.contains(" ") {
            candidate = "mailto:\(trimmed)"
        } else if isLikelyPhoneNumber(trimmed) {
            candidate = "tel:\(trimmed)"
        } else {
            candidate = "https://\(trimmed)"
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased()
        else {
            return nil
        }

        switch scheme {
        case "http", "https":
            guard url.host?.isEmpty == false else { return nil }
            return url
        case "mailto":
            guard url.path.contains("@") else { return nil }
            return url
        case "tel":
            let digits = url.path.filter(\.isNumber)
            guard digits.count >= 3 else { return nil }
            return url
        default:
            return nil
        }
    }

    private static func isLikelyPhoneNumber(_ value: String) -> Bool {
        let allowedScalars = CharacterSet(charactersIn: "+0123456789-() .")
        let digits = value.filter(\.isNumber)
        return digits.count >= 3 && value.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
    }
}

enum DueProofSharedText {
    static let maximumTextBytes = 1_000_000
    static let maximumTextCharacters = 12_000

    static func normalizedText(from value: String?) -> String? {
        let bounded = String((value ?? "").prefix(Self.maximumTextCharacters))
        let trimmed = bounded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func normalizedText(from data: Data) -> String? {
        guard data.count <= Self.maximumTextBytes,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return normalizedText(from: value)
    }
}

enum DueProofSharedFileName {
    static let maximumSuggestedNameCharacters = 160
    static let maximumBaseNameCharacters = 120

    static func originalFileName(
        suggestedName: String?,
        fallbackBaseName: String,
        fileExtension: String
    ) -> String {
        let boundedName = String((suggestedName ?? "").prefix(Self.maximumSuggestedNameCharacters))
        let trimmedName = boundedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateBaseName: String
        if trimmedName.isEmpty {
            candidateBaseName = fallbackBaseName
        } else {
            let lastComponent = (trimmedName as NSString).lastPathComponent
            candidateBaseName = (lastComponent as NSString).deletingPathExtension
        }

        let displayBaseName = candidateBaseName
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseName = displayBaseName.isEmpty ? fallbackBaseName : displayBaseName
        let safeExtension = normalizedExtension(fileExtension) ?? "dat"
        return "\(String(resolvedBaseName.prefix(Self.maximumBaseNameCharacters))).\(safeExtension)"
    }

    private static func normalizedExtension(_ value: String) -> String? {
        let normalized = String(value.lowercased().prefix(8))
        guard !normalized.isEmpty,
              normalized.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else {
            return nil
        }
        return normalized
    }
}

enum DueProofSharedStorageError: LocalizedError, Equatable {
    case appGroupUnavailable
    case unableToCreateDirectory
    case emptyImportRequest
    case sharedItemTooLarge

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "DueProof could not access its shared app group storage."
        case .unableToCreateDirectory:
            "DueProof could not prepare shared app group storage."
        case .emptyImportRequest:
            "That shared item did not include anything DueProof can import."
        case .sharedItemTooLarge:
            "That shared item is too large to import safely."
        }
    }
}

struct SharedClaimSnapshot: Codable, Equatable {
    struct ClaimSummary: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var merchant: String?
        var categoryDisplayName: String
        var categoryIconName: String
        var statusDisplayName: String
        var urgencyLabel: String
        var valueAtRisk: Double
        var deadline: Date?
        var hasProof: Bool

        func normalizedForDisplay() -> ClaimSummary {
            ClaimSummary(
                id: id,
                title: SharedClaimSnapshot.normalizedRequired(title, limit: 160, fallback: "Claim"),
                merchant: SharedClaimSnapshot.normalizedOptional(merchant, limit: 120),
                categoryDisplayName: SharedClaimSnapshot.normalizedRequired(categoryDisplayName, limit: 80, fallback: "Claim"),
                categoryIconName: SharedClaimSnapshot.normalizedSymbolName(categoryIconName),
                statusDisplayName: SharedClaimSnapshot.normalizedRequired(statusDisplayName, limit: 40, fallback: "Active"),
                urgencyLabel: SharedClaimSnapshot.normalizedRequired(urgencyLabel, limit: 80, fallback: "No deadline"),
                valueAtRisk: SharedClaimSnapshot.nonNegativeFinite(valueAtRisk),
                deadline: SharedClaimSnapshot.normalizedDate(deadline),
                hasProof: hasProof
            )
        }
    }

    var generatedAt: Date
    var moneyAtRisk: Double
    var recoveredValue: Double
    var urgentCount: Int
    var overdueCount: Int
    var activeCount: Int
    var prooflessOpenCount: Int
    var nextAction: ClaimSummary?
    var expiringSoon: [ClaimSummary]

    static let empty = SharedClaimSnapshot(
        generatedAt: .distantPast,
        moneyAtRisk: 0,
        recoveredValue: 0,
        urgentCount: 0,
        overdueCount: 0,
        activeCount: 0,
        prooflessOpenCount: 0,
        nextAction: nil,
        expiringSoon: []
    )

    func normalizedForDisplay() -> SharedClaimSnapshot {
        SharedClaimSnapshot(
            generatedAt: generatedAt.timeIntervalSinceReferenceDate.isFinite ? generatedAt : Date(),
            moneyAtRisk: Self.nonNegativeFinite(moneyAtRisk),
            recoveredValue: Self.nonNegativeFinite(recoveredValue),
            urgentCount: Self.nonNegativeCount(urgentCount),
            overdueCount: Self.nonNegativeCount(overdueCount),
            activeCount: Self.nonNegativeCount(activeCount),
            prooflessOpenCount: Self.nonNegativeCount(prooflessOpenCount),
            nextAction: nextAction?.normalizedForDisplay(),
            expiringSoon: expiringSoon.prefix(6).map { $0.normalizedForDisplay() }
        )
    }

    static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }

    static func nonNegativeFinite(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func nonNegativeCount(_ value: Int) -> Int {
        max(0, min(value, 99_999))
    }

    private static func normalizedRequired(_ value: String, limit: Int, fallback: String) -> String {
        let normalized = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        return normalized.isEmpty ? fallback : normalized
    }

    private static func normalizedOptional(_ value: String?, limit: Int) -> String? {
        let normalized = normalizedRequired(value ?? "", limit: limit, fallback: "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedSymbolName(_ value: String) -> String {
        let normalized = normalizedRequired(value, limit: 64, fallback: "checkmark.shield.fill")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "checkmark.shield.fill"
        }
        return normalized
    }
}

final class SharedClaimSnapshotStore {
    static let shared = SharedClaimSnapshotStore()
    static let maximumSnapshotBytes = 1_000_000

    private let fileName = "ClaimSnapshot.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ snapshot: SharedClaimSnapshot) throws {
        let url = try snapshotURL()
        let data = try encoder.encode(snapshot.normalizedForDisplay())
        guard data.count <= Self.maximumSnapshotBytes else {
            throw DueProofSharedStorageError.sharedItemTooLarge
        }
        try data.write(to: url, options: [.atomic])
        try Self.protectSharedItem(at: url)
    }

    func load() -> SharedClaimSnapshot? {
        guard let url = try? snapshotURL(),
              let data = try? DueProofBoundedFileReader.data(
                at: url,
                maximumBytes: Self.maximumSnapshotBytes,
                tooLargeError: DueProofSharedStorageError.sharedItemTooLarge
              )
        else {
            return nil
        }

        return try? decoder.decode(SharedClaimSnapshot.self, from: data).normalizedForDisplay()
    }

    func delete() {
        guard let url = try? snapshotURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func snapshotURL() throws -> URL {
        guard let container = DueProofShared.appGroupContainerURL() else {
            throw DueProofSharedStorageError.appGroupUnavailable
        }

        try Self.prepareDirectory(container)
        return container.appendingPathComponent(fileName)
    }

    private static func prepareDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try protectSharedItem(at: directory)
        } catch {
            throw DueProofSharedStorageError.unableToCreateDirectory
        }
    }

    private static func protectSharedItem(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}

struct SharedImportRequest: Codable, Equatable, Identifiable {
    var id: UUID
    var createdAt: Date
    var sourceApplication: String?
    var suggestedTitle: String
    var items: [SharedImportItem]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceApplication: String? = nil,
        suggestedTitle: String,
        items: [SharedImportItem]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceApplication = sourceApplication
        self.suggestedTitle = suggestedTitle
        self.items = items
    }
}

struct SharedImportItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case image
        case document
        case text
        case url
    }

    var id: UUID
    var kind: Kind
    var originalFileName: String?
    var storedFileName: String?
    var text: String?
    var urlString: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        originalFileName: String? = nil,
        storedFileName: String? = nil,
        text: String? = nil,
        urlString: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.text = text
        self.urlString = urlString
    }
}

final class SharedImportQueueStore {
    static let shared = SharedImportQueueStore()
    static let maximumSharedItemBytes = 25_000_000
    static let maximumRequestBytes = 1_000_000

    private let queueDirectoryName = "QueuedImports"
    private let requestFileName = "request.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager
    private let containerURLOverride: URL?

    init(fileManager: FileManager = .default, containerURL: URL? = nil) {
        self.fileManager = fileManager
        self.containerURLOverride = containerURL
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ request: SharedImportRequest) throws {
        guard !request.items.isEmpty else {
            if let directory = try? directory(for: request.id, create: false) {
                try? fileManager.removeItem(at: directory)
            }
            throw DueProofSharedStorageError.emptyImportRequest
        }

        let directory = try directory(for: request.id, create: true)
        let data = try encoder.encode(request)
        guard data.count <= Self.maximumRequestBytes else {
            try? fileManager.removeItem(at: directory)
            throw DueProofSharedStorageError.sharedItemTooLarge
        }

        let requestURL = directory.appendingPathComponent(requestFileName)
        do {
            try data.write(to: requestURL, options: [.atomic])
            try protectSharedItem(at: requestURL)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func pendingRequestIDs() -> [UUID] {
        guard let directory = try? queueDirectory(create: false),
              let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]
              )
        else {
            return []
        }

        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return UUID(uuidString: url.lastPathComponent)
        }
    }

    func load(id: UUID) -> SharedImportRequest? {
        guard let directory = try? directory(for: id, create: false),
              let data = try? readRequestData(in: directory)
        else {
            return nil
        }

        guard let request = try? decoder.decode(SharedImportRequest.self, from: data),
              isValidRequest(request, expectedID: id)
        else {
            return nil
        }

        return request
    }

    func loadPendingRequests() -> [SharedImportRequest] {
        cleanupOrphanedRequests()

        return pendingRequestIDs()
            .compactMap(load(id:))
            .sorted { $0.createdAt < $1.createdAt }
    }

    func fileURL(for requestID: UUID, storedFileName: String) -> URL? {
        guard isSafeFileName(storedFileName),
              let directory = try? directory(for: requestID, create: false)
        else {
            return nil
        }

        return directory.appendingPathComponent(storedFileName)
    }

    func writeFile(data: Data, originalFileName: String?, requestID: UUID) throws -> String {
        guard data.count <= Self.maximumSharedItemBytes else {
            throw DueProofSharedStorageError.sharedItemTooLarge
        }

        let directory = try directory(for: requestID, create: true)
        let fileName = "\(UUID().uuidString).\(safeFileExtension(from: originalFileName) ?? "dat")"
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        try protectSharedItem(at: fileURL)
        return fileName
    }

    func writeFile(from sourceURL: URL, originalFileName: String?, requestID: UUID) throws -> String {
        let data = try DueProofBoundedFileReader.data(
            at: sourceURL,
            maximumBytes: Self.maximumSharedItemBytes,
            tooLargeError: DueProofSharedStorageError.sharedItemTooLarge
        )
        return try writeFile(data: data, originalFileName: originalFileName, requestID: requestID)
    }

    func delete(id: UUID) {
        guard let directory = try? directory(for: id, create: false) else { return }
        try? fileManager.removeItem(at: directory)
    }

    func deleteAll() {
        guard let directory = try? queueDirectory(create: false) else { return }
        try? fileManager.removeItem(at: directory)
    }

    @discardableResult
    func cleanupOrphanedRequests(olderThan cutoff: Date = Date().addingTimeInterval(-3_600)) -> Int {
        guard let directory = try? queueDirectory(create: false),
              let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]
              )
        else {
            return 0
        }

        var deletedCount = 0
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  isOlderThanCutoff(url, cutoff: cutoff)
            else {
                continue
            }

            guard let id = UUID(uuidString: url.lastPathComponent),
                  isValidRequestDirectory(url, id: id)
            else {
                try? fileManager.removeItem(at: url)
                deletedCount += 1
                continue
            }
        }

        return deletedCount
    }

    private func queueDirectory(create: Bool) throws -> URL {
        guard let container = containerURLOverride ?? DueProofShared.appGroupContainerURL(fileManager: fileManager) else {
            throw DueProofSharedStorageError.appGroupUnavailable
        }

        let directory = container.appendingPathComponent(queueDirectoryName, isDirectory: true)
        if create {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try protectSharedItem(at: directory)
            } catch {
                throw DueProofSharedStorageError.unableToCreateDirectory
            }
        }
        return directory
    }

    private func directory(for id: UUID, create: Bool) throws -> URL {
        let directory = try queueDirectory(create: create).appendingPathComponent(id.uuidString, isDirectory: true)
        if create {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try protectSharedItem(at: directory)
            } catch {
                throw DueProofSharedStorageError.unableToCreateDirectory
            }
        }
        return directory
    }

    private func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName == (fileName as NSString).lastPathComponent
            && !fileName.contains("..")
    }

    private func safeFileExtension(from fileName: String?) -> String? {
        guard let fileName else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 8 else { return nil }
        guard ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        return ext
    }

    private func protectSharedItem(at url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func isValidRequestDirectory(_ directory: URL, id: UUID) -> Bool {
        guard let data = try? readRequestData(in: directory),
              let request = try? decoder.decode(SharedImportRequest.self, from: data)
        else {
            return false
        }

        return isValidRequest(request, expectedID: id)
    }

    private func readRequestData(in directory: URL) throws -> Data {
        try DueProofBoundedFileReader.data(
            at: directory.appendingPathComponent(requestFileName),
            maximumBytes: Self.maximumRequestBytes,
            tooLargeError: DueProofSharedStorageError.sharedItemTooLarge
        )
    }

    private func isOlderThanCutoff(_ url: URL, cutoff: Date) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        guard let date = values?.contentModificationDate ?? values?.creationDate else {
            return false
        }
        return date < cutoff
    }

    private func isValidRequest(_ request: SharedImportRequest, expectedID: UUID) -> Bool {
        request.id == expectedID && !request.items.isEmpty
    }
}
