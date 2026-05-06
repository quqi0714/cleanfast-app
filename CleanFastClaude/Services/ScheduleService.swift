import Foundation

struct ScheduleService {
    var calendar: Calendar = .current

    /// Stable "yyyy-MM-dd" key for a given date in the current calendar/timezone.
    func dayString(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0
        )
    }

    func nextDayString(after date: Date) -> String {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return dayString(for: next)
    }

    func minuteOfDay(for date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return max(0, min(23 * 60 + 59, (comps.hour ?? 0) * 60 + (comps.minute ?? 0)))
    }

    func date(forDayString dayString: String, minuteOfDay: Int) -> Date? {
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
}
