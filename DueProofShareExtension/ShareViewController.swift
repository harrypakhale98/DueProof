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
        do {
            let request = try await makeImportRequest()
            try SharedImportQueueStore.shared.save(request)
            openDueProof(requestID: request.id)
        } catch {
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
    }

    private func loadImageItem(from provider: NSItemProvider, requestID: UUID) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
              let data = try await loadData(from: provider, type: .image)
        else {
            return nil
        }

        let storedFileName = try SharedImportQueueStore.shared.writeFile(
            data: data,
            originalFileName: provider.suggestedName.map { "\($0).jpg" },
            requestID: requestID
        )

        return SharedImportItem(
            kind: .image,
            originalFileName: provider.suggestedName ?? "Shared Photo",
            storedFileName: storedFileName
        )
    }

    private func loadPDFItem(from provider: NSItemProvider, requestID: UUID) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
              let data = try await loadData(from: provider, type: .pdf)
        else {
            return nil
        }

        let originalFileName = provider.suggestedName.map { "\($0).pdf" } ?? "Shared Document.pdf"
        let storedFileName = try SharedImportQueueStore.shared.writeFile(
            data: data,
            originalFileName: originalFileName,
            requestID: requestID
        )

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

        let url: URL?
        if let loadedURL = item as? URL {
            url = loadedURL
        } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else if let string = item as? String {
            url = URL(string: string)
        } else {
            url = nil
        }

        guard let url else { return nil }
        return SharedImportItem(kind: .url, text: url.absoluteString, urlString: url.absoluteString)
    }

    private func loadTextItem(from provider: NSItemProvider) async throws -> SharedImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
              let item = try await loadItem(from: provider, type: .text)
        else {
            return nil
        }

        let text: String?
        if let loadedText = item as? String {
            text = loadedText
        } else if let data = item as? Data {
            text = String(data: data, encoding: .utf8)
        } else {
            text = nil
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return SharedImportItem(kind: .text, text: text)
    }

    private func loadData(from provider: NSItemProvider, type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
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
            return (fileName as NSString).deletingPathExtension
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
