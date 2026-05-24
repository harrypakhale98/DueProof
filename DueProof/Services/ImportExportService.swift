import Foundation
import SwiftData

struct ClaimExportBundle: Codable {
    var exportedAt: Date
    var appName: String
    var schemaVersion: Int
    var includesBinaryProofData: Bool
    var claims: [ClaimRecord]

    private enum CodingKeys: String, CodingKey {
        case exportedAt
        case appName
        case schemaVersion
        case includesBinaryProofData
        case claims
    }

    init(
        exportedAt: Date,
        appName: String,
        schemaVersion: Int,
        includesBinaryProofData: Bool,
        claims: [ClaimRecord]
    ) {
        self.exportedAt = exportedAt
        self.appName = appName
        self.schemaVersion = schemaVersion
        self.includesBinaryProofData = includesBinaryProofData
        self.claims = claims
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? "DueProof"
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        includesBinaryProofData = try container.decodeIfPresent(Bool.self, forKey: .includesBinaryProofData) ?? false
        claims = try container.decodeIfPresent([ClaimRecord].self, forKey: .claims) ?? []
    }
}

struct ClaimRecord: Codable {
    var id: UUID
    var title: String
    var category: ClaimCategory
    var merchant: String?
    var valueAtRisk: Double
    var deadline: Date?
    var reminderDate: Date?
    var notes: String
    var status: ClaimStatus
    var proofItems: [ProofItemRecord]
    var createdAt: Date
    var updatedAt: Date
    var recoveredValue: Double
    var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case merchant
        case valueAtRisk
        case deadline
        case reminderDate
        case notes
        case status
        case proofItems
        case createdAt
        case updatedAt
        case recoveredValue
        case completedAt
    }

    init(
        id: UUID,
        title: String,
        category: ClaimCategory,
        merchant: String?,
        valueAtRisk: Double,
        deadline: Date?,
        reminderDate: Date?,
        notes: String,
        status: ClaimStatus,
        proofItems: [ProofItemRecord],
        createdAt: Date,
        updatedAt: Date,
        recoveredValue: Double,
        completedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.merchant = merchant
        self.valueAtRisk = valueAtRisk
        self.deadline = deadline
        self.reminderDate = reminderDate
        self.notes = notes
        self.status = status
        self.proofItems = proofItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recoveredValue = recoveredValue
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        category = Self.decodeCategory(from: container) ?? .other
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
        valueAtRisk = max(0, try container.decodeIfPresent(Double.self, forKey: .valueAtRisk) ?? 0)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        reminderDate = try container.decodeIfPresent(Date.self, forKey: .reminderDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = Self.decodeStatus(from: container) ?? .active
        proofItems = try container.decodeIfPresent([ProofItemRecord].self, forKey: .proofItems) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        recoveredValue = max(0, try container.decodeIfPresent(Double.self, forKey: .recoveredValue) ?? 0)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    var isImportable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func decodeCategory(from container: KeyedDecodingContainer<CodingKeys>) -> ClaimCategory? {
        if let category = try? container.decodeIfPresent(ClaimCategory.self, forKey: .category) {
            return category
        }

        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .category) else {
            return nil
        }

        return ClaimCategory(rawValue: rawValue)
    }

    private static func decodeStatus(from container: KeyedDecodingContainer<CodingKeys>) -> ClaimStatus? {
        if let status = try? container.decodeIfPresent(ClaimStatus.self, forKey: .status) {
            return status
        }

        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .status) else {
            return nil
        }

        return ClaimStatus(rawValue: rawValue)
    }
}

struct ProofItemRecord: Codable {
    var id: UUID
    var type: ProofItemType
    var localFileName: String?
    var displayName: String
    var extractedText: String?
    var intelligence: ProofIntelligence?
    var createdAt: Date
    var binaryProofData: Data?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case localFileName
        case displayName
        case extractedText
        case intelligence
        case createdAt
        case binaryProofData
    }

    init(
        id: UUID,
        type: ProofItemType,
        localFileName: String?,
        displayName: String,
        extractedText: String? = nil,
        intelligence: ProofIntelligence? = nil,
        createdAt: Date,
        binaryProofData: Data? = nil
    ) {
        self.id = id
        self.type = type
        self.localFileName = localFileName
        self.displayName = displayName
        self.extractedText = extractedText
        self.intelligence = intelligence
        self.createdAt = createdAt
        self.binaryProofData = binaryProofData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = Self.decodeType(from: container) ?? .photo
        localFileName = try container.decodeIfPresent(String.self, forKey: .localFileName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? type.displayName
        extractedText = try container.decodeIfPresent(String.self, forKey: .extractedText)
        intelligence = try container.decodeIfPresent(ProofIntelligence.self, forKey: .intelligence)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        binaryProofData = try container.decodeIfPresent(Data.self, forKey: .binaryProofData)
    }

    private static func decodeType(from container: KeyedDecodingContainer<CodingKeys>) -> ProofItemType? {
        if let type = try? container.decodeIfPresent(ProofItemType.self, forKey: .type) {
            return type
        }

        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .type) else {
            return nil
        }

        return ProofItemType(rawValue: rawValue)
    }
}

