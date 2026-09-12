import Foundation

enum TimingMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return String(localized: "手动切换")
        case .automatic: return String(localized: "自动切换")
        }
    }

    var shortDescription: String {
        switch self {
        case .manual:
            return String(localized: "按实际用餐时间计时。到点提醒，什么时候开始和结束由你决定。")
        case .automatic:
            return String(localized: "适合用餐时间比较固定的人，按设定窗口自动循环。")
        }
    }
}
