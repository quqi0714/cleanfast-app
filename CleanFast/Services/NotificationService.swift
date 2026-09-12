import UserNotifications
import Foundation

/// Small injectable boundary for deterministic tests of suspended system calls.
@MainActor
protocol NotificationCenterClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestPermission() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String]) async
}

@MainActor
private final class SystemNotificationCenterClient: NotificationCenterClient {
    let center = UNUserNotificationCenter.current()
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(identifiers: [String]) async {
        // The system may synchronously wait for its XPC service before returning.
        // Keep that wait away from the first frame and all UI interactions.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
                continuation.resume()
            }
        }
    }
}

/// Only the newest plan may write notifications. Submission and invalidation are
/// synchronous on MainActor; system writes drain in order even when an await is
/// not cancellable. A stale add is removed before the next plan may write.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let client: any NotificationCenterClient
    private var generation: UInt64 = 0
    private var scheduleTask: Task<ScheduleResult, Never>?

    private static let identifier = "cleanfast.targetReached"
    /// Existing product limit: six transitions, roughly three days for 16:8.
    static let maxSeriesCount = 6
    private static let seriesIdentifiers = (0..<maxSeriesCount).map {
        "cleanfast.targetReached.series.\($0)"
    }
    private static let allIdentifiers = [identifier] + seriesIdentifiers

    enum ScheduleResult: Equatable {
        case scheduled, notAuthorized, expired, failed, superseded
    }

    struct PlannedNotification {
        let fireDate: Date
        let title: String
        let body: String
    }

    private override init() {
        let system = SystemNotificationCenterClient()
        client = system
        super.init()
        system.center.delegate = self
    }

    init(client: any NotificationCenterClient) {
        self.client = client
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [.banner, .sound] }

    func requestPermission() async -> Bool { await client.requestPermission() }

    @discardableResult
    func scheduleTargetReached(at fireDate: Date, title: String, body: String) -> Task<ScheduleResult, Never> {
        replacePlan([request(identifier: Self.identifier, fireDate: fireDate, title: title, body: body)])
    }

    @discardableResult
    func scheduleSeries(_ items: [PlannedNotification]) -> Task<ScheduleResult, Never> {
        let valid = items.filter { $0.fireDate.timeIntervalSinceNow > 1 }.prefix(Self.maxSeriesCount)
        return replacePlan(valid.enumerated().map { index, item in
            request(identifier: Self.seriesIdentifiers[index], fireDate: item.fireDate,
                    title: item.title, body: item.body)
        })
    }

    private func replacePlan(_ requests: [UNNotificationRequest]) -> Task<ScheduleResult, Never> {
        generation &+= 1
        let token = generation
        let previous = scheduleTask
        previous?.cancel()
        let next = Task { @MainActor in
            // Cancellation is cooperative. Wait for a possible in-flight add and
            // its cleanup before reusing the same stable notification identifiers.
            if let previous { _ = await previous.value }
            guard self.isCurrent(token) else { return ScheduleResult.superseded }
            await self.client.removePending(identifiers: Self.allIdentifiers)
            guard self.isCurrent(token) else { return .superseded }
            let status = await self.client.authorizationStatus()
            guard self.isCurrent(token) else { return .superseded }
            switch status {
            case .notDetermined:
                let granted = await self.client.requestPermission()
                guard self.isCurrent(token) else { return .superseded }
                guard granted else { return .notAuthorized }
            case .authorized, .provisional, .ephemeral: break
            default: return .notAuthorized
            }

            var scheduledAny = false
            var attemptedAny = false
            for request in requests {
                guard self.isCurrent(token) else { return .superseded }
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let date = trigger.nextTriggerDate(), date.timeIntervalSinceNow > 1 else { continue }
                attemptedAny = true
                do {
                    try await self.client.add(request)
                    scheduledAny = true
                } catch { /* A failed item does not prevent other valid items. */ }
                guard self.isCurrent(token) else {
                    // The next writer still awaits this task, so cleanup cannot
                    // delete a newer plan. Covers cancellation during center.add.
                    await self.client.removePending(identifiers: Self.allIdentifiers)
                    return .superseded
                }
            }
            return scheduledAny ? .scheduled : (attemptedAny ? .failed : .expired)
        }
        scheduleTask = next
        return next
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        token == generation && !Task.isCancelled
    }

    private func request(identifier: String, fireDate: Date, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        return UNNotificationRequest(identifier: identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    func cancelAll() {
        generation &+= 1
        let previous = scheduleTask
        previous?.cancel()
        // Invalidation is immediate; potentially slow system cleanup is ordered
        // behind the old writer without blocking the caller or the main thread.
        scheduleTask = Task { @MainActor in
            if let previous { _ = await previous.value }
            await self.client.removePending(identifiers: Self.allIdentifiers)
            return .superseded
        }
    }

    /// Waits for unavoidable system calls and stale-request cleanup to settle.
    func waitUntilIdle() async { _ = await scheduleTask?.value }
}
