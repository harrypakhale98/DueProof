import Foundation

enum DateHelpers {
    static let calendar = Calendar.autoupdatingCurrent

    static func daysUntil(_ date: Date, from referenceDate: Date = Date()) -> Int {
        guard isFinite(date), isFinite(referenceDate) else { return Int.max }
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func isPastDeadline(_ date: Date, referenceDate: Date = Date()) -> Bool {
        guard isFinite(date), isFinite(referenceDate) else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: referenceDate)
    }

    static func shortDate(_ date: Date) -> String {
        guard isFinite(date) else { return "Unknown date" }
        return date.formatted(.dateTime.month(.abbreviated).day().year(.defaultDigits))
    }

    static func fullDate(_ date: Date) -> String {
        guard isFinite(date) else { return "Unknown date" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    static func fullDateTime(_ date: Date) -> String {
        guard isFinite(date) else { return "Unknown date" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
    }

    static func defaultDeadline(for category: ClaimCategory, referenceDate: Date = Date()) -> Date? {
        let referenceDate = validDate(referenceDate) ?? Date()
        switch category {
        case .returnItem, .reimbursement, .rebate:
            return calendar.date(byAdding: .day, value: 30, to: referenceDate)
        case .giftCard:
            return nil
        case .warranty:
            return calendar.date(byAdding: .year, value: 1, to: referenceDate)
        case .subscription:
            return calendar.date(byAdding: .day, value: 1, to: referenceDate)
        case .renewal:
            return calendar.date(byAdding: .day, value: 7, to: referenceDate)
        case .document, .other:
            return calendar.date(byAdding: .day, value: 30, to: referenceDate)
        }
    }

    static func defaultReminderDate(for category: ClaimCategory, deadline: Date?, referenceDate: Date = Date()) -> Date? {
        let deadline = validDate(deadline)
        let referenceDate = validDate(referenceDate) ?? Date()
        switch category {
        case .giftCard:
            return calendar.date(byAdding: .day, value: 30, to: referenceDate)
        case .returnItem:
            return boundedReminder(before: deadline, days: 7, referenceDate: referenceDate)
        case .warranty:
            return boundedReminder(before: deadline, days: 30, referenceDate: referenceDate)
        case .reimbursement, .rebate, .document:
            return boundedReminder(before: deadline, days: 7, referenceDate: referenceDate)
        case .subscription:
            return boundedReminder(before: deadline, days: 1, referenceDate: referenceDate)
        case .renewal:
            return boundedReminder(before: deadline, days: 7, referenceDate: referenceDate)
        case .other:
            return boundedReminder(before: deadline, days: 7, referenceDate: referenceDate)
        }
    }

    static func deadlineText(for date: Date?) -> String {
        guard let date else { return "No deadline" }
        guard isFinite(date) else { return "Invalid deadline" }
        let days = daysUntil(date)
        if days < 0 {
            let overdueDays = abs(days)
            return overdueDays == 1 ? "Overdue by 1 day" : "Overdue by \(overdueDays) days"
        }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return shortDate(date)
    }

    private static func boundedReminder(before deadline: Date?, days: Int, referenceDate: Date) -> Date? {
        let deadline = validDate(deadline)
        let fallback = calendar.date(byAdding: .day, value: max(days, 1), to: referenceDate)

        guard let deadline else { return fallback }

        let oneHourFromNow = referenceDate.addingTimeInterval(60 * 60)
        let preferred = calendar.date(byAdding: .day, value: -days, to: deadline) ?? deadline

        if preferred > oneHourFromNow {
            return preferred
        }

        let oneHourBeforeDeadline = deadline.addingTimeInterval(-60 * 60)
        if oneHourBeforeDeadline > oneHourFromNow {
            return oneHourBeforeDeadline
        }

        return deadline > oneHourFromNow ? oneHourFromNow : nil
    }

    private static func validDate(_ date: Date?) -> Date? {
        guard let date, isFinite(date) else { return nil }
        return date
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}
