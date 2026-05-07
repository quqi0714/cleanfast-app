import Foundation

/// 时间选择器（开始断食 / 调整开始时间）的"最近 48 小时"约束工具集。
/// 限定可选时段在过去 48 小时内，并提供 day/hour/minute 三段独立 picker
/// 选项的派生（避免选到超出范围的时刻）。
enum RecentTimeSelection {
    static func range(now: Date = Date()) -> ClosedRange<Date> {
        now.addingTimeInterval(-48 * 60 * 60)...now
    }

    static func clamp(_ date: Date, now: Date = Date()) -> Date {
        let range = range(now: now)
        return min(max(date, range.lowerBound), range.upperBound)
    }

    static func date(day: RecentDay, hour: Int, minute: Int, now: Date) -> Date {
        let calendar = Calendar.current
        let base = day.startDate(now: now)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    static func day(for date: Date, now: Date) -> RecentDay {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        return date >= todayStart ? .today : .yesterday
    }

    static func dayOptions(now: Date = Date()) -> [RecentDay] {
        let selectionRange = range(now: now)
        return RecentDay.allCases.filter { day in
            let start = day.startDate(now: now)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            return start <= selectionRange.upperBound && end > selectionRange.lowerBound
        }
    }

    static func hourOptions(day: RecentDay, now: Date = Date()) -> [Int] {
        (0..<24).filter { hour in
            !minuteOptions(day: day, hour: hour, now: now).isEmpty
        }
    }

    static func minuteOptions(day: RecentDay, hour: Int, now: Date = Date()) -> [Int] {
        let selectionRange = range(now: now)
        return (0..<60).filter { minute in
            let candidate = date(day: day, hour: hour, minute: minute, now: now)
            return candidate >= selectionRange.lowerBound && candidate <= selectionRange.upperBound
        }
    }
}

enum RecentDay: Int, CaseIterable, Identifiable {
    case twoDaysAgo = -2
    case yesterday = -1
    case today = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .twoDaysAgo: return String(localized: "前天")
        case .yesterday: return String(localized: "昨天")
        case .today: return String(localized: "今天")
        }
    }

    func startDate(now: Date) -> Date {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: rawValue, to: todayStart) ?? todayStart
    }
}
