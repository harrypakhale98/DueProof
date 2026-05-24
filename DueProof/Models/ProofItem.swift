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
            guard let intelligenceData else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(ProofIntelligence.self, from: intelligenceData)
        }
        set {
            guard let newValue else {
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
        self.id = id
        self.type = type
        self.localFileName = localFileName
        self.syncedFileData = syncedFileData
            ?? (SyncConfiguration.isICloudSyncEnabled ? FileStorageService.shared.data(for: localFileName) : nil)
        self.displayName = displayName
        self.extractedText = extractedText
        self.intelligenceData = nil
        self.createdAt = createdAt
        self.claim = claim
        self.intelligence = intelligence
    }
}
