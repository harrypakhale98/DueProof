import Foundation

enum CalendarExportError: LocalizedError {
    case missingDeadline

    var errorDescription: String? {
        switch self {
        case .missingDeadline:
            "This claim does not have a deadline to export."
        }
    }
}

final class CalendarExportService {
    static let shared = CalendarExportService()

    private init() {}

    func exportDeadline(for claim: Claim) throws -> URL {
        guard let deadline = claim.deadline else { throw CalendarExportError.missingDeadline }

        let end = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: deadline) ?? deadline
        let fileName = "\(safeFileName(claim.title))-deadline.ics"
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//DueProof//DueProof iOS//EN
        CALSCALE:GREGORIAN
        BEGIN:VEVENT
        UID:\(claim.id.uuidString)@dueproof.local
        DTSTAMP:\(icsDate(Date()))
        DTSTART:\(icsDate(deadline))
        DTEND:\(icsDate(end))
        SUMMARY:\(escape("DueProof: \(claim.title)"))
        DESCRIPTION:\(escape(description(for: claim)))
        END:VEVENT
        END:VCALENDAR
        """

        return try FileStorageService.shared.protectedTemporaryURL(
            fileName: fileName,
            data: Data(ics.utf8)
        )
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

    private func safeFileName(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = text.map { character -> Character in
            character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "-"
        }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "claim" : String(mapped)
    }
}
