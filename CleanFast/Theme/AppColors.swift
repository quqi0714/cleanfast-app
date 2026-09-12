import SwiftUI
import UIKit

enum AppColor {
    // MARK: - Background（自适应：浅色奶油 / 深色暖夜）
    static let backgroundCream = Color.adaptive(light: 0xFFF8EF, dark: 0x1A1612)
    static let backgroundWarm  = Color.adaptive(light: 0xF8F1E8, dark: 0x1F1A14)
    static let backgroundSoft  = Color.adaptive(light: 0xF4EFE7, dark: 0x241F18)

    // MARK: - 主色（橙、薄荷在两种模式下保持同一色相，肉眼一致）
    static let sunOrange       = Color(hex: 0xF0944C)
    static let sunOrangeSoft   = Color(hex: 0xF6A94A)
    static let sunOrangeWarm   = Color(hex: 0xFFB15C)

    static let mintGreen       = Color(hex: 0x8BC8A2)
    static let mintGreenSoft   = Color(hex: 0xA9CBB3)
    static let sageGreen       = Color(hex: 0x9FBFA8)

    // MARK: - 中性色（自适应）
    static let restGray        = Color.adaptive(light: 0xA7B0BA, dark: 0x6E747B)
    static let restGraySoft    = Color.adaptive(light: 0xD6D9DD, dark: 0x2E3236)

    static let textPrimary     = Color.adaptive(light: 0x2F2A26, dark: 0xF5EDE0)
    static let textSecondary   = Color.adaptive(light: 0x7A7168, dark: 0xA89A8C)
    // Solid orange / yellow / mint buttons need the same deep ink in both themes.
    static let textOnAccent    = Color(hex: 0x2F2A26)

    static let ringTrack       = Color.adaptive(light: 0xEDE4D6, dark: 0x2A2520)

    /// 卡片 / 列表行底色。浅色下接近纯白；深色下是稍亮于背景的暖灰，
    /// 保持"卡片浮在背景上"的层次感，同时不刺眼。
    static let cardSurface     = Color.adaptive(light: 0xFFFFFF, dark: 0x2C2620)

    // MARK: - Light system
    static let shadowAmbient   = Color.adaptive(light: 0x2F2A26, dark: 0x05030A)
    static let highlightEdge   = Color.adaptive(light: 0xFFFFFF, dark: 0xF5EDE0)

    // MARK: - Stage palette
    static let stageDigesting          = Color(hex: 0xF2B559)
    static let stageBloodSugarSettling = Color(hex: 0xEE8E3F)
    static let stageGlycogenUse        = Color(hex: 0xE26B33)
    static let stageFuelSwitch         = Color(hex: 0xCB4F45)
    static let stageDeepFueling        = Color(hex: 0xA64161)
    static let stageCompleted          = Color(hex: 0x8BC8A2)
}

extension FastingStage {
    var color: Color {
        switch self {
        case .digesting:          return AppColor.stageDigesting
        case .bloodSugarSettling: return AppColor.stageBloodSugarSettling
        case .glycogenUse:        return AppColor.stageGlycogenUse
        case .fuelSwitch:         return AppColor.stageFuelSwitch
        case .deepFueling:        return AppColor.stageDeepFueling
        case .completed:          return AppColor.stageCompleted
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

    /// 浅色 / 深色双值自适应。系统切换 Appearance 时自动跟随。
    /// 预先构造 `UIColor` 实例并 capture 进闭包，trait 变化时闭包仅返回缓存
    /// 的实例，不再每次重新初始化。高频渲染场景（背景 / 阴影）下省掉大量
    /// UIColor allocation。
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        let lightUI = UIColor(rgbHex: light)
        let darkUI = UIColor(rgbHex: dark)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? darkUI : lightUI
        })
    }
}

private extension UIColor {
    convenience init(rgbHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
