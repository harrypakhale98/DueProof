import Foundation

enum DueProofShared {
    static let appGroupIdentifier = "group.com.hardik.dueproof"
    static let cloudKitContainerIdentifier = "iCloud.com.hardik.dueproof"

    static func appGroupContainerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

enum DueProofSharedStorageError: LocalizedError {
    case appGroupUnavailable
    case unableToCreateDirectory
    case emptyImportRequest

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "DueProof could not access its shared app group storage."
        case .unableToCreateDirectory:
            "DueProof could not prepare shared app group storage."
        case .emptyImportRequest:
            "That shared item did not include anything DueProof can import."
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
}

final class SharedClaimSnapshotStore {
    static let shared = SharedClaimSnapshotStore()

    private let fileName = "ClaimSnapshot.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ snapshot: SharedClaimSnapshot) throws {
        let url = try snapshotURL()
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    func load() -> SharedClaimSnapshot? {
        guard let url = try? snapshotURL(),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? decoder.decode(SharedClaimSnapshot.self, from: data)
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
        } catch {
            throw DueProofSharedStorageError.unableToCreateDirectory
        }
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

    private let queueDirectoryName = "QueuedImports"
    private let requestFileName = "request.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ request: SharedImportRequest) throws {
        let directory = try directory(for: request.id, create: true)
        let data = try encoder.encode(request)
        try data.write(to: directory.appendingPathComponent(requestFileName), options: [.atomic])
    }

    func pendingRequestIDs() -> [UUID] {
        guard let directory = try? queueDirectory(create: false),
              let contents = try? FileManager.default.contentsOfDirectory(
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
              let data = try? Data(contentsOf: directory.appendingPathComponent(requestFileName))
        else {
            return nil
        }

        return try? decoder.decode(SharedImportRequest.self, from: data)
    }

    func loadPendingRequests() -> [SharedImportRequest] {
        pendingRequestIDs()
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
        let directory = try directory(for: requestID, create: true)
        let fileName = "\(UUID().uuidString).\(safeFileExtension(from: originalFileName) ?? "dat")"
        try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
        return fileName
    }

    func delete(id: UUID) {
        guard let directory = try? directory(for: id, create: false) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func queueDirectory(create: Bool) throws -> URL {
        guard let container = DueProofShared.appGroupContainerURL() else {
            throw DueProofSharedStorageError.appGroupUnavailable
        }

        let directory = container.appendingPathComponent(queueDirectoryName, isDirectory: true)
        if create {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
}