enum ImportExportError: LocalizedError {
    case importFileTooLarge
    case tooManyClaims
    case tooManyProofItems
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .importFileTooLarge:
            "That export is too large to import safely."
        case .tooManyClaims:
            "That export contains too many claims to import safely."
        case .tooManyProofItems:
            "That export contains too many proof items to import safely."
        case .unsupportedSchema:
            "That DueProof export format is not supported by this version."
        }
    }
}

final class ImportExportService {
    static let shared = ImportExportService()

    private let maximumImportBytes = 100_000_000
    private let maximumClaimCount = 1_000
    private let maximumProofCount = 10_000

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    func exportClaims(_ claims: [Claim]) throws -> URL {
        let records = claims.map { claim in
            ClaimRecord(
                id: claim.id,
                title: claim.title,
                category: claim.category,
                merchant: claim.merchant,
                valueAtRisk: claim.valueAtRisk,
                deadline: claim.deadline,
                reminderDate: claim.reminderDate,
                notes: claim.notes,
                status: claim.status,
                proofItems: claim.proofItemsList.map {
                    ProofItemRecord(
                        id: $0.id,
                        type: $0.type,
                        localFileName: $0.localFileName,
                        displayName: $0.displayName,
                        extractedText: $0.extractedText,
                        intelligence: $0.intelligence,
                        createdAt: $0.createdAt,
                        binaryProofData: FileStorageService.shared.data(for: $0)
                    )
                },
                createdAt: claim.createdAt,
                updatedAt: claim.updatedAt,
                recoveredValue: claim.recoveredValue,
                completedAt: claim.completedAt
            )
        }

        let bundle = ClaimExportBundle(
            exportedAt: Date(),
            appName: "DueProof",
            schemaVersion: 1,
            includesBinaryProofData: true,
            claims: records
        )

        let data = try encoder.encode(bundle)
        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: "Complete-\(Self.timestamp()).json",
            data: data
        )
    }

    @discardableResult
    func importClaims(from url: URL, into context: ModelContext) throws -> Int {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maximumImportBytes {
            throw ImportExportError.importFileTooLarge
        }

        let data = try Data(contentsOf: url)
        guard data.count <= maximumImportBytes else {
            throw ImportExportError.importFileTooLarge
        }

        let bundle = try decoder.decode(ClaimExportBundle.self, from: data)
        guard bundle.schemaVersion == 1 else {
            throw ImportExportError.unsupportedSchema
        }
        guard bundle.claims.count <= maximumClaimCount else {
            throw ImportExportError.tooManyClaims
        }
        guard bundle.claims.reduce(0, { $0 + $1.proofItems.count }) <= maximumProofCount else {
            throw ImportExportError.tooManyProofItems
        }

        var existingIDs = Set(try context.fetch(FetchDescriptor<Claim>()).map(\.id))
        var insertedCount = 0
        var importedProofIDs = Set<UUID>()

        for record in bundle.claims {
            guard record.isImportable, !existingIDs.contains(record.id) else { continue }

            let claim = Claim(
                id: record.id,
                title: Self.trim(record.title, limit: 160),
                category: record.category,
                merchant: Self.optionalTrim(record.merchant, limit: 120),
                valueAtRisk: record.valueAtRisk,
                deadline: record.deadline,
                reminderDate: record.reminderDate,
                notes: Self.trim(record.notes, limit: 4_000),
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                recoveredValue: record.recoveredValue,
                completedAt: record.completedAt
            )

            for proofRecord in record.proofItems where shouldImportProofItem(proofRecord) {
                guard !importedProofIDs.contains(proofRecord.id) else { continue }
                importedProofIDs.insert(proofRecord.id)

                let localFileName = try importedLocalFileName(for: proofRecord)
                let proof = ProofItem(
                    id: proofRecord.id,
                    type: proofRecord.type,
                    localFileName: localFileName,
                    syncedFileData: proofRecord.binaryProofData,
                    displayName: Self.trim(proofRecord.displayName, limit: 120),
                    extractedText: Self.optionalTrim(proofRecord.extractedText, limit: 12_000),
                    intelligence: proofRecord.intelligence,
                    createdAt: proofRecord.createdAt,
                    claim: claim
                )
                claim.proofItemsList.append(proof)
            }

            context.insert(claim)
            existingIDs.insert(record.id)
            insertedCount += 1
        }

        try context.save()
        return insertedCount
    }

    private func shouldImportProofItem(_ proofRecord: ProofItemRecord) -> Bool {
        if proofRecord.binaryProofData != nil { return true }
        guard let localFileName = proofRecord.localFileName else { return true }
        return FileStorageService.shared.isValidLocalFileName(localFileName)
            && FileStorageService.shared.fileExists(named: localFileName)
    }

    private func importedLocalFileName(for proofRecord: ProofItemRecord) throws -> String? {
        if let binaryProofData = proofRecord.binaryProofData {
            switch proofRecord.type {
            case .photo:
                return try FileStorageService.shared.saveImageData(binaryProofData)
            case .document, .note:
                return try FileStorageService.shared.saveDocumentData(
                    binaryProofData,
                    originalFileName: proofRecord.localFileName ?? proofRecord.displayName
                )
            }
        }

        guard let localFileName = proofRecord.localFileName else { return nil }
        return FileStorageService.shared.isValidLocalFileName(localFileName) ? localFileName : nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func trim(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func optionalTrim(_ value: String?, limit: Int) -> String? {
        let trimmed = trim(value ?? "", limit: limit)
        return trimmed.isEmpty ? nil : trimmed
    }
}
