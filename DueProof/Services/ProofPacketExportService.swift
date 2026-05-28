import Foundation
import UIKit

final class ProofPacketExportService {
    static let shared = ProofPacketExportService()

    private let pageSize = CGSize(width: 612, height: 792)
    private let margin: CGFloat = 44

    private init() {}

    func exportPacket(for claim: Claim) throws -> URL {
        let title = normalizedRequired(claim.title, limit: ClaimTextLimits.title, fallback: "Untitled claim")
        let policySummary = normalizedOptional(claim.policySummary, limit: ClaimTextLimits.policySummary)
        let notes = normalizedOptional(claim.notes, limit: ClaimTextLimits.notes)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            let writer = PDFPageWriter(context: context, pageSize: pageSize, margin: margin)

            writer.addTitle("DueProof Packet")
            writer.addSubtitle(title)
            writer.addDivider()

            writer.addSection("Claim Summary")
            writer.addKeyValue("Category", claim.categoryDisplayName)
            writer.addKeyValue("Status", claim.statusDisplayName)
            writer.addKeyValue("Value at Risk", claim.displayValue)
            writer.addKeyValue("Deadline", deadlineText(for: claim.deadline))
            writer.addKeyValue("Reminder", fullDateText(for: claim.reminderDate) ?? "No reminder set")
            writer.addKeyValue("Merchant", normalizedOptional(claim.merchant, limit: ClaimTextLimits.merchant) ?? "Not set")
            writer.addKeyValue("Reference", claim.primaryReference ?? "Not set")
            writer.addKeyValue("Action Link", claim.actionURL?.absoluteString ?? "Not set")
            writer.addKeyValue("Created", fullDateText(for: claim.createdAt) ?? "Unknown")
            writer.addKeyValue("Updated", fullDateText(for: claim.updatedAt) ?? "Unknown")

            if let policySummary {
                writer.addSection("Policy Note")
                writer.addBody(policySummary)
            }

            let actionPlan = ClaimActionPlanService.shared.plan(for: claim)
            writer.addSection("Next Action")
            writer.addBody(actionPlan.nextStep)

            writer.addSection("Checklist")
            for item in actionPlan.checklist {
                writer.addBullet(item)
            }

            if let notes {
                writer.addSection("Notes")
                writer.addBody(notes)
            }

            writer.addSection("Proof")
            if claim.proofItemsList.isEmpty {
                writer.addBody("No proof is attached to this claim yet.")
            } else {
                for proof in claim.proofItemsList.sorted(by: proofSort) {
                    writer.addProof(proof)
                }
            }

            writer.addFooter()
        }

        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: "\(title)-proof-packet.pdf",
            data: data
        )
    }

    private func normalizedRequired(_ value: String, limit: Int, fallback: String) -> String {
        let normalized = ClaimTextLimits.required(value, limit: limit)
        return normalized.isEmpty ? fallback : normalized
    }

    private func normalizedOptional(_ value: String?, limit: Int) -> String? {
        ClaimTextLimits.optional(value, limit: limit)
    }

    private func deadlineText(for date: Date?) -> String {
        guard let date else { return "No deadline" }
        guard date.timeIntervalSinceReferenceDate.isFinite else { return "Invalid deadline" }
        return DateHelpers.deadlineText(for: date)
    }

    private func fullDateText(for date: Date?) -> String? {
        guard let date else { return nil }
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return DateHelpers.fullDateTime(date)
    }

    private func proofSort(_ lhs: ProofItem, _ rhs: ProofItem) -> Bool {
        let lhsDate = lhs.createdAt.timeIntervalSinceReferenceDate.isFinite ? lhs.createdAt : .distantFuture
        let rhsDate = rhs.createdAt.timeIntervalSinceReferenceDate.isFinite ? rhs.createdAt : .distantFuture
        return lhsDate < rhsDate
    }
}

private final class PDFPageWriter {
    private static let maximumDrawCharacters = 8_000
    private static let maximumFragmentCharacters = 700

    private let context: UIGraphicsPDFRendererContext
    private let pageSize: CGSize
    private let margin: CGFloat
    private var y: CGFloat

    private var contentWidth: CGFloat {
        pageSize.width - margin * 2
    }

