import Foundation
import SwiftUI
import Combine
import WidgetKit

@MainActor
final class FastingTimerViewModel: ObservableObject {
    @Published private(set) var targetMinutes: Int           // 断食目标（进食窗口 = 24h − 此值）
    @Published private(set) var state: FastingState
    @Published private(set) var session: FastingSession?
    @Published private(set) var skippedDateString: String?
    @Published private(set) var timingMode: TimingMode
    @Published private(set) var manualStartNeedsTimeChoice: Bool
    @Published private(set) var now: Date = Date()

    private let persistence: PersistenceService
    private let schedule: ScheduleService
    private var ticker: AnyCancellable?

    /// 测试可注入独立 `PersistenceService` 和 `ScheduleService`，
    /// 并通过 `startTicker: false` 跳过 1Hz 轮询。
    /// `schedule` 用 Optional + 内部构造默认值，避免默认参数在非隔离上下文求值
    /// `Calendar.current` 触发 Swift 6 严格并发警告。
    init(
        persistence: PersistenceService = .shared,
        schedule: ScheduleService? = nil,
        startTicker autoStartTicker: Bool = true
    ) {
        self.persistence = persistence
        self.schedule = schedule ?? ScheduleService()
        self.targetMinutes = persistence.targetMinutes
        self.state = persistence.state
        self.session = persistence.session
        self.skippedDateString = persistence.skippedDateString
        self.timingMode = persistence.timingMode
        self.manualStartNeedsTimeChoice = persistence.manualStartNeedsTimeChoice
        rehydrate()
        if autoStartTicker {
            startTicker()
        }
    }

    /// 进食窗口分钟数：永远等于 24h − 断食时长，由设置入口处的范围（1...23）保证为正。
    var eatingTargetMinutes: Int { max(0, 24 * 60 - targetMinutes) }

    // MARK: - Lifecycle

    func rehydrate() {
        now = Date()
        var didResetState = false
        if state == .skipped {
            let today = schedule.dayString(for: now)
            if skippedDateString != today {
                if timingMode == .automatic, let resumeDate = automaticResumeStartDate() {
                    skippedDateString = nil
                    persistence.skippedDateString = nil
                    if now >= resumeDate {
                        startFasting(at: resumeDate)
                        advanceAutomaticSessionIfNeeded(at: now)
                        return
                    } else {
                        state = .notStarted
                        persistence.state = state
                        session = nil
                        persistence.session = nil
                        didResetState = true
                    }
                } else {
                    skippedDateString = nil
                    persistence.skippedDateString = nil
                    state = .notStarted
                    persistence.state = state
                    session = nil
                    persistence.session = nil
                    persistence.automaticResumeDateString = nil
                    if timingMode == .manual {
                        manualStartNeedsTimeChoice = true
                        persistence.manualStartNeedsTimeChoice = true
                    }
                    didResetState = true
                }
            }
        }
        if resumePendingAutomaticStartIfNeeded(at: now) {
            return
        }
        if (state == .fasting || state == .eating), session == nil {
            state = .notStarted
            persistence.state = state
            didResetState = true
        }
        if state == .notStarted || state == .skipped {
            session = nil
            persistence.session = nil
        }
        let didAdvance = advanceAutomaticSessionIfNeeded(at: now)
        if !didAdvance { refreshNotificationScheduleForCurrentState() }
        if didResetState {
            reloadWidgets()
        }
    }

