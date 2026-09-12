import SwiftUI

struct LightBarMarker: Identifiable, Equatable {
    let id: String
    let fraction: Double
    let symbol: String
    let title: String
    let color: Color
    let isActive: Bool
}

struct LightBar: View {
    var progress: Double
    var color: Color
    var trackColor: Color = AppColor.ringTrack
    var markers: [LightBarMarker] = []
    var barHeight: CGFloat = 4
    var markerSize: CGFloat = 18
    var onMarkerTap: ((LightBarMarker, CGPoint) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerActive = false

    private var clampedProgress: CGFloat {
        max(0.001, min(CGFloat(progress), 1))
    }

    var body: some View {
        // 单层 GeometryReader 提供宽度，ZStack 让 bar 和 marker 在同一垂直中心线上
        // 重叠（marker 中心 = bar 中心 = 容器中心 = markerSize / 2）。
        GeometryReader { geo in
            let fillWidth = max(barHeight, geo.size.width * clampedProgress)
            let shimmerWidth = min(86, max(32, fillWidth * 0.42))

            ZStack {
                // Bar：vertical center = ZStack center
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor.opacity(0.55))
                        .frame(height: barHeight)
                        .overlay(
                            Capsule()
                                .stroke(AppColor.highlightEdge.opacity(0.18), lineWidth: 0.5)
                                .frame(height: barHeight)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.92), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: barHeight)
                        .overlay(alignment: .leading) {
                            if !reduceMotion && progress > 0.04 {
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        AppColor.highlightEdge.opacity(0.48),
                                        .clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: shimmerWidth, height: barHeight + 8)
                                .blur(radius: 0.5)
                                .blendMode(.plusLighter)
                                .offset(x: shimmerActive ? fillWidth + shimmerWidth : -shimmerWidth * 1.4)
                                .animation(
                                    .linear(duration: 3.2).repeatForever(autoreverses: false),
                                    value: shimmerActive
                                )
                            }
                        }
                        .clipShape(Capsule())
                        .shadow(color: color.opacity(0.55), radius: 6)
                        .shadow(color: color.opacity(0.40), radius: 14)
                }
                .frame(height: barHeight)

                // Markers 在 bar 中线上重叠
                ForEach(markers) { marker in
                    markerControl(marker)
                        .position(
                            x: geo.size.width * min(max(marker.fraction, 0), 1),
                            y: geo.size.height / 2
                        )
                }
            }
        }
        .frame(height: markerSize)
        .onAppear { shimmerActive = true }
    }

    @ViewBuilder
    private func markerControl(_ marker: LightBarMarker) -> some View {
        if let onMarkerTap {
            GeometryReader { proxy in
                Button {
                    let frame = proxy.frame(in: .named("homeRoot"))
                    onMarkerTap(marker, CGPoint(x: frame.midX, y: frame.midY))
                } label: {
                    markerChip(marker)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(marker.title)
            }
            .frame(width: markerSize, height: markerSize)
        } else {
            markerChip(marker)
        }
    }

    private func markerChip(_ marker: LightBarMarker) -> some View {
        ZStack {
            Circle()
                .fill(marker.isActive ? marker.color : AppColor.cardSurface.opacity(0.85))
                .shadow(
                    color: marker.isActive ? marker.color.opacity(0.55) : AppColor.shadowAmbient.opacity(0.10),
                    radius: marker.isActive ? 6 : 2,
                    y: marker.isActive ? 2 : 1
                )

            if marker.isActive {
                Circle()
                    .trim(from: 0.62, to: 0.88)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.7), .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blendMode(.plusLighter)
            }

            Circle()
                .stroke(
                    marker.isActive ? marker.color.opacity(0.5) : AppColor.restGraySoft,
                    lineWidth: 0.7
                )

            Image(systemName: marker.symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(marker.isActive ? Color.white : AppColor.textSecondary.opacity(0.55))
        }
        .frame(width: markerSize, height: markerSize)
    }
}
