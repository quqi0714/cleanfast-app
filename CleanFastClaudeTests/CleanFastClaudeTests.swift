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

    // MARK: - Automatic-cycle math (drift detection vs widget)

    /// 这组测试钉住 `FastingTimerViewModel.advanceAutomaticCycle` 的精确行为。
    /// 因为 widget 那边的 `WidgetSnapshot.advanceAutomaticCycle` 是按位等价的镜像实现，
    /// 任何这边的算法变动都必须同步到 widget；如果两边偏离，
    /// 这组用例 + 真机看 widget 是否还跟主 App 同步是双重保险。

    @Test func advanceAutomaticCycle_noAdvanceWhenWithinCurrentSession() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let now = start.addingTimeInterval(3600) // 进入断食 1h
        let r = FastingTimerViewModel.advanceAutomaticCycle(
            startDate: start,
            currentDuration: 16 * 3600,
            isFasting: true,
            fastingDuration: 16 * 3600,
            eatingDuration: 8 * 3600,
            at: now
        )
        #expect(r.cyclesAdvanced == 0)
        #expect(r.startDate == start)
        #expect(r.isFasting == true)
        #expect(r.duration == 16 * 3600)
    }

    @Test func advanceAutomaticCycle_oneCycleFastingToEating() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 断食 16h 已过 30 分钟 → 进入进食窗口
        let now = start.addingTimeInterval(16.5 * 3600)
        let r = FastingTimerViewModel.advanceAutomaticCycle(
            startDate: start,
            currentDuration: 16 * 3600,
            isFasting: true,
            fastingDuration: 16 * 3600,
            eatingDuration: 8 * 3600,
            at: now
        )
        #expect(r.cyclesAdvanced == 1)
        #expect(r.startDate == start.addingTimeInterval(16 * 3600))
        #expect(r.isFasting == false)
        #expect(r.duration == 8 * 3600)
    }

    @Test func advanceAutomaticCycle_multipleFullDays() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 跨 3 天（断食 16 + 进食 8 = 24h × 3 = 72h），结束在第 4 个断食的中段
        let now = start.addingTimeInterval(3 * 24 * 3600 + 5 * 3600)
        let r = FastingTimerViewModel.advanceAutomaticCycle(
            startDate: start,
            currentDuration: 16 * 3600,
            isFasting: true,
            fastingDuration: 16 * 3600,
            eatingDuration: 8 * 3600,
            at: now
        )
        // 3 完整天 × 2 段 = 6 cycle
        #expect(r.cyclesAdvanced == 6)
        #expect(r.isFasting == true)
        #expect(r.duration == 16 * 3600)
        // 起点 = start + 72h
        #expect(r.startDate == start.addingTimeInterval(72 * 3600))
    }

    @Test func advanceAutomaticCycle_capsAtMaxIterations() {
        // 极端：1 秒目标会让 200 cycle 内推完非常多时间。这个 test 守护无限循环兜底。
        let start = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 100_000_000)
        let r = FastingTimerViewModel.advanceAutomaticCycle(
            startDate: start,
            currentDuration: 1,
            isFasting: true,
            fastingDuration: 1,
            eatingDuration: 1,
            at: now
        )
        // 守护值 200，表示循环命中上限
        #expect(r.cyclesAdvanced == 200)
    }

    @Test func advanceAutomaticCycle_eatingToFastingBoundary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 进食 8h 刚好到点
        let now = start.addingTimeInterval(8 * 3600)
        let r = FastingTimerViewModel.advanceAutomaticCycle(
            startDate: start,
            currentDuration: 8 * 3600,
            isFasting: false, // 进食态
            fastingDuration: 16 * 3600,
            eatingDuration: 8 * 3600,
            at: now
        )
        #expect(r.cyclesAdvanced == 1)
        #expect(r.isFasting == true)
        #expect(r.duration == 16 * 3600)
        #expect(r.startDate == start.addingTimeInterval(8 * 3600))
    }

    /// 独立参考实现（刻意用不同写法：直接按周期数学求余，而不是逐段循环），
    /// 在整段网格上与 `advanceAutomaticCycle` 比对，钉住其行为。
    /// widget 侧的镜像副本无法被本 target 引用，人工同步时以此为准绳。
    @Test func advanceAutomaticCycle_matchesPinnedReference() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let plans: [(fasting: TimeInterval, eating: TimeInterval)] = [
            (16 * 3600, 8 * 3600),
            (18 * 3600, 6 * 3600),
            (23 * 3600, 1 * 3600),
        ]
        let offsets: [TimeInterval] = [
            0, 1, 3599, 3600, 8 * 3600 - 1, 8 * 3600, 16 * 3600 - 1, 16 * 3600,
            24 * 3600, 30 * 3600, 72 * 3600 + 5 * 3600, 30 * 24 * 3600 + 123,
        ]
        for plan in plans {
            for isFasting in [true, false] {
                let currentDuration = isFasting ? plan.fasting : plan.eating
                for offset in offsets {
                    let now = base.addingTimeInterval(offset)
                    let r = FastingTimerViewModel.advanceAutomaticCycle(
                        startDate: base,
                        currentDuration: currentDuration,
                        isFasting: isFasting,
                        fastingDuration: plan.fasting,
                        eatingDuration: plan.eating,
                        at: now
                    )
                    // 参考实现：先消耗当前段，再按整周期求余推进
                    var refStart = base
                    var refFasting = isFasting
                    var refDuration = currentDuration
                    if now >= base.addingTimeInterval(currentDuration) {
                        refStart = base.addingTimeInterval(currentDuration)
                        refFasting = !isFasting
                        refDuration = refFasting ? plan.fasting : plan.eating
                        let cycle = plan.fasting + plan.eating
                        var remaining = now.timeIntervalSince(refStart)
                        let fullCycles = floor(remaining / cycle)
                        refStart = refStart.addingTimeInterval(fullCycles * cycle)
                        remaining -= fullCycles * cycle
                        if remaining >= refDuration {
                            refStart = refStart.addingTimeInterval(refDuration)
                            refFasting.toggle()
                            refDuration = refFasting ? plan.fasting : plan.eating
                        }
                    }
                    #expect(r.startDate == refStart,
                            "startDate mismatch at offset \(offset), fasting=\(isFasting)")
                    #expect(r.isFasting == refFasting,
                            "isFasting mismatch at offset \(offset), fasting=\(isFasting)")
                    #expect(r.duration == refDuration,
                            "duration mismatch at offset \(offset), fasting=\(isFasting)")
                }
            }
        }
    }

    // MARK: - Upcoming automatic transitions (notification series)

    @Test func upcomingTransitions_alternateAndAccumulateCorrectly() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let transitions = FastingTimerViewModel.upcomingAutomaticTransitions(
            sessionStart: start,
            sessionDuration: 16 * 3600,
            sessionIsFasting: true,
            fastingDuration: 16 * 3600,
            eatingDuration: 8 * 3600,
            count: 4
        )
        #expect(transitions.count == 4)
        // 断食结束 → 进食结束 → 断食结束 → 进食结束
        #expect(transitions[0].fireDate == start.addingTimeInterval(16 * 3600))
        #expect(transitions[0].endedWindowIsFasting == true)
        #expect(transitions[1].fireDate == start.addingTimeInterval(24 * 3600))
        #expect(transitions[1].endedWindowIsFasting == false)
        #expect(transitions[2].fireDate == start.addingTimeInterval(40 * 3600))
        #expect(transitions[2].endedWindowIsFasting == true)
        #expect(transitions[3].fireDate == start.addingTimeInterval(48 * 3600))
        #expect(transitions[3].endedWindowIsFasting == false)
    }

    @Test func upcomingTransitions_startingFromEatingWindow() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let transitions = FastingTimerViewModel.upcomingAutomaticTransitions(
            sessionStart: start,
            sessionDuration: 8 * 3600,
            sessionIsFasting: false,
            fastingDuration: 16 * 3600,
            eatingDuration: 8 * 3600,
            count: 2
        )
        #expect(transitions.count == 2)
        #expect(transitions[0].fireDate == start.addingTimeInterval(8 * 3600))
        #expect(transitions[0].endedWindowIsFasting == false)
        #expect(transitions[1].fireDate == start.addingTimeInterval(24 * 3600))
        #expect(transitions[1].endedWindowIsFasting == true)
    }

    @Test func upcomingTransitions_zeroCountOrDuration_returnsEmpty() {
        let start = Date()
        #expect(FastingTimerViewModel.upcomingAutomaticTransitions(
            sessionStart: start, sessionDuration: 16 * 3600, sessionIsFasting: true,
            fastingDuration: 16 * 3600, eatingDuration: 8 * 3600, count: 0
        ).isEmpty)
        #expect(FastingTimerViewModel.upcomingAutomaticTransitions(
            sessionStart: start, sessionDuration: 16 * 3600, sessionIsFasting: true,
            fastingDuration: 0, eatingDuration: 8 * 3600, count: 3
        ).isEmpty)
    }

    // MARK: - Start-time lower-bound clamping（时间线倒挂保护）

    @Test func startEating_beforeFastingStart_clampsToFastingStart() {
        let (vm, _) = makeVM()
        let fastStart = Date().addingTimeInterval(-4 * 3600)
        vm.startFasting(at: fastStart)
        // 试图把进食开始选到断食开始之前 1 小时 → 应钳制到断食开始
        vm.endFasting(at: fastStart.addingTimeInterval(-3600))
        #expect(vm.state == .eating)
        #expect(vm.session?.startDate == fastStart)
    }

    @Test func restartFasting_beforeEatingStart_clampsToEatingStart() {
        let (vm, _) = makeVM()
        vm.startFasting(at: Date().addingTimeInterval(-10 * 3600))
        let eatingStart = Date().addingTimeInterval(-2 * 3600)
        vm.endFasting(at: eatingStart)
        // 进食态重新开始断食，选到进食开始之前 → 应钳制到进食开始
        vm.startFasting(at: eatingStart.addingTimeInterval(-3600))
        #expect(vm.state == .fasting)
        #expect(vm.session?.startDate == eatingStart)
    }

    @Test func startEating_normalPastTime_keepsChosenTime() {
        let (vm, _) = makeVM()
        let fastStart = Date().addingTimeInterval(-6 * 3600)
        vm.startFasting(at: fastStart)
        let eatingStart = Date().addingTimeInterval(-30 * 60)
        vm.endFasting(at: eatingStart)
        #expect(vm.session?.startDate == eatingStart)
    }

    // MARK: - RecentTimeSelection day mapping

    @Test func recentDay_mapsTodayYesterdayAndTwoDaysAgo() {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        let todayDate = todayStart.addingTimeInterval(60)
        #expect(RecentTimeSelection.day(for: todayDate, now: now) == .today)

        let yesterdayDate = cal.date(byAdding: .day, value: -1, to: todayStart)!
            .addingTimeInterval(5 * 3600)
        #expect(RecentTimeSelection.day(for: yesterdayDate, now: now) == .yesterday)

        // 关键回归：前天的时间必须映射到 .twoDaysAgo（修复前会错报成 .yesterday）
        let twoDaysAgoDate = cal.date(byAdding: .day, value: -2, to: todayStart)!
            .addingTimeInterval(20 * 3600)
        #expect(RecentTimeSelection.day(for: twoDaysAgoDate, now: now) == .twoDaysAgo)
    }

    // MARK: - Review milestones（求评里程碑）

    /// 每轮完成后经 skip/resume 回到 notStarted，
    /// 否则从进食态回退开始时间会被时间线倒挂钳制挡住（那是生产期望行为）。
    @Test func completedFast_thirdCompletionTriggersReviewRequest() {
        let (vm, defaults) = makeVM()
        func completeOneFast() {
            vm.startFasting(at: Date().addingTimeInterval(-17 * 3600)) // 超过 16h 目标
            vm.endFasting()
            vm.skipToday()
            vm.resumeToday()
        }
        for i in 1...2 {
            completeOneFast()
            #expect(vm.pendingReviewRequest == false, "第 \(i) 次不应触发")
        }
        completeOneFast()
        #expect(vm.pendingReviewRequest == true)
        let p = PersistenceService(defaults: defaults)
        #expect(p.completedFastCount == 3)

        vm.markReviewRequestHandled()
        #expect(vm.pendingReviewRequest == false)
        #expect(p.reviewRequestedForCount == 3)

        // 第 4 次完成：非里程碑，不再触发
        completeOneFast()
        #expect(vm.pendingReviewRequest == false)
        #expect(p.completedFastCount == 4)
    }

    @Test func completedFast_unreachedTargetDoesNotCount() {
        let (vm, defaults) = makeVM()
        vm.startFasting(at: Date().addingTimeInterval(-3600)) // 只断了 1h，未达标
        vm.endFasting()
        #expect(PersistenceService(defaults: defaults).completedFastCount == 0)
        #expect(vm.pendingReviewRequest == false)
    }

    @Test func completedFast_automaticSingleAdvanceCounts_multiCatchupDoesNot() {
        // 实时单周期推进（断食 16h 后 30 分钟）→ 计 1 次
        let liveSession = FastingSession(
            startDate: Date().addingTimeInterval(-16.5 * 3600),
            targetDuration: TimeInterval(16 * 3600)
        )
        let (vm1, d1) = makeVM(timingMode: .automatic, state: .fasting, session: liveSession)
        #expect(vm1.state == .eating)
        #expect(PersistenceService(defaults: d1).completedFastCount == 1)

        // 离开 30 小时的多周期追赶 → 不计
        let staleSession = FastingSession(
            startDate: Date().addingTimeInterval(-30 * 3600),
            targetDuration: TimeInterval(16 * 3600)
        )
        let (_, d2) = makeVM(timingMode: .automatic, state: .fasting, session: staleSession)
        #expect(PersistenceService(defaults: d2).completedFastCount == 0)
    }
}
