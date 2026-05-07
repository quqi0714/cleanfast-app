import SwiftUI

struct OnboardingView: View {
    enum Step {
        case welcome
        case howItWorks
        case pickTarget
        case pickTimingMode
        case pickHomeStyle
        case notifications
    }

    @ObservedObject var vm: FastingTimerViewModel
    @EnvironmentObject private var settings: AppSettingsStore
    var onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var targetMinutes: Int = PersistenceService.shared.targetMinutes
    @State private var timingMode: TimingMode = PersistenceService.shared.timingMode
    @State private var notificationRequestInFlight = false

    private static let presets: [FastingPlanPreset] = [
        FastingPlanPreset(hours: 12, name: "温和开始", badge: "新手友好",
                          detail: "进食窗口更宽松，适合先建立节奏。"),
        FastingPlanPreset(hours: 14, name: "稳步适应", badge: nil,
                          detail: "比 12:12 稍集中，日常安排仍然轻松。"),
        FastingPlanPreset(hours: 16, name: "日常推荐", badge: "推荐",
                          detail: "多数人更容易长期坚持，平衡感比较好。"),
        FastingPlanPreset(hours: 18, name: "进阶尝试", badge: nil,
                          detail: "空腹时间更长，适合已经适应 16:8 后再试。"),
        FastingPlanPreset(hours: 20, name: "短窗计划", badge: nil,
                          detail: "进食窗口较短，建议身体舒服、有经验时再用。"),
    ]

