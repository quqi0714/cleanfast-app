import SwiftUI

struct AmbientBackground: View {
    var accentColor: Color = AppColor.sunOrange
    /// 第二光团颜色——默认是落日橙（暖色），断食态下保持，进食态可换成 sageGreen
    /// 让整屏只剩一种色温倾向，状态可一眼分辨
    var supportColor: Color = AppColor.stageGlycogenUse
    /// 第三光团颜色——默认薄荷（冷色），同上语义
    var contrastColor: Color = AppColor.mintGreen
    var intensity: Intensity = .normal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Intensity {
        case subtle
        case normal
        case vibrant
        case cinematic

        var multiplier: Double {
            switch self {
            case .subtle: return 0.55
            case .normal: return 1.0
            case .vibrant: return 1.45
            case .cinematic: return 2.4
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppColor.backgroundCream,
                    AppColor.backgroundWarm,
                    AppColor.backgroundSoft,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    AppColor.highlightEdge.opacity(0.18 * intensity.multiplier),
                    AppColor.highlightEdge.opacity(0),
                ],
                center: UnitPoint(x: 0.42, y: -0.05),
                startRadius: 0,
                endRadius: 700
            )
            .blendMode(.plusLighter)

            if intensity.multiplier > 1.5 {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: accentColor.opacity(0.10), location: 0.50),
                        .init(color: .clear, location: 0.70),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
                .blur(radius: 30)
            }

            if reduceMotion {
                driftingLights(phase1: 0.12, phase2: 0.48, phase3: 0.78)
            } else {
                // 5Hz 足够让 73/89/67s 的慢漂看上去连续（每帧角度变化 ~2.5°，
                // 投影到 unit space 约 0.008/帧，肉眼无跳跃感），但相比 10Hz 减半
                // GPU 负载，避免持续渲染 4 个 RadialGradient + Canvas 噪点。
                TimelineView(.animation(minimumInterval: 1.0 / 5.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase1 = (t / 73.0).truncatingRemainder(dividingBy: 1.0)
                    let phase2 = (t / 89.0 + 0.33).truncatingRemainder(dividingBy: 1.0)
                    let phase3 = (t / 67.0 + 0.66).truncatingRemainder(dividingBy: 1.0)
                    driftingLights(phase1: phase1, phase2: phase2, phase3: phase3)
                }
            }

            PaperTexture()
                .opacity(0.018)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.4), value: accentColor)
    }

    private func driftingLights(phase1: Double, phase2: Double, phase3: Double) -> some View {
        ZStack {
            // 主光团：状态强调色，略微提升以加强主色调
            lightOrb(
                color: accentColor.opacity(0.22 * intensity.multiplier),
                center: drift(phase: phase1, anchor: UnitPoint(x: 0.60, y: 0.25), radius: 0.15),
                radius: 520
            )

            // 副光团：从外部传入，跟随状态色温（warm/cool）走，避免冷暖打架
            lightOrb(
                color: supportColor.opacity(0.10 * intensity.multiplier),
                center: drift(phase: phase2, anchor: UnitPoint(x: 0.30, y: 0.70), radius: 0.18),
                radius: 460
            )

            lightOrb(
                color: contrastColor.opacity(0.08 * intensity.multiplier),
                center: drift(phase: phase3, anchor: UnitPoint(x: 0.85, y: 0.85), radius: 0.12),
                radius: 380
            )
        }
    }

    private func lightOrb(color: Color, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color, color.opacity(0)],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
        .blendMode(.plusLighter)
    }

    private func drift(phase: Double, anchor: UnitPoint, radius: Double) -> UnitPoint {
        let angle = phase * 2 * .pi
        let dx = cos(angle) * radius
        let dy = sin(angle) * radius * 0.65
        return UnitPoint(x: anchor.x + dx, y: anchor.y + dy)
    }
}
