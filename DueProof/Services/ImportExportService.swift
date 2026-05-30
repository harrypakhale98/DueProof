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
        exportedAt = Self.decodeDate(from: container, forKey: .exportedAt) ?? Date()
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? "DueProof"
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        includesBinaryProofData = try container.decodeIfPresent(Bool.self, forKey: .includesBinaryProofData) ?? false
        claims = try container.decodeIfPresent([ClaimRecord].self, forKey: .claims) ?? []
    }

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        do {
            return normalizedDate(try container.decodeIfPresent(Date.self, forKey: key))
        } catch {
            return nil
        }
    }

    private static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
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
    var referenceNumber: String?
    var policySummary: String
    var actionURLString: String?
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
        case referenceNumber
        case policySummary
        case actionURLString
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
        referenceNumber: String?,
        policySummary: String,
        actionURLString: String?,
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
        self.referenceNumber = referenceNumber
        self.policySummary = policySummary
        self.actionURLString = actionURLString
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
        valueAtRisk = Self.nonNegativeFinite(try container.decodeIfPresent(Double.self, forKey: .valueAtRisk) ?? 0)
        deadline = Self.decodeDate(from: container, forKey: .deadline)
        reminderDate = Self.decodeDate(from: container, forKey: .reminderDate)
        referenceNumber = try container.decodeIfPresent(String.self, forKey: .referenceNumber)
        policySummary = try container.decodeIfPresent(String.self, forKey: .policySummary) ?? ""
        actionURLString = try container.decodeIfPresent(String.self, forKey: .actionURLString)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = Self.decodeStatus(from: container) ?? .active
        proofItems = try container.decodeIfPresent([ProofItemRecord].self, forKey: .proofItems) ?? []
        createdAt = Self.decodeDate(from: container, forKey: .createdAt) ?? now
        updatedAt = Self.decodeDate(from: container, forKey: .updatedAt) ?? createdAt
        recoveredValue = Self.nonNegativeFinite(try container.decodeIfPresent(Double.self, forKey: .recoveredValue) ?? 0)
        completedAt = Self.decodeDate(from: container, forKey: .completedAt)
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

    private static func nonNegativeFinite(_ value: Double) -> Double {
        CurrencyFormatter.sanitizedAmount(value)
    }

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        do {
            return normalizedDate(try container.decodeIfPresent(Date.self, forKey: key))
        } catch {
            return nil
        }
    }

    private static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
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
        createdAt = Self.decodeDate(from: container, forKey: .createdAt) ?? Date()
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

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        do {
            return normalizedDate(try container.decodeIfPresent(Date.self, forKey: key))
        } catch {
            return nil
        }
    }

    private static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }
}

struct ImportClaimsResult: Equatable {
    var insertedCount: Int
    var insertedClaimIDs: [UUID]
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
        let records = claims.map(exportRecord)

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

    private func exportRecord(for claim: Claim) -> ClaimRecord {
        let valueAtRisk = CurrencyFormatter.sanitizedAmount(claim.valueAtRisk)
        let status = ClaimStatus.normalizedStoredStatus(claim.status)
        let deadline = Self.normalizedDate(claim.deadline)
        let createdAt = Self.normalizedDate(claim.createdAt) ?? Date()
        let updatedAt = Self.normalizedDate(claim.updatedAt) ?? createdAt
        let completionFields = Self.normalizedCompletionFields(
            status: status,
            valueAtRisk: valueAtRisk,
            recoveredValue: claim.recoveredValue,
            completedAt: claim.completedAt,
            fallbackCompletionDate: updatedAt
        )

        return ClaimRecord(
            id: claim.id,
            title: Self.requiredText(claim.title, limit: ClaimTextLimits.title, fallback: "Untitled claim"),
            category: claim.category,
            merchant: ClaimTextLimits.optional(claim.merchant, limit: ClaimTextLimits.merchant),
            valueAtRisk: valueAtRisk,
            deadline: deadline,
            reminderDate: Self.normalizedReminderDate(claim.reminderDate, deadline: deadline, status: status),
            referenceNumber: ClaimTextLimits.optional(claim.referenceNumber, limit: ClaimTextLimits.reference),
            policySummary: ClaimTextLimits.required(claim.policySummary, limit: ClaimTextLimits.policySummary),
            actionURLString: Claim.normalizedActionURLString(claim.actionURLString),
            notes: ClaimTextLimits.required(claim.notes, limit: ClaimTextLimits.notes),
            status: status,
            proofItems: claim.proofItemsList.map(exportProofRecord),
            createdAt: createdAt,
            updatedAt: updatedAt,
            recoveredValue: completionFields.recoveredValue,
            completedAt: completionFields.completedAt
        )
    }

    private func exportProofRecord(for proof: ProofItem) -> ProofItemRecord {
        let localFileName = FileStorageService.shared.isValidLocalFileName(proof.localFileName) ? proof.localFileName : nil

        return ProofItemRecord(
            id: proof.id,
            type: proof.type,
            localFileName: localFileName,
            displayName: Self.requiredText(proof.displayName, limit: ProofItemTextLimits.displayName, fallback: proof.type.displayName),
            extractedText: ClaimTextLimits.optional(proof.extractedText, limit: ProofItemTextLimits.extractedText),
            intelligence: proof.intelligence?.normalizedForStorage(),
            createdAt: Self.normalizedDate(proof.createdAt) ?? Date(),
            binaryProofData: FileStorageService.shared.data(for: proof)
        )
    }

