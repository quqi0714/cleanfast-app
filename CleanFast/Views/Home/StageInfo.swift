import SwiftUI

/// 主页阶段信息浮窗的载荷。`detail` 是大卡片（点击底部状态名时弹），
/// `marker` 是小气泡（点击 LightBar 上的阶段图标时弹）。
struct StageInfo: Identifiable {
    let title: String
    let message: String?
    let color: Color
    let anchor: CGPoint?
    let kind: StageInfoKind

    var id: String {
        title + (message ?? "") + "\(anchor?.x ?? 0)" + "\(anchor?.y ?? 0)"
    }
}

enum StageInfoKind {
    case detail
    case marker
}
