import Foundation

enum TimeFormat {
    /// "HH:mm:ss" from a non-negative interval (negatives clamped to 0).
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func clock(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// "今天 12:30" / "明天 12:30" 风格，便于在文案中嵌入。
    static func relativeClock(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let timeStr = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        if calendar.isDateInToday(date)     { return "今天 \(timeStr)" }
        if calendar.isDateInTomorrow(date)  { return "明天 \(timeStr)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(timeStr)" }
        let dayComps = calendar.dateComponents([.month, .day], from: date)
        return "\(dayComps.month ?? 0)月\(dayComps.day ?? 0)日 \(timeStr)"
    }
}
