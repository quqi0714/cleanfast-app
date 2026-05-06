import SwiftUI

/// 跳过今天状态的中心视觉：柔和月亮 + 后方径向光晕 + SF Symbol 呼吸脉冲。
/// 用于替换断食/进食态的"大数字"位置——让"今天休息"成为有仪式感的状态，
/// 而不是冰冷的"—"占位。
struct SkippedCenterpiece: View {
    /// 月亮图标显示尺寸（cinematic 推荐 76，classic ring 内推荐 56）。
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            // 后方光晕：让月亮像浮在一团柔光里
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColor.restGraySoft.opacity(0.45),
                            AppColor.restGraySoft.opacity(0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 1.35
                    )
                )
                .frame(width: size * 2.4, height: size * 2.4)
                .blur(radius: 12)
                .blendMode(.plusLighter)

            // 月亮主体：带方向阴影，自带 .pulse 缓慢呼吸
            Image(systemName: "moon.stars.fill")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            AppColor.restGray.opacity(0.95),
                            AppColor.restGray.opacity(0.65),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppColor.restGray.opacity(0.35), radius: 14, x: 0, y: 4)
                .shadow(color: AppColor.shadowAmbient.opacity(0.10), radius: 8, x: 2, y: 6)
                .symbolEffect(.pulse.byLayer, options: .repeating, isActive: true)
        }
    }
}
