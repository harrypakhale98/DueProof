import Foundation

enum CalendarExportError: LocalizedError, Equatable {
    case missingDeadline
    case invalidDeadline

    var errorDescription: String? {
        switch self {
        case .missingDeadline:
            "This claim does not have a deadline to export."
        case .invalidDeadline:
            "This claim has an invalid deadline."
        }
    }
}

final class CalendarExportService {
    static let shared = CalendarExportService()

    private init() {}

    func exportDeadline(for claim: Claim) throws -> URL {
        guard let deadline = claim.deadline else { throw CalendarExportError.missingDeadline }
        guard deadline.timeIntervalSinceReferenceDate.isFinite else { throw CalendarExportError.invalidDeadline }

        let end = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: deadline) ?? deadline
        guard end.timeIntervalSinceReferenceDate.isFinite else { throw CalendarExportError.invalidDeadline }

        let title = normalizedTitle(for: claim)
        let fileName = "\(safeFileName(title))-deadline.ics"
        let ics = calendarText(lines: [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//DueProof//DueProof iOS//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VEVENT",
            "UID:\(claim.id.uuidString)@dueproof.local",
            "DTSTAMP:\(icsDate(Date()))",
            "DTSTART:\(icsDate(deadline))",
            "DTEND:\(icsDate(end))",
            "SUMMARY:\(escape("DueProof: \(title)"))",
            "DESCRIPTION:\(escape(description(for: claim)))",
            "END:VEVENT",
            "END:VCALENDAR"
        ])

        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: fileName,
            data: Data(ics.utf8)
        )
    }

    private func normalizedTitle(for claim: Claim) -> String {
        let title = ClaimTextLimits.required(claim.title, limit: ClaimTextLimits.title)
        return title.isEmpty ? "Claim" : title
    }

    private func description(for _: Claim) -> String {
        "DueProof reminder. Open DueProof to review private claim details and proof before sharing sensitive information."
    }

    private func icsDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func calendarText(lines: [String]) -> String {
        lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private func fold(_ line: String) -> String {
        let limit = 75
        guard line.utf8.count > limit else { return line }

        var foldedLines: [String] = []
        var currentLine = ""
        var currentByteCount = 0

        for character in line {
            let characterText = String(character)
            let characterByteCount = characterText.utf8.count

            if currentByteCount + characterByteCount > limit, !currentLine.isEmpty {
                foldedLines.append(currentLine)
                currentLine = " "
                currentByteCount = 1
            }

            currentLine.append(character)
            currentByteCount += characterByteCount
        }

        if !currentLine.isEmpty {
            foldedLines.append(currentLine)
        }

        return foldedLines.joined(separator: "\r\n")
    }

    private func safeFileName(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = text.map { character -> Character in
            character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "-"
        }
        let sanitized = String(mapped)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "claim" : String(sanitized.prefix(80))
    }
}
