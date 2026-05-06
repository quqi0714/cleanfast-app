//
//  CleanFastClaudeTests.swift
//  CleanFastClaudeTests
//
//  Covers FastingTimerViewModel state machine + automatic-mode resume mechanic.
//  Each test gets a fresh PersistenceService backed by an isolated UserDefaults suite,
//  so tests don't pollute each other or the App Group.
//

import Testing
import Foundation
@testable import CleanFastClaude

@MainActor
struct CleanFastClaudeTests {

    // MARK: - Test helpers

    /// Builds a FastingTimerViewModel with an isolated UserDefaults suite + ticker disabled.
    /// All persistence keys can be pre-seeded via the optional params.
    private func makeVM(
        targetMinutes: Int = 16 * 60,
        timingMode: TimingMode = .manual,
        state: FastingState = .notStarted,
        session: FastingSession? = nil,
        skippedDateString: String? = nil,
        notificationEnabled: Bool = false,
        manualStartNeedsTimeChoice: Bool = false,
        automaticFastingStartMinute: Int? = nil,
        automaticResumeDateString: String? = nil
    ) -> (vm: FastingTimerViewModel, defaults: UserDefaults) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let p = PersistenceService(defaults: defaults)
        p.targetMinutes = targetMinutes
        p.timingMode = timingMode
        p.state = state
        p.session = session
        p.skippedDateString = skippedDateString
        p.notificationEnabled = notificationEnabled
        p.manualStartNeedsTimeChoice = manualStartNeedsTimeChoice
        p.automaticFastingStartMinute = automaticFastingStartMinute
        p.automaticResumeDateString = automaticResumeDateString

