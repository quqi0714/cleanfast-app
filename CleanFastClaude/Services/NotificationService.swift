import UserNotifications
import Foundation

/// 本地通知调度。一个会话最多有一条「目标达成」通知挂在 iOS 通知中心，
/// 状态切换/跳过/恢复会取消它，保证不会有过期通知到来。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private static let identifier = "cleanfast.targetReached"

    enum ScheduleResult: Equatable {
        case scheduled
        case notAuthorized
        case expired
        case failed
    }

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Foreground presentation

    /// 让通知在 App 前台时也能弹横幅 + 出声，否则会被静默吞掉。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: - Permission

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Schedule

    /// 安排一条「目标达成」通知。若已有 pending 同标识通知会先撤销。
    /// 如果用户尚未授权，会在此触发授权请求；拒绝则静默退出。
    func scheduleTargetReached(at fireDate: Date, title: String, body: String) async -> ScheduleResult {
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            let granted = await requestPermission()
            guard granted else { return .notAuthorized }
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return .notAuthorized
        }

        guard fireDate.timeIntervalSinceNow > 1 else { return .expired }

        cancelAll()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed
        }
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
