import Foundation
import SwiftUI
import UIKit

// MARK: - Models（Widget 自带的轻量副本）

enum WidgetFastingState: String {
    case notStarted
    case fasting
    case eating
    case skipped
}

enum WidgetTimingMode: String {
    case manual
    case automatic
}

struct WidgetSession: Decodable {
    let startDate: Date
    let targetDuration: TimeInterval

    var targetEndDate: Date { startDate.addingTimeInterval(targetDuration) }
}

struct WidgetSnapshot {
    let state: WidgetFastingState
    let session: WidgetSession?
    let targetMinutes: Int
    let timingMode: WidgetTimingMode
    let skippedDateString: String?
    let automaticResumeStartDate: Date?
    let date: Date

    static let appGroupIdentifier = "group.la.maxhope.cleanfast"

    static func current(at date: Date = Date()) -> WidgetSnapshot {
        let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard

        let targetRaw = defaults.integer(forKey: "targetMinutes.v1")
        let targetMinutes = targetRaw == 0 ? 16 * 60 : min(max(targetRaw, 60), 23 * 60)
        let timingModeRaw = defaults.string(forKey: "timingMode.v1") ?? ""
        let timingMode = WidgetTimingMode(rawValue: timingModeRaw) ?? .manual
        let automaticStartMinute: Int? = defaults.object(forKey: "automaticFastingStartMinute.v1") == nil
            ? nil
            : defaults.integer(forKey: "automaticFastingStartMinute.v1")
        let automaticResumeDateString = defaults.string(forKey: "automaticResumeDate.v1")
        let automaticResumeStartDate = automaticResumeDateString.flatMap { day in
            automaticStartMinute.flatMap { minute in
                Self.date(forDayString: day, minuteOfDay: minute)
            }
        }

        let stateRaw = defaults.string(forKey: "state.v1") ?? ""
        var state = WidgetFastingState(rawValue: stateRaw) ?? .notStarted
        let skippedDateString = defaults.string(forKey: "skippedDate.v1")
        if state == .skipped, skippedDateString != dayString(for: date) {
            if timingMode == .automatic,
               let automaticResumeStartDate,
               date >= automaticResumeStartDate {
                state = .fasting
            } else {
                state = .notStarted
            }
        }
        if state == .notStarted,
           timingMode == .automatic,
           let automaticResumeStartDate,
           date >= automaticResumeStartDate {
            state = .fasting
        }

        var session: WidgetSession?
        if state == .fasting,
           timingMode == .automatic,
           automaticResumeDateString != nil,
           let automaticResumeStartDate,
           date >= automaticResumeStartDate {
            session = WidgetSession(
                startDate: automaticResumeStartDate,
                targetDuration: TimeInterval(targetMinutes * 60)
            )
        }
        if session == nil,
           state == .fasting || state == .eating,
           let data = defaults.data(forKey: "session.v1") {
            session = try? JSONDecoder().decode(WidgetSession.self, from: data)
        }
        if (state == .fasting || state == .eating), session == nil {
            state = .notStarted
        }

        if timingMode == .automatic,
           let activeSession = session,
           state == .fasting || state == .eating {
            let advanced = advanceAutomatic(
                state: state,
                session: activeSession,
                targetMinutes: targetMinutes,
                at: date
            )
            state = advanced.state
            session = advanced.session
        }

        return WidgetSnapshot(
            state: state,
            session: session,
            targetMinutes: targetMinutes,
            timingMode: timingMode,
            skippedDateString: skippedDateString,
            automaticResumeStartDate: automaticResumeStartDate,
            date: date
        )
    }

    static func startOfNextDay(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
    }

    private static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func date(forDayString dayString: String, minuteOfDay: Int, calendar: Calendar = .current) -> Date? {
        let parts = dayString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        comps.second = 0
        return calendar.date(from: comps)
    }

    private static func advanceAutomatic(
        state: WidgetFastingState,
        session: WidgetSession,
        targetMinutes: Int,
        at date: Date
    ) -> (state: WidgetFastingState, session: WidgetSession) {
        guard state == .fasting || state == .eating else {
            return (state, session)
        }

        let fastingDuration = TimeInterval(targetMinutes * 60)
        let eatingDuration = TimeInterval(max(0, 24 * 60 - targetMinutes) * 60)

        let result = advanceAutomaticCycle(
            startDate: session.startDate,
            currentDuration: session.targetDuration,
            isFasting: state == .fasting,
            fastingDuration: fastingDuration,
            eatingDuration: eatingDuration,
            at: date
        )

        let nextState: WidgetFastingState = result.isFasting ? .fasting : .eating
        let nextSession = WidgetSession(
            startDate: result.startDate,
            targetDuration: result.duration
        )
        return (nextState, nextSession)
    }

