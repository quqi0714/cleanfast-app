import SwiftUI
import Combine
import StoreKit

struct HomeView: View {
    @ObservedObject var vm: FastingTimerViewModel
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.requestReview) private var requestReview
    @State private var showSettings = false
    @State private var showAdjustStartTime = false
    @State private var showSkipConfirmation = false
    @State private var manualTimeAction: ManualTimeAction?
    @State private var animatedProgress: Double = 0
    @State private var didEnter = false
    @State private var stageInfo: StageInfo?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private let ringSize: CGFloat = 280
    private let ringSlotHeight: CGFloat = 340

    var body: some View {
        ZStack {
            backgroundView.ignoresSafeArea()
            homeLayout
            if let stageInfo {
                stageInfoOverlay(stageInfo)
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .coordinateSpace(name: "homeRoot")
        .animation(.easeInOut(duration: 0.18), value: stageInfo?.id)
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: vm)
        }
        .sheet(isPresented: $showAdjustStartTime) {
            AdjustStartTimeView(vm: vm)
                .presentationDetents([.height(420)])
        }
        .sheet(item: $manualTimeAction) { action in
            ManualTimePickerView(action: action) { selectedDate in
                handleManualTime(action, at: selectedDate)
            }
            .presentationDetents([.height(420)])
        }
        .confirmationDialog("今天先休息？", isPresented: $showSkipConfirmation, titleVisibility: .visible) {
            Button("今天先休息", role: .destructive) {
                Haptics.play(.secondaryAction)
                vm.skipToday()
            }
            Button("取消", role: .cancel) {
                Haptics.play(.cancel)
            }
        } message: {
            Text(skipConfirmationMessage)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.rehydrate() }
        }
        .onAppear {
            if !didEnter {
                didEnter = true
                animatedProgress = 0
                withAnimation(.spring(response: 1.2, dampingFraction: 0.75).delay(0.1)) {
                    animatedProgress = vm.progress
                }
            }
            // 预热常用 generator，消除首次点击 50–200ms 的延迟
            Haptics.prepare()
        }
        .onChange(of: vm.progress) { _, new in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = new
            }
        }
        .onChange(of: vm.currentStage) { _, _ in
            if vm.state == .fasting { Haptics.play(.stageChange) }
        }
        .onChange(of: vm.hasReachedTarget) { _, reached in
            if reached && (vm.state == .fasting || vm.state == .eating) {
                Haptics.play(.targetReached)
            }
        }
        .onChange(of: vm.state) { _, _ in
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                animatedProgress = vm.progress
            }
        }
        .onChange(of: vm.pendingReviewRequest) { _, pending in
            guard pending else { return }
            // 稍等状态切换动画落定再弹系统评分，避免打断高光时刻
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                requestReview()
                vm.markReviewRequestHandled()
            }
        }
    }

    @ViewBuilder
    private var homeLayout: some View {
        switch settings.homeStyle {
        case .classic:
            classicHomeLayout
        case .cinematic:
            cinematicHomeLayout
        }
    }

    @ViewBuilder
    private var classicHomeLayout: some View {
        GeometryReader { geometry in
            if geometry.size.height < 720 || geometry.size.width < 390 {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        topBar
                        ringSection(size: compactRingSize(for: geometry))
                        stageCard
                        primaryActionArea
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 18) {
                    topBar
                    Spacer(minLength: 0)
                    ringSection(size: ringSize)
                        .frame(height: ringSlotHeight)
                    stageCard
                        .frame(minHeight: 110, alignment: .top)
                    Spacer(minLength: 0)
                    primaryActionArea
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    private func compactRingSize(for geometry: GeometryProxy) -> CGFloat {
        let widthBound = max(226, geometry.size.width - 48)
        let heightBound = geometry.size.height * 0.34
        return min(ringSize, max(226, min(widthBound, heightBound)))
    }

    private var cinematicHomeLayout: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 12)
                .padding(.horizontal, 28)
            Spacer()
            cinemaTimeBlock
                .padding(.horizontal, 24)
            Spacer()
            bottomBlock
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
        }
    }

    private func stageInfoOverlay(_ info: StageInfo) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        hideStageInfo()
                    }

                switch info.kind {
                case .detail:
                    stageInfoCard(info)
                        .padding(.horizontal, 28)
                case .marker:
                    markerInfoCard(info)
                        .position(markerInfoPosition(anchor: info.anchor, in: geo.size))
                }
            }
        }
    }

    private func stageInfoCard(_ info: StageInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(info.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: info.color.opacity(0.55), radius: 6)
                Text(info.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }

            if let message = info.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.5)
        )
        .shadow(color: info.color.opacity(0.18), radius: 24, y: 10)
        .shadow(color: AppColor.shadowAmbient.opacity(0.10), radius: 20, y: 14)
        .onTapGesture {}
    }

    private func markerInfoCard(_ info: StageInfo) -> some View {
        Text(info.title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(info.color)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(info.color.opacity(0.38), lineWidth: 0.8)
            )
            .shadow(color: info.color.opacity(0.22), radius: 14, y: 6)
            .shadow(color: AppColor.shadowAmbient.opacity(0.10), radius: 12, y: 8)
            .onTapGesture {}
    }

    private func markerInfoPosition(anchor: CGPoint?, in size: CGSize) -> CGPoint {
        let anchor = anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let x = min(max(anchor.x, 58), size.width - 58)
        let verticalOffset: CGFloat = anchor.y > size.height * 0.45 ? -38 : 38
        let y = min(max(anchor.y + verticalOffset, 72), size.height - 72)
        return CGPoint(x: x, y: y)
    }

    private func showStageDetail(title: String, message: String, color: Color) {
        Haptics.play(.selection)
        withAnimation(.easeInOut(duration: 0.18)) {
            stageInfo = StageInfo(title: title, message: message, color: color, anchor: nil, kind: .detail)
        }
    }

    private func showMarkerInfo(title: String, color: Color, anchor: CGPoint) {
        Haptics.play(.selection)
        withAnimation(.easeInOut(duration: 0.18)) {
            stageInfo = StageInfo(title: title, message: nil, color: color, anchor: anchor, kind: .marker)
        }
    }

    private func hideStageInfo() {
        Haptics.play(.cancel)
        withAnimation(.easeInOut(duration: 0.16)) {
            stageInfo = nil
        }
    }

    // MARK: - Header（标题 + 计划胶囊 + 跳过按钮）

    // MARK: - Top bar (shared by both themes)

    /// 两个主题共用的顶栏：左 = 状态胶囊，右 = 操作图标胶囊。
    /// 保持两侧胶囊高度一致（统一 36pt），描边/材质统一，呼吸感对齐。
    private var topBar: some View {
        HStack(spacing: 12) {
            // 左：状态点 + 当前会话/目标信息
            HStack(spacing: 8) {
                Circle()
                    .fill(ringColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: ringColor.opacity(0.7), radius: 5)
                    .shadow(color: ringColor.opacity(0.4), radius: 12)
                Text(topBarLeftText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(topBarChromeColor)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: topBarLeftText)
            }
            .padding(.horizontal, 12)
            .topPillStyle()

            Spacer()

            // 右：1–3 个操作图标
            HStack(spacing: 4) {
                if vm.canAdjustCurrentStartTime {
                    cornerButton(symbol: "clock.arrow.circlepath", label: "调整开始时间") {
                        Haptics.play(.selection)
                        showAdjustStartTime = true
                    }
                }
                if vm.state != .skipped {
                    cornerButton(symbol: "moon.zzz", label: "跳过今天") {
                        Haptics.play(.selection)
                        showSkipConfirmation = true
                    }
                }
                cornerButton(symbol: "slider.horizontal.3", label: "设置") {
                    Haptics.play(.selection)
                    showSettings = true
                }
            }
            .padding(.horizontal, 4)
            .topPillStyle()
        }
    }

    private func cornerButton(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(topBarChromeColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var topBarChromeColor: Color {
        AppColor.textPrimary.opacity(0.82)
    }

    private var topBarLeftText: String {
        if let start = vm.session?.startDate {
            return String(localized: "始于 \(TimeFormat.relativeClock(start))")
        }
        let fastingHours = vm.targetMinutes / 60
        return String(localized: "目标 \(fastingHours):\(24 - fastingHours)")
    }

    private var cinemaTimeBlock: some View {
        VStack(spacing: 18) {
            Text(stateLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(cinematicStatusColor)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: stateLabel)
                .shadow(color: AppColor.shadowAmbient.opacity(0.24), radius: 8, y: 3)

            // 跳过态用月亮中心位替换大数字，避免冰冷的 "—" 占位
            if vm.state == .skipped {
                SkippedCenterpiece(size: 76)
                    .frame(height: 96)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Text(elapsedDisplay)
                    .font(.system(size: 86, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: elapsedDisplay)
                    .shadow(color: AppColor.shadowAmbient.opacity(0.06), radius: 18, y: 10)
                    .shadow(color: ringColor.opacity(0.18), radius: 30)
                    .transition(.opacity)
            }

            secondaryRow
        }
        .animation(.easeInOut(duration: 0.45), value: vm.state == .skipped)
    }

    @ViewBuilder
    private var secondaryRow: some View {
        switch vm.state {
        case .fasting, .eating:
            HStack(spacing: 14) {
                stageLabelButton
                Text("·")
                    .foregroundStyle(cinematicSecondaryInfoColor.opacity(0.55))
                HStack(spacing: 4) {
                    if vm.hasReachedTarget {
                        Text("+")
                            .foregroundStyle(cinematicSecondaryInfoColor)
                    }
                    Text(cinematicSecondaryClockValue)
                        .foregroundStyle(cinematicSecondaryInfoColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .animation(.snappy(duration: 0.35), value: cinematicSecondaryClockValue)
            .shadow(color: AppColor.shadowAmbient.opacity(0.22), radius: 8, y: 3)
        case .notStarted:
            if let pendingAutomaticResumeText {
                Text(pendingAutomaticResumeText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                Text("准备好了，就开始")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
            }
        case .skipped:
            Text("生活也需要弹性")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private var stageLabelButton: some View {
        if vm.state == .fasting {
            Button {
                showStageDetail(
                    title: vm.currentStage.title,
                    message: vm.currentStage.message,
                    color: vm.currentStage.color
                )
            } label: {
                HStack(spacing: 5) {
                    Text(stageOrSubtitle)
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(cinematicStageLabelColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(stageOrSubtitle)，查看说明"))
        } else {
            Text(stageOrSubtitle)
                .foregroundStyle(cinematicStageLabelColor)
        }
    }

    private var cinematicSecondaryClockValue: String {
        let elapsedInt = Int(vm.elapsed)
        let totalInt = Int(vm.activeTargetDuration)
        if vm.hasReachedTarget {
            return TimeFormat.duration(TimeInterval(max(0, elapsedInt - totalInt)))
        }
        return TimeFormat.duration(TimeInterval(max(0, totalInt - elapsedInt)))
    }

    private var stageOrSubtitle: String {
        switch vm.state {
        case .fasting: return vm.currentStage.title
        case .eating: return vm.hasReachedTarget ? String(localized: "进食已满") : String(localized: "进食窗口")
        default: return ""
        }
    }

    private var bottomBlock: some View {
        VStack(spacing: 22) {
            LightBar(
                progress: animatedProgress,
                color: ringColor,
                markers: lightBarMarkers
            ) { marker, anchor in
                showMarkerInfo(title: marker.title, color: marker.color, anchor: anchor)
            }
                .animation(.easeInOut(duration: 0.6), value: ringColor)

            Text(targetText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppColor.textSecondary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: targetText)

            cinemaActionButton
                .padding(.top, 8)
        }
    }

    private var lightBarMarkers: [LightBarMarker] {
        guard vm.state == .fasting else { return [] }
        let target = vm.activeTargetDuration / 3600
        guard target > 0 else { return [] }

        let elapsedHours = vm.elapsed / 3600
        let stageDefs: [(hour: Double, stage: FastingStage, symbol: String)] = [
            (2,  .bloodSugarSettling, "drop.fill"),
            (4,  .glycogenUse,        "bolt.fill"),
            (8,  .fuelSwitch,         "arrow.triangle.2.circlepath"),
            (12, .deepFueling,        "flame.fill"),
        ]

        return stageDefs.compactMap { def in
            let fraction = def.hour / target
            guard fraction <= 1.0 else { return nil }
            return LightBarMarker(
                id: "\(Int(def.hour))h",
                fraction: fraction,
                symbol: def.symbol,
                title: def.stage.title,
                color: def.stage.color,
                isActive: elapsedHours >= def.hour
            )
        }
    }

    private var cinemaActionButton: some View {
        Button {
            if shouldOpenTimePicker || (vm.timingMode == .automatic && (vm.state == .fasting || vm.state == .eating)) {
                Haptics.play(.selection)
            } else {
                Haptics.play(.primaryAdvance)
            }
            primaryAction()
        } label: {
            HStack(spacing: 12) {
                Text(primaryTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Image(systemName: primaryArrowSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ringColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(
                Capsule().stroke(
                    LinearGradient(
                        colors: [
                            ringColor.opacity(0.85),
                            ringColor.opacity(0.30),
                            ringColor.opacity(0.85),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.4
                )
            )
            .shadow(color: ringColor.opacity(0.45), radius: 22)
            .shadow(color: AppColor.shadowAmbient.opacity(0.10), radius: 14, x: 4, y: 10)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.6), value: ringColor)
    }

    private var primaryArrowSymbol: String {
        vm.state == .skipped ? "arrow.uturn.backward" : "arrow.right"
    }

    private var pendingAutomaticResumeDate: Date? {
        guard vm.timingMode == .automatic,
              vm.state == .notStarted,
              let resumeDay = PersistenceService.shared.automaticResumeDateString,
              let startMinute = PersistenceService.shared.automaticFastingStartMinute,
              let date = ScheduleService().date(forDayString: resumeDay, minuteOfDay: startMinute),
              date > vm.now
        else { return nil }
        return date
    }

    private var pendingAutomaticResumeText: String? {
        guard let date = pendingAutomaticResumeDate else { return nil }
        return String(localized: "自动恢复于 \(TimeFormat.relativeClock(date))")
    }

    private var stateLabel: String {
        switch vm.state {
        case .notStarted: return String(localized: "准 备 中")
        case .fasting: return vm.hasReachedTarget ? String(localized: "超 额 完 成") : String(localized: "断 食 进 行 中")
        case .eating: return vm.hasReachedTarget ? String(localized: "进 食 已 满") : String(localized: "进 食 窗 口")
        case .skipped: return String(localized: "今 日 休 息")
        }
    }

    private var cinematicStatusColor: Color {
        AppColor.textPrimary.opacity(0.90)
    }

    private var cinematicStageLabelColor: Color {
        AppColor.textPrimary.opacity(0.84)
    }

    private var cinematicSecondaryInfoColor: Color {
        AppColor.textPrimary.opacity(0.68)
    }

    // MARK: - Ring section

    private func ringSection(size: CGFloat) -> some View {
        let scale = size / ringSize

        return ZStack {
            ProgressRingView(
                progress: animatedProgress,
                color: ringColor,
                trackColor: ringTrackColor,
                markers: ringMarkers,
                radius: size / 2
            ) { marker, anchor in
                showMarkerInfo(title: marker.title, color: marker.color, anchor: anchor)
            }
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.6), value: ringTrackColor)

            Text(stateTitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textSecondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: stateTitle)
                .offset(y: -64 * scale)

            // 跳过态用月亮中心位替换大数字
            if vm.state == .skipped {
                SkippedCenterpiece(size: 56 * scale)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Text(elapsedDisplay)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: elapsedDisplay)
                    .transition(.opacity)
            }

            secondaryClock
                .offset(y: 42 * scale)

            Text(targetText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppColor.textSecondary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: size - 80 * scale)
                .offset(y: 74 * scale)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var secondaryClock: some View {
        switch vm.state {
        case .fasting, .eating:
            HStack(spacing: 6) {
                Text(vm.hasReachedTarget ? LocalizedStringKey("已超额") : LocalizedStringKey("还剩"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryClockColor)
                Text(secondaryClockValue)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryClockColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: secondaryClockValue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(secondaryClockColor.opacity(0.12), in: Capsule())
        default:
            Color.clear.frame(height: 1)
        }
    }

    private var secondaryClockValue: String {
        let elapsedInt = Int(vm.elapsed)
        let totalInt = Int(vm.activeTargetDuration)
        if vm.hasReachedTarget {
            return "+" + TimeFormat.duration(TimeInterval(max(0, elapsedInt - totalInt)))
        }
        return TimeFormat.duration(TimeInterval(max(0, totalInt - elapsedInt)))
    }

    private var secondaryClockColor: Color {
        switch vm.state {
        case .fasting:
            return vm.hasReachedTarget ? AppColor.stageCompleted : AppColor.textSecondary
        case .eating:
            return vm.hasReachedTarget ? AppColor.sunOrange : AppColor.stageCompleted
        default:
            return AppColor.textSecondary
        }
    }

    // MARK: - Ring markers

    /// 5 个生理阶段的标记（drop / bolt / cycle / flame）按"该阶段起始小时 / 目标小时"
    /// 算位置漂在环上。超出目标时长的标记自动隐藏。
    private var ringMarkers: [StageMarker] {
        guard vm.state == .fasting else { return [] }
        let target = vm.activeTargetDuration / 3600
        guard target > 0 else { return [] }

        let elapsedHours = vm.elapsed / 3600
        let stageDefs: [(hour: Double, stage: FastingStage, symbol: String)] = [
            (2,  .bloodSugarSettling, "drop.fill"),
            (4,  .glycogenUse,        "bolt.fill"),
            (8,  .fuelSwitch,         "arrow.triangle.2.circlepath"),
            (12, .deepFueling,        "flame.fill"),
        ]

        return stageDefs.compactMap { def in
            let f = def.hour / target
            guard f <= 1.0 else { return nil }
            return StageMarker(
                id: "\(Int(def.hour))h",
                fraction: f,
                symbol: def.symbol,
                title: def.stage.title,
                color: def.stage.color,
                isActive: elapsedHours >= def.hour
            )
        }
    }

    // MARK: - Stage card

    private var stageCard: some View {
        GlassCardView {
            VStack(alignment: .leading, spacing: 6) {
                ZHText(verbatim: stageTitle, size: 17, weight: .semibold,
                       color: AppColor.textPrimary)
                    .id(stageTitle)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: stageTitle)

                ZHText(verbatim: stageMessage, size: 14, weight: .regular,
                       color: AppColor.textSecondary, lineSpacing: 3)
                    .id(stageMessage)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: stageMessage)
            }
        }
    }

    // MARK: - Buttons（底部只剩主按钮；进食态额外保留"结束进食"小副按钮）

    private var primaryActionArea: some View {
        PrimaryButton(title: primaryTitle, color: ringColor) {
            if shouldOpenTimePicker || (vm.timingMode == .automatic && (vm.state == .fasting || vm.state == .eating)) {
                Haptics.play(.selection)
            } else {
                Haptics.play(.primaryAdvance)
            }
            primaryAction()
        }
        .animation(.easeInOut(duration: 0.6), value: ringColor)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        switch settings.homeStyle {
        case .classic:
            classicBackgroundView
        case .cinematic:
            cinematicBackgroundView
        }
    }

    private var classicBackgroundView: some View {
        ZStack {
            // 经典主题也用 AmbientBackground，但强度比 cinematic 低一档
            // （活动时 .normal，未开始/休息时 .subtle）。
            // 这样经典也能享受到状态色温变化（断食暖、进食冷），
            // 但保持比 cinematic 更安静的氛围
            AmbientBackground(
                accentColor: ringColor,
                supportColor: ambientSupportColor,
                contrastColor: ambientContrastColor,
                intensity: vm.state == .fasting || vm.state == .eating ? .normal : .subtle
            )
            .animation(.easeInOut(duration: 1.4), value: vm.state)

            // 跟手势倾斜的辅助光晕（强度比 cinematic 略低，因为经典还有圆环本体提供焦点）
            RadialGradient(
                colors: [
                    ringColor.opacity(vm.state == .fasting || vm.state == .eating ? 0.20 : 0.10),
                    .clear
                ],
                center: lightCenter,
                startRadius: 0,
                endRadius: 420
            )
            .blendMode(.plusLighter)
            .animation(.easeInOut(duration: 1.4), value: ringColor)
            .animation(.easeInOut(duration: 1.4), value: vm.state)
        }
    }

    private var cinematicBackgroundView: some View {
        ZStack {
            AmbientBackground(
                accentColor: ringColor,
                supportColor: ambientSupportColor,
                contrastColor: ambientContrastColor,
                intensity: cinematicBackgroundIntensity
            )
            .animation(.easeInOut(duration: 1.4), value: vm.state)

            RadialGradient(
                colors: [
                    ringColor.opacity(cinematicRingGlowOpacity),
                    .clear
                ],
                center: lightCenter,
                startRadius: 0,
                endRadius: 520
            )
            .blendMode(.plusLighter)
            .animation(.easeInOut(duration: 1.4), value: ringColor)
            .animation(.easeInOut(duration: 1.4), value: vm.state)

            LinearGradient(
                colors: [.clear, AppColor.shadowAmbient.opacity(0.12)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Keep the light text readable over the cinematic eating glow.
            Color.black
                .opacity(cinematicBackgroundDimOpacity)
                .allowsHitTesting(false)
        }
    }

    private var cinematicBackgroundIntensity: AmbientBackground.Intensity {
        if vm.state == .eating && colorScheme == .dark {
            return .vibrant
        }
        return vm.state == .fasting || vm.state == .eating ? .cinematic : .normal
    }

    private var cinematicRingGlowOpacity: Double {
        if vm.state == .eating && colorScheme == .dark {
            return 0.12
        }
        return vm.state == .fasting || vm.state == .eating ? 0.30 : 0.14
    }

    private var cinematicBackgroundDimOpacity: Double {
        vm.state == .eating && colorScheme == .dark ? 0.18 : 0
    }

    /// 副光团颜色：断食态用暖橙、进食态用鼠尾草绿、休息态用冷蓝。
    /// 让整屏色温只往一个方向偏，状态可一眼分辨。
    /// 经典 + cinematic 共用此函数，故名前缀去掉 cinematic
    private var ambientSupportColor: Color {
        switch vm.state {
        case .fasting:    return AppColor.stageBloodSugarSettling
        case .eating:     return AppColor.sageGreen
        case .skipped:    return AppColor.restGray
        default:          return AppColor.stageGlycogenUse
        }
    }

    /// 第三光团颜色：与 support 同色系，强化色温
    private var ambientContrastColor: Color {
        switch vm.state {
        case .fasting:    return AppColor.stageDigesting
        case .eating:     return AppColor.mintGreenSoft
        case .skipped:    return AppColor.restGraySoft
        default:          return AppColor.mintGreen
        }
    }

    /// 主辅助光晕中心点（固定）。原本跟陀螺仪联动，砍掉之后保持静态位置。
    private var lightCenter: UnitPoint { UnitPoint(x: 0.5, y: 0.22) }

    // MARK: - State-driven values

    private var ringColor: Color {
        switch vm.state {
        case .notStarted: return AppColor.sunOrange
        case .fasting:    return vm.currentStage.color
        case .eating:     return AppColor.stageCompleted
        case .skipped:    return AppColor.restGray
        }
    }

    private var ringTrackColor: Color {
        switch vm.state {
        case .notStarted, .skipped: return AppColor.ringTrack
        case .fasting, .eating:     return ringColor.opacity(0.38)
        }
    }

    private var stateTitle: String {
        switch vm.state {
        case .notStarted: return String(localized: "准备好了")
        case .fasting:
            if vm.timingMode == .automatic { return String(localized: "断食窗口") }
            return vm.hasReachedTarget ? String(localized: "超额完成中") : String(localized: "断食中")
        case .eating:
            if vm.timingMode == .automatic { return String(localized: "进食窗口") }
            return vm.hasReachedTarget ? String(localized: "进食时间已满") : String(localized: "进食窗口")
        case .skipped:    return String(localized: "今天休息")
        }
    }

    private var elapsedDisplay: String {
        switch vm.state {
        case .notStarted: return TimeFormat.duration(vm.fastingDuration)
        case .fasting:    return TimeFormat.duration(vm.elapsed)
        case .eating:     return TimeFormat.duration(vm.elapsed)
        case .skipped:    return "—"
        }
    }

    private var targetText: String {
        let lockedHours = Int(vm.activeTargetDuration / 3600)
        switch vm.state {
        case .notStarted:
            if pendingAutomaticResumeDate != nil {
                return String(localized: "按设定时间自动开始。")
            }
            return String(localized: "从你点击开始的那一刻计时")
        case .fasting:
            if let end = vm.sessionEndDate {
                if vm.timingMode == .automatic {
                    return String(localized: "断食窗口至 \(TimeFormat.relativeClock(end))")
                }
                return vm.hasReachedTarget
                    ? String(localized: "目标 \(lockedHours) 小时（已达成）")
                    : String(localized: "\(TimeFormat.relativeClock(end)) 后可以进食")
            }
            return String(localized: "目标 \(lockedHours) 小时")
        case .eating:
            if let end = vm.sessionEndDate {
                if vm.timingMode == .automatic {
                    return String(localized: "进食窗口至 \(TimeFormat.relativeClock(end))")
                }
                return vm.hasReachedTarget
                    ? String(localized: "进食窗口 \(lockedHours) 小时（已满）")
                    : String(localized: "建议 \(TimeFormat.relativeClock(end)) 前结束进食")
            }
            return String(localized: "进食窗口 \(lockedHours) 小时")
        case .skipped:
            return String(localized: "明天再继续就好")
        }
    }

    private var stageTitle: String {
        switch vm.state {
        case .notStarted:
            if let pendingAutomaticResumeDate {
                return String(localized: "自动恢复于 \(TimeFormat.relativeClock(pendingAutomaticResumeDate))")
            }
            return String(localized: "准备好了，就开始")
        case .fasting:
            return vm.currentStage.title
        case .eating:
            if vm.timingMode == .automatic { return String(localized: "现在是进食窗口") }
            return vm.hasReachedTarget ? String(localized: "进食窗口已满") : String(localized: "慢慢进食")
        case .skipped:    return String(localized: "生活也需要弹性")
        }
    }

    private var stageMessage: String {
        switch vm.state {
        case .notStarted:
            if pendingAutomaticResumeDate != nil {
                return String(localized: "按设定时间自动开始，准备好了也可以现在提前开始。")
            }
            return String(localized: "按你的节奏来，准备好了就开始。")
        case .fasting:
            if vm.hasReachedTarget {
                return String(localized: "目标已经到了。\n想继续也可以，身体舒服最重要。")
            }
            if vm.timingMode == .automatic {
                return vm.currentStage.message + "\n" + String(localized: "时钟会按你的设定自动进入下一段。")
            }
            return vm.currentStage.message
        case .eating:
            if vm.timingMode == .automatic {
                return String(localized: "现在处于进食窗口。\n时间到后会自动回到断食窗口。")
            }
            if vm.hasReachedTarget {
                return String(localized: "进食窗口建议时长已到。\n准备好就可以开始下一轮断食。")
            }
            return String(localized: "辛苦啦，开始温和进食吧。\n少量多次，记得喝水。")
        case .skipped:
            return String(localized: "今天休息一下没关系，明天再继续就好。")
        }
    }

    // MARK: - Actions

    private var primaryTitle: String {
        if vm.timingMode == .automatic {
            switch vm.state {
            case .notStarted:
                return pendingAutomaticResumeDate == nil
                    ? String(localized: "开始计时")
                    : String(localized: "现在提前开始")
            case .fasting, .eating: return String(localized: "今天休息")
            case .skipped: return String(localized: "恢复今天")
            }
        }
        switch vm.state {
        case .notStarted: return String(localized: "开始断食")
        case .fasting:    return String(localized: "结束断食")
        case .eating:     return String(localized: "现在开始断食")
        case .skipped:    return String(localized: "恢复今天")
        }
    }

    private func primaryAction() {
        if vm.timingMode == .automatic {
            switch vm.state {
            case .notStarted: vm.startFasting()
            case .fasting, .eating: showSkipConfirmation = true
            case .skipped: vm.resumeToday()
            }
            return
        }
        switch vm.state {
        case .notStarted: manualTimeAction = .startFasting
        case .fasting:    manualTimeAction = .startEating
        case .eating:     manualTimeAction = .restartFasting
        case .skipped:    vm.resumeToday()
        }
    }

    private var shouldOpenTimePicker: Bool {
        vm.timingMode == .manual && vm.state != .skipped
    }

    private func handleManualTime(_ action: ManualTimeAction, at date: Date) {
        switch action {
        case .startFasting, .restartFasting:
            vm.startFasting(at: date)
        case .startEating:
            vm.endFasting(at: date)
        }
    }

    private var skipConfirmationMessage: String {
        if vm.timingMode == .automatic {
            return String(localized: "今天先休息，明天会按设定时间自动开始。")
        }
        return String(localized: "今天先休息，准备好了记得回来点击“开始”。")
    }
}

#Preview {
    HomeView(vm: FastingTimerViewModel())
        .environmentObject(AppSettingsStore())
}

// MARK: - Shared top pill styling

private extension View {
    /// 顶栏胶囊统一样式：固定 36pt 高、ultraThinMaterial 底、对角线"玻璃边"渐变描边。
    /// 静态版本——靠左上→右下的渐变本身让描边带有微妙的"光从上方落下"感觉，
    /// 性能为零（无 CoreMotion / 无定时器 / 无 @Published）。
    func topPillStyle() -> some View {
        self
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                AppColor.highlightEdge.opacity(0.22),
                                AppColor.highlightEdge.opacity(0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
    }
}
