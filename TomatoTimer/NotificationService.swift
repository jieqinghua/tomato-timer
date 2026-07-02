import Foundation
import UserNotifications

protocol NotificationService: AnyObject {
    func requestAuthorizationIfNeeded()
    func sendPhaseFinishedNotification(nextPhase: TimerPhase)
}

final class UserNotificationService: NSObject, NotificationService, UNUserNotificationCenterDelegate {
    private var hasRequestedAuthorization = false
    private let notificationCenter: UNUserNotificationCenter

    override init() {
        self.notificationCenter = .current()
        super.init()
        notificationCenter.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in
        }
    }

    func sendPhaseFinishedNotification(nextPhase: TimerPhase) {
        let content = UNMutableNotificationContent()

        switch nextPhase {
        case .focus:
            content.title = "回到专注"
            content.body = "休息结束，开始下一轮番茄钟。"
        case .rest:
            content.title = "该休息了"
            content.body = "专注完成，起来活动一下。"
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