    /// 自动模式循环推进的纯函数实现（无副作用，仅算 Date 数学）。
    ///
    /// **MIRROR**：必须与 `FastingTimerViewModel.advanceAutomaticCycle` 保持算法等价。
    /// 改动这里时同步改主 App 那一份，反之亦然（widget target 无法被测试 target
    /// 引用，跨 target 等价只能靠人工同步）。
    /// 主 App 侧的单元测试 `advanceAutomaticCycle_matchesPinnedReference` 用独立
    /// 参考实现钉住该算法的行为——改这里时请同步看它是否需要更新。
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

    var elapsed: TimeInterval {
        guard let session else { return 0 }
        return max(0, date.timeIntervalSince(session.startDate))
    }

    var hasReachedTarget: Bool {
        guard let session else { return false }
        return elapsed >= session.targetDuration
    }

    var progress: Double {
        guard let session, session.targetDuration > 0 else { return 0 }
        return min(max(elapsed / session.targetDuration, 0), 1)
    }

    /// 当前所处的断食阶段标题（与主 App 的 FastingStage 一致）。
    /// 仅在 .fasting 状态下返回；其他状态返回 nil（widget 端可据此决定是否展示副标题）。
    var fastingStageTitle: String? {
        guard state == .fasting, session != nil else { return nil }
        if hasReachedTarget { return String(localized: "目标达成") }
        let h = elapsed / 3600
        switch h {
        case ..<2:  return String(localized: "消化中")
        case ..<4:  return String(localized: "血糖渐稳")
        case ..<8:  return String(localized: "动用糖原")
        case ..<12: return String(localized: "燃料切换")
        default:    return String(localized: "深度供能")
        }
    }

    /// 阶段分隔点（小时数 + SF Symbol），用于在能量条上漂浮 marker。
    /// 仅在 .fasting 时有意义；超过 target 的标记自动隐藏。
    var stageMarkers: [WidgetStageMarker] {
        guard state == .fasting, let session else { return [] }
        let target = session.targetDuration / 3600
        guard target > 0 else { return [] }
        let elapsedH = elapsed / 3600
        let stages: [(h: Double, sym: String)] = [
            (2,  "drop.fill"),
            (4,  "bolt.fill"),
            (8,  "arrow.triangle.2.circlepath"),
            (12, "flame.fill"),
        ]
        return stages.compactMap { stage in
            let f = stage.h / target
            guard f <= 1.0 else { return nil }
            return WidgetStageMarker(
                id: "\(Int(stage.h))h",
                fraction: f,
                symbol: stage.sym,
                color: WidgetColor.stageColor(elapsedHours: stage.h, hasReachedTarget: false),
                isActive: elapsedH >= stage.h
            )
        }
    }
}

struct WidgetStageMarker: Identifiable {
    let id: String
    let fraction: Double
    let symbol: String
    let color: Color
    let isActive: Bool
}

// MARK: - Colors（自适应：浅色 / 深色）

enum WidgetColor {
    static let background      = Color.adaptive(light: 0xFFF8EF, dark: 0x1A1612)
    static let backgroundSoft  = Color.adaptive(light: 0xF4EFE7, dark: 0x241F18)
    static let textPrimary     = Color.adaptive(light: 0x2F2A26, dark: 0xF5EDE0)
    static let textSecondary   = Color.adaptive(light: 0x7A7168, dark: 0xA89A8C)
    static let ringTrack       = Color.adaptive(light: 0xEDE4D6, dark: 0x2A2520)
    static let trackOverlay    = Color.adaptive(light: 0x000000, dark: 0xFFFFFF) // 给条用半透明阴影
    static let cardSurface     = Color.adaptive(light: 0xFFFFFF, dark: 0x2C2620) // 中心白盘 / 卡片底

    static let sunOrange       = Color(hex: 0xF0944C)
    static let mintGreen       = Color(hex: 0x8BC8A2)

    static func stageColor(elapsedHours: Double, hasReachedTarget: Bool) -> Color {
        if hasReachedTarget { return mintGreen }
        switch elapsedHours {
        case ..<2:  return Color(red: 0.949, green: 0.710, blue: 0.349)  // #F2B559
        case ..<4:  return Color(red: 0.933, green: 0.557, blue: 0.247)  // #EE8E3F
        case ..<8:  return Color(red: 0.886, green: 0.420, blue: 0.200)  // #E26B33
        case ..<12: return Color(red: 0.796, green: 0.310, blue: 0.271)  // #CB4F45
        default:    return Color(red: 0.651, green: 0.255, blue: 0.380)  // #A64161
        }
    }

    static func stageSymbol(elapsedHours: Double, hasReachedTarget: Bool) -> String {
        if hasReachedTarget { return "checkmark.seal.fill" }
        switch elapsedHours {
        case ..<2:  return "leaf.fill"
        case ..<4:  return "drop.fill"
        case ..<8:  return "bolt.fill"
        case ..<12: return "arrow.triangle.2.circlepath"
        default:    return "flame.fill"
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        // 预解析 UIColor 实例，capture 进闭包，避免每次 trait 变化都重新初始化
        let lightUI = UIColor(widgetHex: light)
        let darkUI = UIColor(widgetHex: dark)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? darkUI : lightUI
        })
    }
}

private extension UIColor {
    convenience init(widgetHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
