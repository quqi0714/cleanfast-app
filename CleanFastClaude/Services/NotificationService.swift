import UserNotifications
import Foundation

/// 本地通知调度。
/// - 手动模式：一个会话最多一条「目标达成」通知（`identifier`）。
/// - 自动模式：预排未来若干次窗口切换（`seriesIdentifiers`），
///   这样用户几天不打开 App 也能按节奏收到提醒。
/// 状态切换/跳过/恢复都会先取消全部，保证不会有过期通知到来。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private static let identifier = "cleanfast.targetReached"
    /// 自动模式一次最多预排的切换条数（16:8 下 ≈ 3 天），远低于系统 64 条上限。
    static let maxSeriesCount = 6
    private static let seriesIdentifiers: [String] =
        (0..<maxSeriesCount).map { "cleanfast.targetReached.series.\($0)" }
    private static let allIdentifiers: [String] = [identifier] + seriesIdentifiers

    enum ScheduleResult: Equatable {
        case scheduled
        case notAuthorized
        case expired
        case failed
    }

    /// 待预排的一条通知（自动模式的某次窗口切换）。
    struct PlannedNotification {
        let fireDate: Date
        let title: String
        let body: String
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

        do {
            try await center.add(request(identifier: Self.identifier,
                                         fireDate: fireDate, title: title, body: body))
            return .scheduled
        } catch {
            return .failed
        }
    }

    /// 批量预排一串通知（自动模式的未来切换）。先清空旧的，再逐条挂上；
    /// 已过期的条目被跳过，超出 `maxSeriesCount` 的截断。
    func scheduleSeries(_ items: [PlannedNotification]) async -> ScheduleResult {
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

        cancelAll()

        let valid = items
            .filter { $0.fireDate.timeIntervalSinceNow > 1 }
            .prefix(Self.seriesIdentifiers.count)
        guard !valid.isEmpty else { return .expired }

        var scheduledAny = false
        for (index, item) in valid.enumerated() {
            do {
                try await center.add(request(identifier: Self.seriesIdentifiers[index],
                                             fireDate: item.fireDate,
                                             title: item.title, body: item.body))
                scheduledAny = true
            } catch {
                // 单条失败不阻断其余条目
            }
        }
        return scheduledAny ? .scheduled : .failed
    }

    private func request(identifier: String, fireDate: Date, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers)
    }
}