        let vm = FastingTimerViewModel(
            persistence: p,
            schedule: ScheduleService(),
            startTicker: false
        )
        return (vm, defaults)
    }

    private func dayString(for date: Date) -> String {
        ScheduleService().dayString(for: date)
    }

    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    // MARK: - Manual mode core paths

    @Test func startFasting_setsStateAndSessionWithCorrectDuration() {
        let (vm, _) = makeVM()
        vm.startFasting()
        #expect(vm.state == .fasting)
        #expect(vm.session != nil)
        #expect(vm.session?.targetDuration == TimeInterval(16 * 3600))
    }

    @Test func endFasting_transitionsToEatingWithEatingDuration() {
        let (vm, _) = makeVM()
        vm.startFasting()
        vm.endFasting()
        #expect(vm.state == .eating)
        #expect(vm.session?.targetDuration == TimeInterval(8 * 3600))
    }

    @Test func skipToday_manual_setsSkippedAndNeedsTimeChoice() {
        let (vm, _) = makeVM()
        vm.startFasting()
        vm.skipToday()

        #expect(vm.state == .skipped)
        #expect(vm.session == nil)
        #expect(vm.manualStartNeedsTimeChoice == true)
        #expect(vm.skippedDateString == dayString(for: Date()))
    }

    @Test func resumeToday_manual_returnsToNotStartedAndKeepsTimeChoiceFlag() {
        let (vm, _) = makeVM(state: .skipped, skippedDateString: dayString(for: Date()))
        vm.resumeToday()

        #expect(vm.state == .notStarted)
        #expect(vm.skippedDateString == nil)
        #expect(vm.manualStartNeedsTimeChoice == true)
    }

    @Test func updateTargetMinutes_syncsActiveSessionDuration() {
        let (vm, _) = makeVM()
        vm.startFasting()
        // 默认 16h，改成 18h，session.targetDuration 应立即同步
        vm.updateTargetMinutes(18 * 60)
        #expect(vm.session?.targetDuration == TimeInterval(18 * 3600))
        #expect(vm.activeTargetDuration == TimeInterval(18 * 3600))
    }

    @Test func adjustCurrentSessionStartDate_movesSessionStartBackward() {
        let (vm, _) = makeVM()
        vm.startFasting()
        let originalStart = vm.session!.startDate
        let earlier = originalStart.addingTimeInterval(-30 * 60)
        vm.adjustCurrentSessionStartDate(earlier)
        #expect(vm.session?.startDate == earlier)
    }

    @Test func adjustCurrentSessionStartDate_clampsToNow() {
        let (vm, _) = makeVM()
        vm.startFasting()
        let future = Date().addingTimeInterval(3600)
        vm.adjustCurrentSessionStartDate(future)
        // 不能挪到未来——应被钳制到 ~now
        #expect((vm.session?.startDate ?? .distantFuture) <= Date().addingTimeInterval(1))
    }

    // MARK: - Cross-day skip recovery

    @Test func rehydrate_skippedYesterday_recoversToNotStarted_inManualMode() {
        let yesterdayKey = dayString(for: yesterday)
        let (vm, _) = makeVM(
            timingMode: .manual,
            state: .skipped,
            skippedDateString: yesterdayKey
        )
        // makeVM 内部 init 已经调用过 rehydrate
        #expect(vm.state == .notStarted)
        #expect(vm.skippedDateString == nil)
        #expect(vm.manualStartNeedsTimeChoice == true)
    }

    @Test func rehydrate_skippedToday_remainsSkipped() {
        let todayKey = dayString(for: Date())
        let (vm, _) = makeVM(
            timingMode: .manual,
            state: .skipped,
            skippedDateString: todayKey
        )
        #expect(vm.state == .skipped)
    }

    @Test func rehydrate_inconsistentFastingWithoutSession_resetsToNotStarted() {
        // 持久化里 state == .fasting 但没有 session（数据损坏 / 旧版升级），
        // rehydrate 应该兜底回到 notStarted
        let (vm, _) = makeVM(
            timingMode: .manual,
            state: .fasting,
            session: nil
        )
        #expect(vm.state == .notStarted)
        #expect(vm.session == nil)
    }

    // MARK: - Automatic mode

    @Test func automatic_startFasting_setsFastingStartMinuteAnchor() {
        let (vm, defaults) = makeVM(timingMode: .automatic)
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        vm.startFasting(at: twoHoursAgo)

        let expectedAnchor = ScheduleService().minuteOfDay(for: twoHoursAgo)
        let p = PersistenceService(defaults: defaults)
        #expect(p.automaticFastingStartMinute == expectedAnchor)
    }

    @Test func automatic_skipTodayWithFastingActive_setsAnchorAndResumeDate() {
        let (vm, defaults) = makeVM(timingMode: .automatic)
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        vm.startFasting(at: twoHoursAgo)
        vm.skipToday()

        #expect(vm.state == .skipped)

        let p = PersistenceService(defaults: defaults)
        let expectedAnchor = ScheduleService().minuteOfDay(for: twoHoursAgo)
        #expect(p.automaticFastingStartMinute == expectedAnchor)
        let tomorrow = ScheduleService().nextDayString(after: Date())
        #expect(p.automaticResumeDateString == tomorrow)
    }

    @Test func automatic_skipTodayWithEatingActive_derivesAnchorFromEatingMinusFastingDuration() {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 17
        comps.minute = 0
        let fivePM = cal.date(from: comps)!
        let eatingSession = FastingSession(
            startDate: fivePM,
            targetDuration: TimeInterval(8 * 3600)
        )
        let (vm, defaults) = makeVM(
            timingMode: .automatic,
            state: .eating,
            session: eatingSession
        )

        vm.skipToday()

        let p = PersistenceService(defaults: defaults)
        let expectedAnchor = ScheduleService()
            .minuteOfDay(for: fivePM.addingTimeInterval(-16 * 3600))
        #expect(p.automaticFastingStartMinute == expectedAnchor)
    }

    @Test func automatic_rehydrate_pastResumeTime_resumesActiveCycle() {
        // 跳过昨天 + resume 在今天 00:01。
        // rehydrate 时（运行测试的当前时刻）已远晚于 resume，
        // startFasting + advanceAutomaticSessionIfNeeded 应把状态推进到
        // 当前应处的窗口（fasting 或 eating，取决于跑测试的时刻）。
        // 不论哪种，关键不变量：state != .skipped/.notStarted，session != nil
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let p = PersistenceService(defaults: defaults)

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 0
        comps.minute = 0
        let todayMidnight = cal.date(from: comps)!
        let yesterdayMidnight = cal.date(byAdding: .day, value: -1, to: todayMidnight)!

        let yesterdayStr = ScheduleService().dayString(for: yesterdayMidnight)
        let todayStr = ScheduleService().dayString(for: todayMidnight)

        p.targetMinutes = 16 * 60
        p.timingMode = .automatic
        p.state = .skipped
        p.skippedDateString = yesterdayStr
        p.automaticFastingStartMinute = 1
        p.automaticResumeDateString = todayStr

        let vm = FastingTimerViewModel(
            persistence: p, schedule: ScheduleService(), startTicker: false
        )

        #expect(vm.state == .fasting || vm.state == .eating)
        #expect(vm.session != nil)
        #expect(vm.skippedDateString == nil)
    }

    @Test func automatic_rehydrate_beforeResumeTime_staysNotStarted() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let p = PersistenceService(defaults: defaults)

        let now = Date()
        let yesterdayStr = ScheduleService().dayString(for: yesterday)
        let nextDayStr = ScheduleService().nextDayString(after: now)

        p.targetMinutes = 16 * 60
        p.timingMode = .automatic
        p.state = .skipped
        p.skippedDateString = yesterdayStr
        // resume 设在明天的 23:59
        p.automaticFastingStartMinute = 23 * 60 + 59
        p.automaticResumeDateString = nextDayStr

        let vm = FastingTimerViewModel(
            persistence: p, schedule: ScheduleService(), startTicker: false
        )

        // 还没到 resume 时刻 → 应回到 notStarted 而不是开始 fasting
        #expect(vm.state == .notStarted)
        #expect(vm.session == nil)
    }

    @Test func automatic_advanceCyclesAcrossLongAbsence() {
        // 16:8 cycle，30 小时前开始 fasting
        // 16h fasting → 8h eating → 16h fasting，cycle = 24h
        // 30h - 16h - 8h = 6h，所以现在应在新一轮 fasting，已进行 6h
        let thirtyHoursAgo = Date().addingTimeInterval(-30 * 3600)
        let session = FastingSession(
            startDate: thirtyHoursAgo,
            targetDuration: TimeInterval(16 * 3600)
        )
        let (vm, _) = makeVM(
            timingMode: .automatic,
            state: .fasting,
            session: session
        )
        // makeVM 已经在 init 里 rehydrate → advance 已跑完
        #expect(vm.state == .fasting)
        // 当前 session 应该是新启动的（startDate 在最近 8h 内，不是 30h 前那个）
        let elapsedSinceNewStart = -(vm.session?.startDate.timeIntervalSinceNow ?? 0)
        #expect(elapsedSinceNewStart < 8 * 3600)
        #expect(elapsedSinceNewStart > 0)
    }

    // MARK: - Timing mode switching

    @Test func updateTimingMode_manualToAutomaticMidFasting_setsAnchor() {
        let (vm, defaults) = makeVM(timingMode: .manual)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        vm.startFasting(at: oneHourAgo)
        vm.updateTimingMode(.automatic)

        let expectedAnchor = ScheduleService().minuteOfDay(for: oneHourAgo)
        let p = PersistenceService(defaults: defaults)
        #expect(p.automaticFastingStartMinute == expectedAnchor)
    }

    @Test func updateTimingMode_automaticToManual_clearsResumeDateString() {
        let (vm, defaults) = makeVM(
            timingMode: .automatic,
            automaticResumeDateString: "2099-01-01"
        )
        vm.updateTimingMode(.manual)

        let p = PersistenceService(defaults: defaults)
        #expect(p.automaticResumeDateString == nil)
    }
}
