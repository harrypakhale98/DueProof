import Foundation
import SwiftData

enum ProofItemType: String, Codable, CaseIterable, Identifiable, Hashable {
    case photo
    case document
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo: "Photo"
        case .document: "Document"
        case .note: "Note"
        }
    }
}

enum ProofItemTextLimits {
    static let displayName = 120
    static let extractedText = 12_000
}

@Model
final class ProofItem {
    var id: UUID = UUID()
    var type: ProofItemType = ProofItemType.photo
    var localFileName: String?
    @Attribute(.externalStorage) var syncedFileData: Data?
    var displayName: String = ""
    var extractedText: String?
    var intelligenceData: Data?
    var createdAt: Date = Date()
    var claim: Claim?

    var intelligence: ProofIntelligence? {
        get {
            decodedIntelligence()?.normalizedForStorage()
        }
        set {
            guard let newValue = newValue?.normalizedForStorage() else {
                intelligenceData = nil
                return
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            intelligenceData = try? encoder.encode(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        type: ProofItemType = .photo,
        localFileName: String? = nil,
        syncedFileData: Data? = nil,
        displayName: String,
        extractedText: String? = nil,
        intelligence: ProofIntelligence? = nil,
        createdAt: Date = Date(),
        claim: Claim? = nil
    ) {
        let normalizedLocalFileName = Self.normalizedLocalFileName(localFileName)
        let boundedSyncedFileData = Self.normalizedSyncedFileData(syncedFileData)

        self.id = id
        self.type = type
        self.localFileName = normalizedLocalFileName
        self.syncedFileData = boundedSyncedFileData
            ?? (SyncConfiguration.isICloudSyncEnabled ? FileStorageService.shared.data(for: normalizedLocalFileName) : nil)
        self.displayName = Self.normalizedDisplayName(displayName, type: type)
        self.extractedText = Self.normalizedExtractedText(extractedText)
        self.intelligenceData = nil
        self.createdAt = Self.normalizedCreatedAt(createdAt)
        self.claim = claim
        self.intelligence = intelligence
    }

    @discardableResult
    func normalizeStoredFields() -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ProofItem, Value>, to normalizedValue: Value) {
            guard self[keyPath: keyPath] != normalizedValue else { return }
            self[keyPath: keyPath] = normalizedValue
            didChange = true
        }

        let normalizedIntelligenceData = Self.encodedIntelligenceData(intelligence)

        update(\.localFileName, to: Self.normalizedLocalFileName(localFileName))
        update(\.syncedFileData, to: Self.normalizedSyncedFileData(syncedFileData))
        update(\.displayName, to: Self.normalizedDisplayName(displayName, type: type))
        update(\.extractedText, to: Self.normalizedExtractedText(extractedText))
        update(\.intelligenceData, to: normalizedIntelligenceData)
        update(\.createdAt, to: Self.normalizedCreatedAt(createdAt))

        return didChange
    }

    private func decodedIntelligence() -> ProofIntelligence? {
        guard let intelligenceData else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProofIntelligence.self, from: intelligenceData)
    }

    private static func encodedIntelligenceData(_ intelligence: ProofIntelligence?) -> Data? {
        guard let intelligence = intelligence?.normalizedForStorage() else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(intelligence)
    }

    private static func normalizedLocalFileName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              FileStorageService.shared.isValidLocalFileName(trimmed)
        else {
            return nil
        }
        return trimmed
    }

    private static func normalizedSyncedFileData(_ value: Data?) -> Data? {
        guard let value,
              value.count <= FileStorageService.maximumProofFileBytes
        else {
            return nil
        }
        return value
    }

    private static func normalizedDisplayName(_ value: String, type: ProofItemType) -> String {
        let normalized = ClaimTextLimits.required(value, limit: ProofItemTextLimits.displayName)
        return normalized.isEmpty ? type.displayName : normalized
    }

    private static func normalizedExtractedText(_ value: String?) -> String? {
        ClaimTextLimits.optional(value, limit: ProofItemTextLimits.extractedText)
    }

    private static func normalizedCreatedAt(_ value: Date) -> Date {
        value.timeIntervalSinceReferenceDate.isFinite ? value : Date()
    }
}
