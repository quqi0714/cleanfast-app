import SwiftUI

/// 圆环上的一个阶段标记（漂在外圈周长上，告诉用户"这一时刻代表什么"）。
struct StageMarker: Identifiable, Equatable {
    let id: String
    let fraction: Double      // 0...1，在圆环上的位置
    let symbol: String        // SF Symbol
    let title: String
    let color: Color
    let isActive: Bool        // 已经走过的阶段为 true
}

struct ProgressRingView: View {
    var progress: Double
    var color: Color
    var trackColor: Color = AppColor.ringTrack
    var lineWidth: CGFloat = 18
    var glowEnabled: Bool = true
    var markers: [StageMarker] = []
    /// 圆环上的阶段标记会绕这个半径漂浮（默认 = ringSize/2）。
    var radius: CGFloat = 140
    /// 是否显示中心白色实心盘（让数字与环视觉分层）。
    var showCenterDisk: Bool = true
    var onMarkerTap: ((StageMarker, CGPoint) -> Void)?

    @State private var breathing = false

    private var trim: CGFloat { max(0.0001, min(CGFloat(progress), 1)) }

    var body: some View {
        ZStack {
            // 1. Track
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            if glowEnabled {
                Circle()
                    .stroke(
                        color.opacity(0.12),
                        style: StrokeStyle(lineWidth: lineWidth + 32, lineCap: .round)
                    )
                    .blur(radius: 26)
                    .animation(.easeInOut(duration: 1.4), value: color)

                Circle()
                    .trim(from: 0, to: trim)
                    .stroke(
                        color.opacity(0.35),
                        style: StrokeStyle(lineWidth: lineWidth + 24, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 22)
                    .animation(.easeInOut(duration: 1.4), value: color)
                    .animation(.easeInOut(duration: 0.6), value: progress)

                Circle()
                    .trim(from: 0, to: trim)
                    .stroke(
                        color.opacity(0.65),
                        style: StrokeStyle(lineWidth: lineWidth + 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 11)
                    .animation(.easeInOut(duration: 1.4), value: color)
                    .animation(.easeInOut(duration: 0.6), value: progress)
            }

            // 5. 主活动弧
            Circle()
                .trim(from: 0, to: trim)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.4), value: color)
                .animation(.easeInOut(duration: 0.6), value: progress)

            // 6. 中心实心盘（让大数字与圆环分层，更立体；深色模式自动换成暖夜色）
            if showCenterDisk {
                Circle()
                    .fill(AppColor.cardSurface)
                    .padding(lineWidth + 14)
                    .shadow(color: .black.opacity(0.05), radius: 12, y: 3)
            }

            // 7. 阶段图标标记（沿圆环周长漂浮）
            ForEach(markers) { marker in
                markerControl(marker)
                    .offset(offset(for: marker.fraction))
                    .animation(.easeInOut(duration: 0.6), value: marker.isActive)
            }
        }
        .scaleEffect(breathing ? 1.006 : 0.994)
        .animation(
            .easeInOut(duration: 4).repeatForever(autoreverses: true),
            value: breathing
        )
        .onAppear { breathing = true }
    }

    @ViewBuilder
    private func markerControl(_ marker: StageMarker) -> some View {
        if let onMarkerTap {
            GeometryReader { proxy in
                Button {
                    let frame = proxy.frame(in: .named("homeRoot"))
                    onMarkerTap(marker, CGPoint(x: frame.midX, y: frame.midY))
                } label: {
                    StageMarkerView(marker: marker)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(marker.title)
            }
            .frame(width: 24, height: 24)
        } else {
            StageMarkerView(marker: marker)
        }
    }

    /// 把 fraction（0...1）转成环上对应位置的 (x, y) 偏移，以中心为原点、12 点为起点顺时针。
    private func offset(for fraction: Double) -> CGSize {
        let theta = fraction * 2 * .pi
        let r = radius
        return CGSize(width: r * sin(theta), height: -r * cos(theta))
    }
}

private struct StageMarkerView: View {
    let marker: StageMarker

    var body: some View {
        Image(systemName: marker.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(marker.isActive ? Color.white : AppColor.textSecondary.opacity(0.55))
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(marker.isActive ? marker.color : AppColor.cardSurface)
            )
            .overlay(
                Circle().stroke(
                    marker.isActive ? marker.color.opacity(0.4) : AppColor.restGraySoft,
                    lineWidth: 1
                )
            )
            .shadow(color: marker.isActive ? marker.color.opacity(0.35) : .black.opacity(0.06),
                    radius: marker.isActive ? 6 : 3, y: 1)
    }
}