    @discardableResult
    func importClaims(from url: URL, into context: ModelContext) throws -> Int {
        try importClaimsWithResult(from: url, into: context).insertedCount
    }

    @discardableResult
    func importClaimsWithResult(from url: URL, into context: ModelContext) throws -> ImportClaimsResult {
        let data = try DueProofBoundedFileReader.data(
            at: url,
            maximumBytes: maximumImportBytes,
            tooLargeError: ImportExportError.importFileTooLarge
        )

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
        var insertedClaimIDs: [UUID] = []
        var insertedClaims: [Claim] = []
        var localFileNamesCreatedByImport: [String] = []

        do {
            for record in bundle.claims {
                guard record.isImportable, !existingIDs.contains(record.id) else { continue }
                var importedProofIDsForClaim = Set<UUID>()

                let importedStatus = ClaimStatus.normalizedStoredStatus(record.status)
                let completionFields = Self.normalizedCompletionFields(
                    status: importedStatus,
                    valueAtRisk: record.valueAtRisk,
                    recoveredValue: record.recoveredValue,
                    completedAt: record.completedAt,
                    fallbackCompletionDate: record.updatedAt
                )
                let claim = Claim(
                    id: record.id,
                    title: ClaimTextLimits.required(record.title, limit: ClaimTextLimits.title),
                    category: record.category,
                    merchant: ClaimTextLimits.optional(record.merchant, limit: ClaimTextLimits.merchant),
                    valueAtRisk: record.valueAtRisk,
                    deadline: record.deadline,
                    reminderDate: Self.normalizedReminderDate(
                        record.reminderDate,
                        deadline: record.deadline,
                        status: importedStatus
                    ),
                    referenceNumber: ClaimTextLimits.optional(record.referenceNumber, limit: ClaimTextLimits.reference),
                    policySummary: ClaimTextLimits.required(record.policySummary, limit: ClaimTextLimits.policySummary),
                    actionURLString: Claim.normalizedActionURLString(record.actionURLString),
                    notes: ClaimTextLimits.required(record.notes, limit: ClaimTextLimits.notes),
                    status: importedStatus,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    recoveredValue: completionFields.recoveredValue,
                    completedAt: completionFields.completedAt
                )

                for proofRecord in record.proofItems where shouldImportProofItem(proofRecord) {
                    guard !importedProofIDsForClaim.contains(proofRecord.id) else { continue }
                    importedProofIDsForClaim.insert(proofRecord.id)

                    let localFileName = try importedLocalFileName(for: proofRecord)
                    if proofRecord.binaryProofData != nil, let localFileName {
                        localFileNamesCreatedByImport.append(localFileName)
                    }
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
                insertedClaims.append(claim)
                existingIDs.insert(record.id)
                insertedCount += 1
                insertedClaimIDs.append(record.id)
            }

            try context.save()
            return ImportClaimsResult(insertedCount: insertedCount, insertedClaimIDs: insertedClaimIDs)
        } catch {
            for claim in insertedClaims {
                context.delete(claim)
            }
            localFileNamesCreatedByImport.forEach { _ = FileStorageService.shared.deleteFile(named: $0) }
            try? context.save()
            throw error
        }
    }

    private func shouldImportProofItem(_ proofRecord: ProofItemRecord) -> Bool {
        if proofRecord.binaryProofData != nil { return true }
        if proofRecord.type == .note { return true }
        guard let localFileName = proofRecord.localFileName else { return false }
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

    private static func normalizedCompletionFields(
        status: ClaimStatus,
        valueAtRisk: Double,
        recoveredValue: Double,
        completedAt: Date?,
        fallbackCompletionDate: Date
    ) -> (recoveredValue: Double, completedAt: Date?) {
        let fallbackCompletionDate = normalizedDate(fallbackCompletionDate) ?? Date()
        let completedAt = normalizedDate(completedAt)
        let valueAtRisk = CurrencyFormatter.sanitizedAmount(valueAtRisk)
        let recoveredValue = CurrencyFormatter.sanitizedAmount(recoveredValue)

        switch status {
        case .recovered:
            let resolvedRecoveredValue = recoveredValue > 0 ? min(recoveredValue, valueAtRisk) : valueAtRisk
            return (max(0, resolvedRecoveredValue), completedAt ?? fallbackCompletionDate)
        case .used, .expired, .ignored:
            return (0, completedAt ?? fallbackCompletionDate)
        case .active, .urgent, .overdue:
            return (0, nil)
        }
    }

    private static func normalizedReminderDate(_ reminderDate: Date?, deadline: Date?, status: ClaimStatus) -> Date? {
        guard status.isOpen,
              let reminderDate = normalizedDate(reminderDate),
              reminderDate > Date()
        else {
            return nil
        }

        if let deadline = normalizedDate(deadline), reminderDate > deadline {
            return nil
        }

        return reminderDate
    }

    private static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func requiredText(_ value: String, limit: Int, fallback: String) -> String {
        let trimmed = trim(value, limit: limit)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func trim(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func optionalTrim(_ value: String?, limit: Int) -> String? {
        let trimmed = trim(value ?? "", limit: limit)
        return trimmed.isEmpty ? nil : trimmed
    }
}