    init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat) {
        self.context = context
        self.pageSize = pageSize
        self.margin = margin
        self.y = margin
    }

    func addTitle(_ text: String) {
        draw(text, font: .systemFont(ofSize: 28, weight: .bold), color: .label, spacingAfter: 6)
    }

    func addSubtitle(_ text: String) {
        draw(text, font: .systemFont(ofSize: 17, weight: .semibold), color: .secondaryLabel, spacingAfter: 14)
    }

    func addSection(_ text: String) {
        ensureSpace(42)
        y += 8
        draw(text, font: .systemFont(ofSize: 15, weight: .bold), color: .label, spacingAfter: 8)
    }

    func addBody(_ text: String) {
        draw(text, font: .systemFont(ofSize: 11), color: .label, spacingAfter: 10)
    }

    func addBullet(_ text: String) {
        draw("- \(text)", font: .systemFont(ofSize: 11), color: .label, spacingAfter: 6)
    }

    func addKeyValue(_ key: String, _ value: String) {
        let combined = "\(key): \(value)"
        draw(combined, font: .systemFont(ofSize: 11), color: .label, spacingAfter: 5)
    }

    func addDivider() {
        ensureSpace(16)
        UIColor.separator.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        path.lineWidth = 1
        path.stroke()
        y += 16
    }

    func addProof(_ proof: ProofItem) {
        ensureSpace(72)
        let displayName = ClaimTextLimits.required(proof.displayName, limit: ProofItemTextLimits.displayName)
        draw(displayName.isEmpty ? proof.type.displayName : displayName, font: .systemFont(ofSize: 12, weight: .semibold), color: .label, spacingAfter: 4)
        addKeyValue("Type", proof.type.displayName)
        addKeyValue("Added", proof.createdAt.timeIntervalSinceReferenceDate.isFinite ? DateHelpers.fullDateTime(proof.createdAt) : "Unknown")

        if let intelligence = proof.intelligence?.normalizedForStorage() {
            addKeyValue("Proof completeness", intelligence.completeness.displayPercent)
            if let orderNumber = intelligence.orderNumber {
                addKeyValue("Order", orderNumber)
            }
            if let serialNumber = intelligence.serialNumber {
                addKeyValue("Serial", serialNumber)
            }
            for barcodeValue in intelligence.barcodeValues.prefix(3) {
                addKeyValue("Barcode", barcodeValue)
            }
            draw(intelligence.summary, font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 6)
        }

        if let text = ClaimTextLimits.optional(proof.extractedText, limit: ProofItemTextLimits.extractedText) {
            draw("Extracted text: \(String(text.prefix(900)))", font: .systemFont(ofSize: 9), color: .secondaryLabel, spacingAfter: 8)
        }

        if proof.type == .photo,
           let image = FileStorageService.shared.thumbnail(for: proof, maxPixelSize: 900) {
            addImage(image)
        }
    }

    func addFooter() {
        let footer = "Generated by DueProof. Proof files stay local unless you choose to share this packet."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.secondaryLabel
        ]
        footer.draw(
            in: CGRect(x: margin, y: pageSize.height - margin + 10, width: contentWidth, height: 20),
            withAttributes: attributes
        )
    }

    private func addImage(_ image: UIImage) {
        let maxHeight: CGFloat = 220
        let scale = min(contentWidth / image.size.width, maxHeight / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensureSpace(size.height + 14)
        image.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
        y += size.height + 14
    }

    private func draw(
        _ text: String,
        font: UIFont,
        color: UIColor,
        spacingAfter: CGFloat
    ) {
        let cleanText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumDrawCharacters))
        guard !cleanText.isEmpty else { return }

        let fragments = Self.fragments(for: cleanText, maximumCharacters: Self.maximumFragmentCharacters)
        for (index, fragment) in fragments.enumerated() {
            drawFragment(
                fragment,
                font: font,
                color: color,
                spacingAfter: index == fragments.count - 1 ? spacingAfter : 2
            )
        }
    }

    private func drawFragment(
        _ text: String,
        font: UIFont,
        color: UIColor,
        spacingAfter: CGFloat
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let rect = NSString(string: text).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        ensureSpace(ceil(rect.height) + spacingAfter)
        NSString(string: text).draw(
            in: CGRect(x: margin, y: y, width: contentWidth, height: ceil(rect.height)),
            withAttributes: attributes
        )
        y += ceil(rect.height) + spacingAfter
    }

    private static func fragments(for text: String, maximumCharacters: Int) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var fragments: [String] = []
        var current = ""

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                fragments.append(trimmed)
            }
            current = ""
        }

        for paragraph in normalized.components(separatedBy: .newlines) {
            let paragraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else {
                flushCurrent()
                continue
            }

            if current.count + paragraph.count + 1 > maximumCharacters {
                flushCurrent()
            }

            if paragraph.count <= maximumCharacters {
                current = current.isEmpty ? paragraph : "\(current)\n\(paragraph)"
                continue
            }

            flushCurrent()
            var remaining = paragraph[...]
            while !remaining.isEmpty {
                let end = remaining.index(
                    remaining.startIndex,
                    offsetBy: min(maximumCharacters, remaining.count)
                )
                let chunk = String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    fragments.append(chunk)
                }
                remaining = remaining[end...]
            }
        }

        flushCurrent()
        return fragments.isEmpty ? [text] : fragments
    }

    private func ensureSpace(_ height: CGFloat) {
        guard y + height > pageSize.height - margin else { return }
        context.beginPage()
        y = margin
    }
}
