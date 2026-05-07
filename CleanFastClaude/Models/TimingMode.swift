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
            return String(localized: "到点后只提醒，由你决定什么时候进入下一段。")
        case .automatic:
            return String(localized: "按设定窗口自动进入下一段，打开时直接看到当前窗口。")
        }
    }
}