    private func startTicker() {
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick(at: date)
            }
    }

    private func tick(at date: Date) {
        // 仅在有进行中会话、或自动模式有等待恢复的情况下发布 `now`。
        // 未开始 / 已跳过手动模式下 `now` 不影响任何 UI 显示，
        // 静音 @Published 可以避免 HomeView 每秒空转一次 body。
        let needsPublish = session != nil
            || (timingMode == .automatic && persistence.automaticResumeDateString != nil)
        if needsPublish {
            now = date
        }
        if resumePendingAutomaticStartIfNeeded(at: date) {
            return
        }
        advanceAutomaticSessionIfNeeded(at: date)
    }

    // MARK: - Derived

    var fastingDuration: TimeInterval { TimeInterval(targetMinutes * 60) }
    var eatingDuration: TimeInterval  { TimeInterval(eatingTargetMinutes * 60) }

    /// 当前会话的目标时长。Session 的 targetDuration 会被设置改动**立即同步**
    /// （见 `updateTargetMinutes`），所以这里直接读 session 即可，圆环 / 副位 /
    /// 文案 / 通知共用一个源头，不会打架。
    var activeTargetDuration: TimeInterval {
        session?.targetDuration ?? fastingDuration
    }

    /// 当前会话已经过的时间（始终累加，过目标后继续）。
    var elapsed: TimeInterval {
        guard let session else { return 0 }
        return max(0, now.timeIntervalSince(session.startDate))
    }

    /// 距目标剩余时间（达成后为负）。
    var remaining: TimeInterval {
        guard let session else { return 0 }
        return session.targetDuration - elapsed
    }

    var overshoot: TimeInterval { max(0, -remaining) }

    var hasReachedTarget: Bool {
        guard session != nil else { return false }
        return remaining <= 0
    }

    /// 圆环进度，达到 1.0 后保持 1.0。
    var progress: Double {
        guard let session, session.targetDuration > 0 else { return 0 }
        return min(max(elapsed / session.targetDuration, 0), 1)
    }

    var sessionEndDate: Date? { session?.targetEndDate }

    var canAdjustCurrentStartTime: Bool {
        timingMode == .manual && (state == .fasting || state == .eating) && session != nil
    }

    /// 仅在断食时有意义：当前身体阶段。
    var currentStage: FastingStage {
        FastingStage.from(elapsedSeconds: elapsed, hasReachedTarget: hasReachedTarget)
    }

    // MARK: - Actions

    func startFasting(at date: Date = Date()) {
        let startDate = min(date, Date())
        let s = FastingSession(startDate: startDate, targetDuration: fastingDuration)
        session = s
        state = .fasting
        skippedDateString = nil
        manualStartNeedsTimeChoice = false
        persistence.session = s
        persistence.state = state
        persistence.skippedDateString = nil
        persistence.manualStartNeedsTimeChoice = false
        persistence.automaticResumeDateString = nil
        if timingMode == .automatic {
            persistence.automaticFastingStartMinute = schedule.minuteOfDay(for: startDate)
        }
        // 在 ticker 节流的前提下，session 刚建立时主动刷新 `now`，
        // 避免大数字第一秒显示陈旧 elapsed
        now = Date()
        scheduleSessionNotification()
        reloadWidgets()
    }

    /// 结束断食 → 自动进入进食窗口（不回到 notStarted）。
    func endFasting(at date: Date = Date()) {
        startEating(at: date)
    }

    func startEating(at date: Date = Date()) {
        let s = FastingSession(startDate: date, targetDuration: eatingDuration)
        session = s
        state = .eating
        persistence.session = s
        persistence.state = state
        // 同上：ticker 节流时手动刷新 `now`，让 elapsed 立即正确
        now = Date()
        scheduleSessionNotification()
        reloadWidgets()
    }

    func skipToday() {
        let today = schedule.dayString(for: Date())
        if timingMode == .automatic {
            ensureAutomaticFastingStartAnchor(defaultingTo: Date())
        }
        skippedDateString = today
        persistence.skippedDateString = today
        state = .skipped
        persistence.state = state
        session = nil
        persistence.session = nil
        cancelSessionNotifications()
        if timingMode == .manual {
            manualStartNeedsTimeChoice = true
            persistence.manualStartNeedsTimeChoice = true
            persistence.automaticResumeDateString = nil
        } else {
            if persistence.automaticFastingStartMinute != nil {
                persistence.automaticResumeDateString = schedule.nextDayString(after: Date())
                scheduleAutomaticResumeNotificationIfNeeded()
            }
        }
        reloadWidgets()
    }

    func resumeToday() {
        skippedDateString = nil
        persistence.skippedDateString = nil
        state = .notStarted
        persistence.state = state
        session = nil
        persistence.session = nil
        persistence.automaticResumeDateString = nil
        if timingMode == .manual {
            manualStartNeedsTimeChoice = true
            persistence.manualStartNeedsTimeChoice = true
        }
        cancelSessionNotifications()
        reloadWidgets()
    }

    /// 设置页打开通知后调用，给当前进行中的 session 重新挂上通知。
    func refreshNotificationsFromCurrentSession() {
        refreshNotificationScheduleForCurrentState()
    }

    func updateTimingMode(_ mode: TimingMode) {
        timingMode = mode
        persistence.timingMode = mode
        if mode == .automatic {
            manualStartNeedsTimeChoice = false
            persistence.manualStartNeedsTimeChoice = false
            ensureAutomaticFastingStartAnchor(defaultingTo: now)
            if state == .skipped, persistence.automaticFastingStartMinute != nil {
                persistence.automaticResumeDateString = schedule.nextDayString(after: now)
            }
            let didAdvance = advanceAutomaticSessionIfNeeded(at: now)
            if !didAdvance { refreshNotificationScheduleForCurrentState() }
        } else {
            persistence.automaticResumeDateString = nil
            if state == .skipped {
                manualStartNeedsTimeChoice = true
                persistence.manualStartNeedsTimeChoice = true
            }
            refreshNotificationScheduleForCurrentState()
        }
        reloadWidgets()
    }

    func adjustCurrentSessionStartDate(_ date: Date) {
        guard canAdjustCurrentStartTime, var current = session else { return }
        current.startDate = min(date, Date())
        session = current
        persistence.session = current
        now = Date()
        refreshNotificationScheduleForCurrentState()
        reloadWidgets()
    }

    private func automaticResumeStartDate() -> Date? {
        guard let resumeDay = persistence.automaticResumeDateString,
              let startMinute = persistence.automaticFastingStartMinute
        else { return nil }
        return schedule.date(forDayString: resumeDay, minuteOfDay: startMinute)
    }

    private func resumePendingAutomaticStartIfNeeded(at referenceDate: Date) -> Bool {
        guard timingMode == .automatic,
              state == .notStarted,
              let resumeDate = automaticResumeStartDate(),
              referenceDate >= resumeDate
        else { return false }

        startFasting(at: resumeDate)
        advanceAutomaticSessionIfNeeded(at: referenceDate)
        return true
    }

    private func ensureAutomaticFastingStartAnchor(defaultingTo fallbackDate: Date? = nil) {
        guard timingMode == .automatic else { return }

        guard let session else {
            if persistence.automaticFastingStartMinute == nil, let fallbackDate {
                persistence.automaticFastingStartMinute = schedule.minuteOfDay(for: fallbackDate)
            }
            return
        }

        let fastingStart: Date
        switch state {
        case .fasting:
            fastingStart = session.startDate
        case .eating:
            fastingStart = session.startDate.addingTimeInterval(-fastingDuration)
        default:
            return
        }
        persistence.automaticFastingStartMinute = schedule.minuteOfDay(for: fastingStart)
    }

    // MARK: - Notification helpers

    private func scheduleSessionNotification() {
        guard persistence.notificationEnabled, let session else {
            cancelSessionNotifications()
            return
        }
        let title: String
        let body: String
        switch state {
        case .fasting:
            if timingMode == .automatic {
                title = "已进入进食窗口"
                body = "断食窗口已经结束，时钟会继续帮你记录这一段。"
            } else {
                title = "辛苦啦"
                body = "你的断食目标已达成，可以开始温和进食了。"
            }
        case .eating:
            if timingMode == .automatic {
                title = "已回到断食窗口"
                body = "进食窗口已经结束，新一段断食已经开始。"
            } else {
                title = "差不多到时间啦"
                body = "进食窗口建议时长已到，准备好就可以开始下一轮断食。"
            }
        default:
            cancelSessionNotifications()
            return
        }
        let endDate = session.targetEndDate
        guard endDate.timeIntervalSinceNow > 1 else {
            cancelSessionNotifications()
            return
        }
        Task { @MainActor in
            let result = await NotificationService.shared.scheduleTargetReached(
                at: endDate, title: title, body: body
            )
            if result == .notAuthorized {
                persistence.notificationEnabled = false
            }
        }
    }

    private func scheduleAutomaticResumeNotificationIfNeeded() {
        guard persistence.notificationEnabled,
              let resumeDate = automaticResumeStartDate()
        else { return }

        let fireDate = resumeDate.addingTimeInterval(fastingDuration)
        guard fireDate.timeIntervalSinceNow > 1 else {
            cancelSessionNotifications()
            return
        }

        Task { @MainActor in
            let result = await NotificationService.shared.scheduleTargetReached(
                at: fireDate,
                title: "已进入进食窗口",
                body: "断食窗口已经结束，时钟会继续帮你记录这一段。"
            )
            if result == .notAuthorized {
                persistence.notificationEnabled = false
            }
        }
    }

    private func cancelSessionNotifications() {
        NotificationService.shared.cancelAll()
    }

    private func refreshNotificationScheduleForCurrentState() {
        if state == .fasting || state == .eating {
            scheduleSessionNotification()
        } else if timingMode == .automatic, automaticResumeStartDate() != nil {
            scheduleAutomaticResumeNotificationIfNeeded()
        } else {
            cancelSessionNotifications()
        }
    }

    func updateTargetMinutes(_ minutes: Int) {
        // 范围在调用方（设置 / 引导）就已经控制在 1...23 小时，这里再夹一道兜底。
        let clamped = min(max(minutes, 60), 23 * 60)
        targetMinutes = clamped
        persistence.targetMinutes = clamped

        // 把改动立即同步到进行中的会话：圆环、达成判断、通知一致跟着变。
        if var current = session {
            switch state {
            case .fasting: current.targetDuration = fastingDuration
            case .eating:  current.targetDuration = eatingDuration
            default:       break
            }
            session = current
            persistence.session = current
        }
        if timingMode == .automatic {
            let didAdvance = advanceAutomaticSessionIfNeeded(at: now)
            if !didAdvance { refreshNotificationScheduleForCurrentState() }
        } else {
            refreshNotificationScheduleForCurrentState()
        }
        reloadWidgets()
    }

    @discardableResult
    private func advanceAutomaticSessionIfNeeded(at referenceDate: Date) -> Bool {
        guard timingMode == .automatic,
              state == .fasting || state == .eating,
              var current = session
        else { return false }

        var nextState = state
        var didAdvance = false
        var guardCount = 0

        while referenceDate >= current.targetEndDate && guardCount < 200 {
            let nextStart = current.targetEndDate
            switch nextState {
            case .fasting:
                nextState = .eating
                current = FastingSession(startDate: nextStart, targetDuration: eatingDuration)
            case .eating:
                nextState = .fasting
                current = FastingSession(startDate: nextStart, targetDuration: fastingDuration)
            default:
                return false
            }
            didAdvance = true
            guardCount += 1
        }

        guard didAdvance else { return false }
        state = nextState
        session = current
        persistence.state = nextState
        persistence.session = current
        scheduleSessionNotification()
        reloadWidgets()
        return true
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
