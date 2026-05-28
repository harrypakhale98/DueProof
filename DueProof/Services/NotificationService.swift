import Foundation
import OSLog
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private static let logger = Logger(subsystem: "com.hardik.dueproof", category: "Notifications")

    private init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        @unknown default:
            return false
        }
    }

    func scheduleReminder(for claim: Claim) async {
        guard Self.canScheduleReminder(for: claim) else {
            cancelReminder(for: claim)
            return
        }
        guard let reminderDate = claim.reminderDate else { return }

        do {
            guard try await requestAuthorizationIfNeeded() else {
                cancelReminder(for: claim)
                return
            }
            cancelReminder(for: claim)

            let content = UNMutableNotificationContent()
            content.title = "DueProof"
            content.body = Self.notificationBody(for: claim, referenceDate: reminderDate)
            content.sound = .default
            content.userInfo = ["claimID": claim.id.uuidString]

            let components = Calendar.autoupdatingCurrent.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminderDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(for: claim.id),
                content: content,
                trigger: trigger
            )

            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.error("Could not schedule local notification: \(error.localizedDescription, privacy: .private)")
        }
    }

    func cancelReminder(for claim: Claim) {
        cancelReminder(for: claim.id)
    }

    func cancelReminder(for claimID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier(for: claimID)])
    }

    static func reminderIdentifier(for id: UUID) -> String {
        "dueproof.claim.\(id.uuidString)"
    }

    static func canScheduleReminder(for claim: Claim, referenceDate: Date = Date()) -> Bool {
        guard isFinite(referenceDate) else { return false }
        guard claim.status.isOpen,
              let reminderDate = claim.reminderDate,
              isFinite(reminderDate),
              reminderDate > referenceDate
        else {
            return false
        }

        if let deadline = claim.deadline {
            guard isFinite(deadline), reminderDate <= deadline else { return false }
        }

        return true
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func validDate(_ date: Date?) -> Date? {
        guard let date, isFinite(date) else {
            return nil
        }
        return date
    }

    private static func hasInvalidDate(_ date: Date?) -> Bool {
        guard let date else { return false }
        return !isFinite(date)
    }

    private static func normalizedDeadline(for claim: Claim) -> Date? {
        if hasInvalidDate(claim.deadline) {
            return nil
        }
        return validDate(claim.deadline)
    }

    private static func normalizedReferenceDate(_ date: Date) -> Date {
        isFinite(date) ? date : Date()
    }

    private func identifier(for id: UUID) -> String {
        Self.reminderIdentifier(for: id)
    }

    static func notificationBody(for claim: Claim, referenceDate: Date = Date()) -> String {
        let category = claim.category.displayName.lowercased()

        guard let deadline = normalizedDeadline(for: claim) else {
            return "Check your \(category) proof in DueProof."
        }

        let days = DateHelpers.daysUntil(deadline, from: normalizedReferenceDate(referenceDate))
        if days == 0 {
            return "Your \(category) deadline is today."
        } else if days == 1 {
            return "Your \(category) deadline is tomorrow."
        } else if days > 1, days < Int.max {
            return "Your \(category) deadline is in \(days) days."
        } else if days > 1 {
            return "Check your \(category) proof in DueProof."
        } else {
            return "A \(category) deadline has passed."
        }
    }
}
