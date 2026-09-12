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

    /// "今天 12:30" / "明天 12:30" 风格，便于在文案中嵌入。
    /// 通过 `String(localized:)` 走 catalog，英文 / 繁中下日词会跟着翻。
    /// 时刻部分跟随系统 locale/时制（中文默认 24h 不变，en-US 显示 12h AM/PM）。
    static func relativeClock(_ date: Date, calendar: Calendar = .current) -> String {
        let timeStr = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date)     { return String(localized: "今天 \(timeStr)") }
        if calendar.isDateInTomorrow(date)  { return String(localized: "明天 \(timeStr)") }
        if calendar.isDateInYesterday(date) { return String(localized: "昨天 \(timeStr)") }
        let dayComps = calendar.dateComponents([.month, .day], from: date)
        let month = dayComps.month ?? 0
        let day = dayComps.day ?? 0
        return String(localized: "\(month)月\(day)日 \(timeStr)")
    }
}
