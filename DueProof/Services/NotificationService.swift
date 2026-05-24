import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

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
        cancelReminder(for: claim)

        guard claim.status.isOpen, let reminderDate = claim.reminderDate, reminderDate > Date() else { return }

        do {
            guard try await requestAuthorizationIfNeeded() else { return }

            let content = UNMutableNotificationContent()
            content.title = "DueProof"
            content.body = notificationBody(for: claim)
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
            #if DEBUG
            print("DueProof could not schedule local notification: \(error.localizedDescription)")
            #endif
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

    private func identifier(for id: UUID) -> String {
        Self.reminderIdentifier(for: id)
    }

    private func notificationBody(for claim: Claim) -> String {
        let category = claim.category.displayName.lowercased()

        guard let deadline = claim.deadline else {
            return "Check your \(category) proof in DueProof."
        }

        let days = DateHelpers.daysUntil(deadline)
        if days == 0 {
            return "Your \(category) deadline is today."
        } else if days == 1 {
            return "Your \(category) deadline is tomorrow."
        } else if days > 1 {
            return "Your \(category) deadline is in \(days) days."
        } else {
            return "A \(category) deadline has passed."
        }
    }
}
