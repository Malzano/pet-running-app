import Foundation
import UserNotifications

@MainActor
protocol PlannerReminderScheduling {
    func requestPermission() async -> Bool
    func replace(plans: [PlannedActivity], now: Date) async -> String?
}

@MainActor
final class PlannerReminders: NSObject, PlannerReminderScheduling, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onOpenPlanner: (() -> Void)?
    static let prefix = "pawpace.plan."

    func installDelegate() { center.delegate = self }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func upcoming(_ plans: [PlannedActivity], now: Date) -> [PlannedActivity] {
        plans.filter { ($0.reminderDate ?? .distantPast) > now }
            .sorted { $0.reminderDate! < $1.reminderDate! }
    }

    func replace(plans: [PlannedActivity], now: Date) async -> String? {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) })
        let delivered = await center.deliveredNotifications()
        let activeIDs = Set(plans.filter { $0.completion == nil }.map { Self.prefix + $0.id.uuidString })
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter {
            $0.hasPrefix(Self.prefix) && !activeIDs.contains($0)
        })
        let upcoming = Self.upcoming(plans, now: now)
        guard !upcoming.isEmpty else { return nil }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return "Plans are saved. To receive reminders, allow notifications for PawPace in iPhone Settings."
        }
        do {
            for plan in upcoming.prefix(50) {
                let content = UNMutableNotificationContent()
                content.title = plan.isRestDay ? "A moment to rest" : "A little time to move"
                // Avoid placing fitness details or companion identities on the lock screen.
                content.body = "Your PawPace plan is coming up. Open your planner when you’re ready."
                content.sound = .default
                content.userInfo = ["plannerID": plan.id.uuidString]
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.reminderDate!)
                components.timeZone = .current
                try await center.add(UNNotificationRequest(identifier: Self.prefix + plan.id.uuidString,
                    content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
            return upcoming.count > 50 ? "Your next 50 reminders are scheduled. Open PawPace again to schedule later ones." : nil
        } catch { return "Your plans are saved, but reminders couldn’t be scheduled. Open Planner to retry." }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.notification.request.identifier.hasPrefix(Self.prefix) { onOpenPlanner?() }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
