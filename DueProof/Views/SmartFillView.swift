import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SmartFillView: View {
    @Environment(\.dismiss) private var dismiss

    var initialCategory: ClaimCategory?
    var onCreated: (() -> Void)?
    var onEditManually: (() -> Void)?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var proofData: Data?
    @State private var proofType: ProofItemType = .photo
    @State private var proofDisplayName = "Smart Fill Proof"
    @State private var proofImage: UIImage?
    @State private var ocrResult: OCRResult?
    @State private var proofIntelligence: ProofIntelligence?
    @State private var draft: ClaimDraft?
    @State private var isProcessing = false
    @State private var isImportingProofFile = false
    @State private var isCapturingPhoto = false
    @State private var errorMessage: String?
    @State private var availability = IntelligenceAvailabilityService.shared.availability()

    private let generator = ClaimDraftGenerator.shared

    var body: some View {
        NavigationStack {
            Group {
                if let draft, let ocrResult {
                    ClaimDraftReviewView(
                        draft: draft,
                        ocrResult: ocrResult,
                        proofData: proofData,
                        proofType: proofType,
                        proofDisplayName: proofDisplayName,
                        proofImage: proofImage,
                        proofIntelligence: proofIntelligence,
                        onCreated: {
                            onCreated?()
                            dismiss()
                        },
                        onEditManually: {
                            dismiss()
                            onEditManually?()
                        }
                    )
                } else {
                    intakeView
                }
            }
            .navigationTitle("Smart Fill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await process(newItem) }
            }
            .fileImporter(isPresented: $isImportingProofFile, allowedContentTypes: [.image, .pdf]) { result in
                Task { await processImportedFile(result) }
            }
            .fullScreenCover(isPresented: $isCapturingPhoto) {
                CameraCaptureView { image in
                    isCapturingPhoto = false
                    guard let image else { return }
                    Task { await processCameraImage(image) }
                }
                .ignoresSafeArea()
            }
            .alert("DueProof", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var intakeView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Smart Fill from Proof", systemImage: "doc.viewfinder")
                        .font(.headline)

                    Text("Choose a receipt, screenshot, warranty, gift card, or document. DueProof reads visible text on this iPhone and suggests a claim for you to review.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if !availability.isAvailable {
                    Label(availability.message, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(availability.message)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityLabel("Choose proof photo for Smart Fill")
                .disabled(isProcessing)

                Button {
                    isCapturingPhoto = true
                } label: {
                    Label("Scan with Camera", systemImage: "camera.viewfinder")
                }
                .disabled(isProcessing || !UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityLabel("Scan proof with camera")

                Button {
                    isImportingProofFile = true
                } label: {
                    Label("Import Image or PDF", systemImage: "folder.badge.plus")
                }
                .disabled(isProcessing)
                .accessibilityLabel("Import image or PDF for Smart Fill")

                if isProcessing {
                    HStack {
                        ProgressView()
                        Text("Reading proof...")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reading proof")
                }
            } footer: {
                Text("Processed on this iPhone. Not uploaded.")
            }
        }
    }

    @MainActor
    private func process(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                errorMessage = "DueProof could not read that proof image."
                return
            }

            await processImageData(data, image: image, displayName: "Smart Fill Photo")
        } catch {
            errorMessage = "DueProof could not load that proof image."
        }
    }

    @MainActor
    private func processCameraImage(_ image: UIImage) async {
        isProcessing = true
        defer { isProcessing = false }

        guard let data = image.jpegData(compressionQuality: 0.9) else {
            errorMessage = "DueProof could not prepare that proof image."
            return
        }

        await processImageData(data, image: image, displayName: "Camera Proof")
    }

    @MainActor
    private func processImportedFile(_ result: Result<URL, Error>) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension)

            if type?.conforms(to: .image) == true,
               let image = UIImage(data: data) {
                await processImageData(data, image: image, displayName: url.lastPathComponent)
                return
            }

            if type?.conforms(to: .pdf) == true {
                let text = await OCRService.shared.searchableText(at: url, type: .document) ?? ""
                await processRecognizedProof(
                    data: data,
                    type: .document,
                    displayName: url.lastPathComponent,
                    image: nil,
                    result: OCRResult(
                        text: text,
                        warnings: text.isEmpty ? ["No readable text was found in that PDF."] : []
                    )
                )
                return
            }

            errorMessage = "DueProof can smart fill from images and PDFs."
        } catch {
            errorMessage = "DueProof could not import that proof file."
        }
    }

    @MainActor
    private func processImageData(_ data: Data, image: UIImage, displayName: String) async {
        let result = await OCRService.shared.recognizeText(in: image)
        await processRecognizedProof(
            data: data,
            type: .photo,
            displayName: displayName,
            image: image,
            result: result
        )
    }

    @MainActor
    private func processRecognizedProof(
        data: Data,
        type: ProofItemType,
        displayName: String,
        image: UIImage?,
        result: OCRResult
    ) async {
        proofData = data
        proofType = type
        proofDisplayName = displayName
        proofImage = image

        async let generatedDraftTask = generator.generate(from: result)
        async let intelligenceTask = ProofIntelligenceService.shared.analyze(ocrResult: result, categoryHint: initialCategory)

        var generatedDraft = await generatedDraftTask
        let generatedIntelligence = await intelligenceTask

        if generatedDraft.category == nil {
            generatedDraft.category = initialCategory
        }

        ocrResult = result
        proofIntelligence = generatedIntelligence
        draft = generatedDraft
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    SmartFillView()
        .modelContainer(PreviewSampleData.container())
}
