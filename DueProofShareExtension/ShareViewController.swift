import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private var didStartImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Saving to DueProof..."
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartImport else { return }
        didStartImport = true

        Task {
            await saveSharedItems()
        }
    }

    @MainActor
    private func saveSharedItems() async {
        var pendingRequestID: UUID?

        do {
            let request = try await makeImportRequest()
            pendingRequestID = request.id
            try SharedImportQueueStore.shared.save(request)
            openDueProof(requestID: request.id)
        } catch {
            if let pendingRequestID {
                SharedImportQueueStore.shared.delete(id: pendingRequestID)
            }
            statusLabel.text = error.localizedDescription
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    private func makeImportRequest() async throws -> SharedImportRequest {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        let requestID = UUID()
        do {
            var items: [SharedImportItem] = []

            for provider in providers {
                if let item = try await loadImageItem(from: provider, requestID: requestID) {
                    items.append(item)
                    continue
                }

                if let item = try await loadPDFItem(from: provider, requestID: requestID) {
                    items.append(item)
                    continue
                }

                if let item = try await loadURLItem(from: provider) {
                    items.append(item)
                    continue
                }

                if let item = try await loadTextItem(from: provider) {
                    items.append(item)
                }
            }

            guard !items.isEmpty else {
                throw DueProofSharedStorageError.emptyImportRequest
            }

            return SharedImportRequest(
                id: requestID,
                sourceApplication: nil,
                suggestedTitle: suggestedTitle(from: items),
                items: items
            )
        } catch {
            SharedImportQueueStore.shared.delete(id: requestID)
            throw error
        }
    }

    private func loadImageItem(from provider: NSItemProvider, requestID: UUID) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        let originalFileName = DueProofSharedFileName.originalFileName(
            suggestedName: provider.suggestedName,
            fallbackBaseName: "Shared Photo",
            fileExtension: "jpg"
        )
        guard let storedFileName = try await loadFile(
            from: provider,
            type: .image,
            originalFileName: originalFileName,
            requestID: requestID
        ) else {
            return nil
        }

        return SharedImportItem(
            kind: .image,
            originalFileName: originalFileName,
            storedFileName: storedFileName
        )
    }

    private func loadPDFItem(from provider: NSItemProvider, requestID: UUID) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) else {
            return nil
        }

        let originalFileName = DueProofSharedFileName.originalFileName(
            suggestedName: provider.suggestedName,
            fallbackBaseName: "Shared Document",
            fileExtension: "pdf"
        )
        guard let storedFileName = try await loadFile(
            from: provider,
            type: .pdf,
            originalFileName: originalFileName,
            requestID: requestID
        ) else {
            return nil
        }

        return SharedImportItem(
            kind: .document,
            originalFileName: originalFileName,
            storedFileName: storedFileName
        )
    }

    private func loadURLItem(from provider: NSItemProvider) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
              let item = try await loadItem(from: provider, type: .url)
        else {
            return nil
        }

        let urlString: String?
        if let loadedURL = item as? URL {
            urlString = DueProofActionURL.normalizedString(from: loadedURL.absoluteString)
        } else if let data = item as? Data {
            guard data.count <= DueProofActionURL.maximumLength * 4,
                  let string = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            urlString = DueProofActionURL.normalizedString(from: string)
        } else if let string = item as? String {
            urlString = DueProofActionURL.normalizedString(from: string)
        } else {
            urlString = nil
        }

        guard let urlString else { return nil }
        return SharedImportItem(kind: .url, text: urlString, urlString: urlString)
    }

    private func loadTextItem(from provider: NSItemProvider) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
              let item = try await loadItem(from: provider, type: .text)
        else {
            return nil
        }

        let text: String?
        if let loadedText = item as? String {
            text = DueProofSharedText.normalizedText(from: loadedText)
        } else if let data = item as? Data {
            text = DueProofSharedText.normalizedText(from: data)
        } else {
            text = nil
        }

        guard let text else { return nil }
        return SharedImportItem(kind: .text, text: text)
    }

    private func loadFile(
        from provider: NSItemProvider,
        type: UTType,
        originalFileName: String,
        requestID: UUID
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    do {
                        let storedFileName = try SharedImportQueueStore.shared.writeFile(
                            from: url,
                            originalFileName: originalFileName,
                            requestID: requestID
                        )
                        continuation.resume(returning: storedFileName)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadItem(from provider: NSItemProvider, type: UTType) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    private func suggestedTitle(from items: [SharedImportItem]) -> String {
        if let fileName = items.compactMap(\.originalFileName).first, !fileName.isEmpty {
            return String((fileName as NSString).deletingPathExtension.prefix(160))
        }

        if let text = items.compactMap(\.text).first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return String(text.prefix(80))
        }

        return "Shared Proof"
    }

    private func openDueProof(requestID: UUID) {
        guard let url = URL(string: "dueproof://import-shared/\(requestID.uuidString)") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extensionContext?.open(url) { _ in
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