    var body: some View {
        ZStack {
            AmbientBackground(accentColor: AppColor.sunOrange, intensity: .subtle)

            content
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:    welcomePage
        case .howItWorks: howItWorksPage
        case .pickTarget: pickTargetPage
        case .pickTimingMode: pickTimingModePage
        case .pickHomeStyle: pickHomeStylePage
        case .notifications: notificationPage
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "sun.haze.fill")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(AppColor.sunOrange)
                    .shadow(color: AppColor.sunOrange.opacity(0.35), radius: 24)
                Text("轻断食时钟")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }
            ZHText(content: "一个温和的轻断食计时器。\n不打卡，不催促，不制造焦虑。\n按你的节奏来。",
                   size: 16, color: AppColor.textSecondary,
                   lineSpacing: 6, alignment: .center)
            Spacer()
            PrimaryButton(title: "开始") {
                Haptics.play(.primaryAdvance)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    step = .howItWorks
                }
            }
        }
    }

    // MARK: - How it works

    private var howItWorksPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("先简单设置一下")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("很简单，按你的节奏来。")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 14) {
                        bulletCard(
                            symbol: "timer",
                            title: "先选一个节奏",
                            body: "选一个适合今天的断食时长。\n进食窗口会自动算好。"
                        )
                        bulletCard(
                            symbol: "play.circle",
                            title: "准备好了再开始",
                            body: "不会替你开始。\n点下「开始断食」后，才开始计时。"
                        )
                        bulletCard(
                            symbol: "infinity",
                            title: "到了目标，也不催你",
                            body: "到了以后会继续计时。\n什么时候结束，由你决定。"
                        )
                        bulletCard(
                            symbol: "fork.knife",
                            title: "结束后，进入进食窗口",
                            body: "进食窗口也会继续计时。\n准备好下一轮时，点「现在开始断食」。"
                        )
                        bulletCard(
                            symbol: "moon.zzz",
                            title: "想休息一下？",
                            body: "可以随时跳过今天。明天回来就好。"
                        )
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            PrimaryButton(title: "下一步") {
                Haptics.play(.primaryAdvance)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    step = .pickTarget
                }
            }
            .padding(.top, 8)
        }
    }

    private func bulletCard(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColor.sunOrange)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                ZHText(content: title, size: 16, weight: .semibold,
                       color: AppColor.textPrimary)
                ZHText(content: body, size: 13,
                       color: AppColor.textSecondary, lineSpacing: 2)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape
                .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Pick target

    private var pickTargetPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("选择断食时长")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        ZHText(content: "进食窗口 = 24 − 断食。之后还可以在设置里改。",
                               size: 13, color: AppColor.textSecondary,
                               alignment: .center)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 10) {
                        ForEach(Self.presets) { preset in
                            presetRow(preset)
                        }
                        customRow
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                SecondaryButton(title: "返回") {
                    Haptics.play(.cancel)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        step = .howItWorks
                    }
                }
                PrimaryButton(title: "下一步") {
                    Haptics.play(.primaryAdvance)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        step = .pickTimingMode
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func presetRow(_ preset: FastingPlanPreset) -> some View {
        let hours = preset.hours
        let minutes = hours * 60
        let selected = targetMinutes == minutes
        let eat = 24 - hours
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            Haptics.play(.selection)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                targetMinutes = minutes
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("\(hours):\(eat)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(preset.name)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                        if let badge = preset.badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColor.textOnAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppColor.sunOrange, in: Capsule())
                        }
                    }
                    ZHText(content: preset.detail, size: 12,
                           color: AppColor.textSecondary, lineSpacing: 2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.sunOrange)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .stroke(selected ? AppColor.sunOrange.opacity(0.6) : Color.white.opacity(0.5), lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var customRow: some View {
        let isCustom = !Self.presets.contains { $0.hours == targetMinutes / 60 }
        let h = targetMinutes / 60
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 12) {
            Text("自定义")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text("\(h):\(24 - h)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isCustom ? AppColor.sunOrange : AppColor.textSecondary)
                .monospacedDigit()
            Stepper("", value: Binding(
                get: { h },
                set: { newHour in
                    Haptics.play(.selection)
                    targetMinutes = newHour * 60
                }
            ), in: 1...23)
            .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape
                .stroke(isCustom ? AppColor.sunOrange.opacity(0.6) : Color.white.opacity(0.5),
                        lineWidth: isCustom ? 1.5 : 0.5)
        )
    }

    // MARK: - Pick timing mode

    private var pickTimingModePage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("选择切换方式")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        ZHText(content: "之后也可以在设置里随时更改。",
                               size: 13, color: AppColor.textSecondary,
                               alignment: .center)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 12) {
                        timingModeCard(
                            mode: .manual,
                            titleSuffix: String(localized: "（推荐）"),
                            detail: "到点后只提醒，不自动切换。\n准备好了再轻触进入下一段。"
                        )
                        timingModeCard(
                            mode: .automatic,
                            titleSuffix: "",
                            detail: "按设定的断食和进食窗口自动切换。\n打开时可以直接看到当前是否在进食窗口。"
                        )
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                SecondaryButton(title: "返回") {
                    Haptics.play(.cancel)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        step = .pickTarget
                    }
                }
                PrimaryButton(title: "下一步") {
                    Haptics.play(.primaryAdvance)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        step = .pickHomeStyle
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func timingModeCard(mode: TimingMode, titleSuffix: String, detail: LocalizedStringKey) -> some View {
        let selected = timingMode == mode
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            Haptics.play(.modeChanged)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                timingMode = mode
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode == .manual ? "hand.tap.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? AppColor.sunOrange : AppColor.textSecondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.title + titleSuffix)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    ZHText(content: detail, size: 13, color: AppColor.textSecondary, lineSpacing: 3)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.sunOrange)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .stroke(selected ? AppColor.sunOrange.opacity(0.6) : Color.white.opacity(0.5),
                            lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pick home style

    private var pickHomeStylePage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("选择首页风格")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        ZHText(content: "之后也可以在设置里随时更改。",
                               size: 13, color: AppColor.textSecondary,
                               alignment: .center)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 12) {
                        homeStyleCard(.classic)
                        homeStyleCard(.cinematic)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                SecondaryButton(title: "返回") {
                    Haptics.play(.cancel)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        step = .pickTimingMode
                    }
                }
                PrimaryButton(title: "下一步") {
                    Haptics.play(.primaryAdvance)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        step = .notifications
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func homeStyleCard(_ style: HomeStyle) -> some View {
        let selected = settings.homeStyle == style
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button {
            Haptics.play(.modeChanged)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                settings.homeStyle = style
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(style.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColor.sunOrange)
                    }
                }

                homeStylePreview(style)
                    .frame(height: 132)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .stroke(selected ? AppColor.sunOrange.opacity(0.62) : Color.white.opacity(0.5),
                            lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func homeStylePreview(_ style: HomeStyle) -> some View {
        switch style {
        case .classic:
            classicPreview
        case .cinematic:
            cinematicPreview
        }
    }

    private var classicPreview: some View {
        ZStack {
            LinearGradient(
                colors: [AppColor.backgroundCream, AppColor.backgroundWarm],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(AppColor.ringTrack, lineWidth: 8)
                        .frame(width: 76, height: 76)
                    Circle()
                        .trim(from: 0, to: 0.42)
                        .stroke(AppColor.sunOrange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 76, height: 76)
                    VStack(spacing: 2) {
                        Text("断食中")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColor.textSecondary)
                        Text("04:09")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }

                Capsule()
                    .fill(AppColor.sunOrange.opacity(0.88))
                    .frame(width: 112, height: 18)
            }
        }
    }

    private var cinematicPreview: some View {
        ZStack {
            LinearGradient(
                colors: [AppColor.backgroundWarm, AppColor.backgroundSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppColor.sunOrange.opacity(0.38), .clear],
                center: UnitPoint(x: 0.52, y: 0.28),
                startRadius: 0,
                endRadius: 150
            )
            .blendMode(.plusLighter)

            VStack(spacing: 14) {
                Text("断 食 进 行 中")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.72))

                Text("04:09")
                    .font(.system(size: 38, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: 8) {
                    Capsule()
                        .fill(AppColor.ringTrack.opacity(0.7))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.sunOrange)
                                .frame(width: 64)
                        }
                        .frame(width: 156, height: 4)

                    Capsule()
                        .stroke(AppColor.sunOrange.opacity(0.72), lineWidth: 1)
                        .frame(width: 132, height: 22)
                }
            }
        }
    }

    // MARK: - Notification permission

    private var notificationPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(AppColor.sunOrange)
                    .shadow(color: AppColor.sunOrange.opacity(0.28), radius: 22)

                VStack(spacing: 8) {
                    Text("需要时提醒你")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    ZHText(content: "我们只在断食或进食目标到达时提醒你。\n不会打卡催促，也不会发送多余通知。",
                           size: 14, color: AppColor.textSecondary,
                           lineSpacing: 4, alignment: .center)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                PrimaryButton(title: notificationRequestInFlight ? "请稍候" : "开启提醒") {
                    requestNotificationsAndFinish()
                }
                .disabled(notificationRequestInFlight)
                .opacity(notificationRequestInFlight ? 0.7 : 1)

                SecondaryButton(title: "暂时不用") {
                    Haptics.play(.cancel)
                    finish(notificationEnabled: false, playHaptic: false)
                }
            }
        }
    }

    private func requestNotificationsAndFinish() {
        guard !notificationRequestInFlight else { return }
        notificationRequestInFlight = true
        Haptics.play(.primaryAdvance)
        Task { @MainActor in
            let granted = await NotificationService.shared.requestPermission()
            notificationRequestInFlight = false
            finish(notificationEnabled: granted, playHaptic: false)
        }
    }

    private func finish(notificationEnabled: Bool? = nil, playHaptic: Bool = true) {
        if playHaptic {
            Haptics.play(.primaryAdvance)
        }
        if let notificationEnabled {
            PersistenceService.shared.notificationEnabled = notificationEnabled
        }
        vm.updateTargetMinutes(targetMinutes)
        vm.updateTimingMode(timingMode)
        PersistenceService.shared.hasCompletedOnboarding = true
        onFinish()
    }
}

private struct FastingPlanPreset: Identifiable {
    let hours: Int
    let name: LocalizedStringKey
    let badge: LocalizedStringKey?
    let detail: LocalizedStringKey

    var id: Int { hours }
}
