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
    /// 达到求评里程碑时置 true，由 HomeView 消费（调系统评分弹窗后回调 markReviewRequestHandled）。
    @Published private(set) var pendingReviewRequest: Bool = false

    private let persistence: PersistenceService
    private let schedule: ScheduleService
    private let notifications: NotificationService
    private var notificationObserver: Task<Void, Never>?
    private var notificationRevision: UInt64 = 0
    private var permissionTask: Task<Bool, Never>?
    private var permissionRevision: UInt64 = 0
    private var ticker: AnyCancellable?

    /// 测试可注入独立 `PersistenceService` 和 `ScheduleService`，
    /// 并通过 `startTicker: false` 跳过 1Hz 轮询。
    /// `schedule` 用 Optional + 内部构造默认值，避免默认参数在非隔离上下文求值
    /// `Calendar.current` 触发 Swift 6 严格并发警告。
    init(
        persistence: PersistenceService = .shared,
        schedule: ScheduleService? = nil,
        startTicker autoStartTicker: Bool = true,
        notifications: NotificationService? = nil
    ) {
        self.persistence = persistence
        self.schedule = schedule ?? ScheduleService()
        self.notifications = notifications ?? .shared
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
        // 跳过状态跨午夜要失效（App 整夜留在前台时 scenePhase 不变化，
        // 只能靠 tick 兜底触发 rehydrate）。
        if state == .skipped, skippedDateString != schedule.dayString(for: date) {
            rehydrate()
            return
        }
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
        var startDate = min(date, Date())
        // 从进食态重新开始断食时，新断食的开始不允许早于当前进食段的开始，
        // 否则会出现"断食开始于进食之前"的倒挂时间线。
        if state == .eating, let current = session {
            startDate = max(startDate, current.startDate)
        }
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
        var startDate = min(date, Date())
        // 结束断食时，进食的开始不允许早于这段断食的开始（时间线倒挂保护）。
        if state == .fasting, let current = session {
            startDate = max(startDate, current.startDate)
        }
        // 手动结束一段「已达标」的断食 → 记一次完成（求评里程碑依据）。
        if state == .fasting, hasReachedTarget {
            recordCompletedFast()
        }
        let s = FastingSession(startDate: startDate, targetDuration: eatingDuration)
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
        guard persistence.notificationEnabled, let session,
              state == .fasting || state == .eating
        else {
            cancelSessionNotifications()
            return
        }

        // 自动模式：预排未来若干次窗口切换（用户几天不开 App 也能持续收到提醒）。
        if timingMode == .automatic {
            scheduleAutomaticSeries(
                sessionStart: session.startDate,
                sessionDuration: session.targetDuration,
                sessionIsFasting: state == .fasting
            )
            return
        }

        // 手动模式：只挂"当前目标达成"这一条。
        let title: String
        let body: String
        if state == .fasting {
            title = String(localized: "辛苦啦")
            body = String(localized: "你的断食目标已达成，可以开始温和进食了。")
        } else {
            title = String(localized: "差不多到时间啦")
            body = String(localized: "进食窗口建议时长已到，准备好就可以开始下一轮断食。")
        }
        let endDate = session.targetEndDate
        guard endDate.timeIntervalSinceNow > 1 else {
            cancelSessionNotifications()
            return
        }
        observeNotificationResult(notifications.scheduleTargetReached(
            at: endDate, title: title, body: body
        ))
    }

    private func scheduleAutomaticResumeNotificationIfNeeded() {
        guard persistence.notificationEnabled,
              let resumeDate = automaticResumeStartDate()
        else { return }
        // 恢复后的第一段是断食：以 resumeDate 为起点的断食会话推出整串切换。
        scheduleAutomaticSeries(
            sessionStart: resumeDate,
            sessionDuration: fastingDuration,
            sessionIsFasting: true
        )
    }

    /// 把"当前会话之后的 N 次切换"转成通知系列挂给系统。
    private func scheduleAutomaticSeries(
        sessionStart: Date,
        sessionDuration: TimeInterval,
        sessionIsFasting: Bool
    ) {
        let transitions = Self.upcomingAutomaticTransitions(
            sessionStart: sessionStart,
            sessionDuration: sessionDuration,
            sessionIsFasting: sessionIsFasting,
            fastingDuration: fastingDuration,
            eatingDuration: eatingDuration,
            count: NotificationService.maxSeriesCount
        )
        let items = transitions.map { transition in
            NotificationService.PlannedNotification(
                fireDate: transition.fireDate,
                title: transition.endedWindowIsFasting
                    ? String(localized: "已进入进食窗口")
                    : String(localized: "已回到断食窗口"),
                body: transition.endedWindowIsFasting
                    ? String(localized: "断食窗口已经结束，时钟会继续帮你记录这一段。")
                    : String(localized: "进食窗口已经结束，新一段断食已经开始。")
            )
        }
        observeNotificationResult(notifications.scheduleSeries(items))
    }

    /// 自动模式：从给定会话推出接下来 `count` 次窗口切换。
    /// 纯函数（只做 Date 数学），返回每次切换的触发时刻 + 刚结束的是否断食窗口。
    static func upcomingAutomaticTransitions(
        sessionStart: Date,
        sessionDuration: TimeInterval,
        sessionIsFasting: Bool,
        fastingDuration: TimeInterval,
        eatingDuration: TimeInterval,
        count: Int
    ) -> [(fireDate: Date, endedWindowIsFasting: Bool)] {
        guard count > 0, fastingDuration > 0, eatingDuration > 0 else { return [] }
        var result: [(fireDate: Date, endedWindowIsFasting: Bool)] = []
        var windowEnd = sessionStart.addingTimeInterval(sessionDuration)
        var windowIsFasting = sessionIsFasting
        for _ in 0..<count {
            result.append((windowEnd, windowIsFasting))
            windowIsFasting.toggle()
            windowEnd = windowEnd.addingTimeInterval(windowIsFasting ? fastingDuration : eatingDuration)
        }
        return result
    }

    private func observeNotificationResult(_ task: Task<NotificationService.ScheduleResult, Never>) {
        notificationRevision &+= 1
        let token = notificationRevision
        notificationObserver?.cancel()
        notificationObserver = Task { @MainActor [weak self] in
            let result = await task.value
            guard let self, !Task.isCancelled, token == self.notificationRevision else { return }
            if result == .notAuthorized { self.persistence.notificationEnabled = false }
        }
    }

    private func cancelSessionNotifications() {
        notificationRevision &+= 1
        notificationObserver?.cancel()
        notifications.cancelAll()
    }

    /// The latest switch choice owns permission completion, including when the
    /// system prompt returns after the user has switched reminders off.
    @discardableResult
    func setNotificationsEnabled(_ enabled: Bool) -> Task<Bool, Never> {
        permissionRevision &+= 1
        let token = permissionRevision
        permissionTask?.cancel()
        persistence.notificationEnabled = false
        cancelSessionNotifications()
        guard enabled else { return Task { false } }
        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, token == self.permissionRevision else { return false }
            let granted = await self.notifications.requestPermission()
            guard !Task.isCancelled, token == self.permissionRevision else { return false }
            self.persistence.notificationEnabled = granted
            if granted { self.refreshNotificationScheduleForCurrentState() }
            return granted
        }
        permissionTask = task
        return task
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
              let current = session
        else { return false }

        let result = Self.advanceAutomaticCycle(
            startDate: current.startDate,
            currentDuration: current.targetDuration,
            isFasting: state == .fasting,
            fastingDuration: fastingDuration,
            eatingDuration: eatingDuration,
            at: referenceDate
        )

        guard result.cyclesAdvanced > 0 else { return false }

        // 自动模式「实时」走完一段断食（单次推进、断食→进食）也记一次完成；
        // 离开多日后的多周期追赶不计（用户并未真的经历那些窗口）。
        if result.cyclesAdvanced == 1, state == .fasting, !result.isFasting {
            recordCompletedFast()
        }

        let nextState: FastingState = result.isFasting ? .fasting : .eating
        let nextSession = FastingSession(
            startDate: result.startDate,
            targetDuration: result.duration
        )
        state = nextState
        session = nextSession
        persistence.state = nextState
        persistence.session = nextSession
        scheduleSessionNotification()
        reloadWidgets()
        return true
    }

    /// 自动模式循环推进的纯函数实现（无副作用，仅算 Date 数学）。
    ///
    /// **MIRROR**：必须与 `WidgetSnapshot.advanceAutomaticCycle` 保持算法等价。
    /// 改动这里时同步改 widget 那一份，反之亦然（widget target 无法被测试 target
    /// 引用，跨 target 等价只能靠人工同步）。
    /// 单元测试 `advanceAutomaticCycle_matchesPinnedReference` 用独立的参考实现
    /// 钉住这一份的行为，防止单边被改坏。
    static func advanceAutomaticCycle(
        startDate: Date,
        currentDuration: TimeInterval,
        isFasting: Bool,
        fastingDuration: TimeInterval,
        eatingDuration: TimeInterval,
        at referenceDate: Date
    ) -> (startDate: Date, duration: TimeInterval, isFasting: Bool, cyclesAdvanced: Int) {
        let unchanged = (startDate, currentDuration, isFasting, 0)
        let period = fastingDuration + eatingDuration
        guard currentDuration.isFinite, currentDuration > 0,
              fastingDuration.isFinite, fastingDuration > 0,
              eatingDuration.isFinite, eatingDuration > 0, period.isFinite,
              referenceDate.timeIntervalSince(startDate).isFinite,
              referenceDate >= startDate.addingTimeInterval(currentDuration) else {
            return unchanged
        }

        // Preserve the current session's duration, even if the plan changed after it began.
        var nextStart = startDate.addingTimeInterval(currentDuration)
        var nextFasting = !isFasting
        var nextDuration = nextFasting ? fastingDuration : eatingDuration
        let completePairs = floor(referenceDate.timeIntervalSince(nextStart) / period)
        nextStart = nextStart.addingTimeInterval(completePairs * period)
        // Saturation only matters for malformed, astronomical dates; a catch-up must
        // never look like one transition and incorrectly award a completed-fast milestone.
        var cycles = completePairs < Double(Int.max / 4) ? 1 + Int(completePairs) * 2 : Int.max - 1
        if referenceDate >= nextStart.addingTimeInterval(nextDuration) {
            nextStart = nextStart.addingTimeInterval(nextDuration)
            nextFasting.toggle()
            nextDuration = nextFasting ? fastingDuration : eatingDuration
            cycles += 1
        }

        return (nextStart, nextDuration, nextFasting, cycles)
    }

    // MARK: - App Store review milestones

    /// 求评里程碑：第 3 / 10 / 30 次达成断食目标。
    /// 时机选在刚完成目标的高光时刻；系统自身限制每 365 天最多真正弹出 3 次。
    private static let reviewMilestones: Set<Int> = [3, 10, 30]

    private func recordCompletedFast() {
        let count = persistence.completedFastCount + 1
        persistence.completedFastCount = count
        if Self.reviewMilestones.contains(count),
           persistence.reviewRequestedForCount < count {
            pendingReviewRequest = true
        }
    }

    /// HomeView 调用系统评分请求后回调，落盘防重复。
    func markReviewRequestHandled() {
        pendingReviewRequest = false
        persistence.reviewRequestedForCount = persistence.completedFastCount
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
