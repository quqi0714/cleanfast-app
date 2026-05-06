import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: FastingTimerViewModel
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetMinutes: Int = PersistenceService.shared.targetMinutes
    @State private var notificationEnabled: Bool = PersistenceService.shared.notificationEnabled
    @State private var timingMode: TimingMode = PersistenceService.shared.timingMode
    @State private var isRevertingNotificationToggle = false

    private static let presets: [Int] = [14, 16, 18, 20, 22]

    private var derivedEatingHours: Int {
        max(0, 24 - targetMinutes / 60)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.backgroundCream.ignoresSafeArea()

                Form {
                    appearanceSection
                    timingModeSection
                    targetSection
                    notificationSection
                    widgetSection
                    aboutSection
                    healthSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        Haptics.play(.cancel)
                        dismiss()
                    }
                    .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        vm.updateTargetMinutes(targetMinutes)
                        vm.updateTimingMode(timingMode)
                        Haptics.play(.primaryAdvance)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.sunOrange)
                }
            }
        }
        // colorScheme 由 WindowGroup 的 preferredColorScheme 通过环境传播下来，
        // 这里不再重复设置（重复设置会和 store 的 @Published 变化叠加触发多次重算）。
        .onAppear {
            targetMinutes = vm.targetMinutes
            timingMode = vm.timingMode
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: $settings.appAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.appAppearance) { _, _ in
                Haptics.play(.modeChanged)
            }

            Picker("首页风格", selection: $settings.homeStyle) {
                ForEach(HomeStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.homeStyle) { _, _ in
                Haptics.play(.modeChanged)
            }
        } header: {
            Text("外观")
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }

    private var timingModeSection: some View {
        Section {
            Picker("切换方式", selection: $timingMode) {
                ForEach(TimingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: timingMode) { _, _ in Haptics.play(.modeChanged) }
        } header: {
            Text("计时方式")
        } footer: {
            ZHText(content: timingModeFooter, size: 13, color: AppColor.textSecondary, lineSpacing: 2)
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }

    private var timingModeFooter: String {
        switch timingMode {
        case .manual:
            return "到点只提醒，什么时候切换由你决定。"
        case .automatic:
            return "按时间自动切换，打开就知道现在是哪一段。"
        }
    }

    private var targetSection: some View {
        Section {
            Picker("预设", selection: $targetMinutes) {
                ForEach(Self.presets, id: \.self) { h in
                    Text("\(h):\(24 - h)").tag(h * 60)
                }
                if !Self.presets.contains(targetMinutes / 60) {
                    Text("\(targetMinutes / 60):\(derivedEatingHours)（自定义）").tag(targetMinutes)
                }
            }
            .onChange(of: targetMinutes) { _, _ in Haptics.play(.selection) }

            Stepper("断食小时数：\(targetMinutes / 60)", value: Binding(
                get: { targetMinutes / 60 },
                set: { targetMinutes = $0 * 60 }
            ), in: 1...23)

            HStack {
                Text("进食窗口")
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text("\(derivedEatingHours) 小时")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.stageCompleted)
            }
        } header: {
            Text("断食 / 进食时长")
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }

    private var notificationSection: some View {
        Section {
            Toggle("达成时提醒我", isOn: $notificationEnabled)
                .onChange(of: notificationEnabled) { _, newValue in
                    if isRevertingNotificationToggle {
                        isRevertingNotificationToggle = false
                        return
                    }
                    Haptics.play(.toggle)
                    handleNotificationToggle(newValue)
                }
        } header: {
            Text("通知")
        } footer: {
            ZHText(content: "断食或进食目标达成时会发一条本地通知，\n仅此而已。",
                   size: 13, color: AppColor.textSecondary, lineSpacing: 2)
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }

    private func handleNotificationToggle(_ on: Bool) {
        if on {
            Task { @MainActor in
                let granted = await NotificationService.shared.requestPermission()
                if granted {
                    PersistenceService.shared.notificationEnabled = true
                    vm.refreshNotificationsFromCurrentSession()
                } else {
                    // 用户拒绝授权 → 把开关回退，避免给用户"已开启"的错觉
                    isRevertingNotificationToggle = true
                    notificationEnabled = false
                    PersistenceService.shared.notificationEnabled = false
                }
            }
        } else {
            PersistenceService.shared.notificationEnabled = false
            NotificationService.shared.cancelAll()
        }
    }

    private var widgetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColor.sunOrange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("桌面 / 锁屏小组件")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("不打开 App 也能看到当前进度。")
                            .font(.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }
                Divider().opacity(0.3)
                instructionRow(num: "1", text: "桌面：长按空白处 → 左上角 +")
                instructionRow(num: "2", text: "锁屏：长按表盘空白 → Customize")
                instructionRow(num: "3", text: "搜「轻断食」→ 选尺寸 → 加上")
            }
            .padding(.vertical, 4)
        } header: {
            Text("小组件")
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }

    private func instructionRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(AppColor.sunOrange))
            ZHText(content: text, size: 13, color: AppColor.textPrimary)
            Spacer()
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            VStack(alignment: .leading, spacing: 4) {
                ZHText(content: "不登录，不联网，不收集数据。", size: 13, color: AppColor.textSecondary)
                ZHText(content: "语言跟随系统。", size: 13, color: AppColor.textSecondary)
            }

            HStack {
                Text("版本")
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(LegalURLs.appVersion)
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppColor.textSecondary)
            }

            Link(destination: LegalURLs.privacyPolicy) {
                aboutLinkRow(symbol: "hand.raised.fill", title: "隐私政策")
            }
            Link(destination: LegalURLs.termsOfUse) {
                aboutLinkRow(symbol: "doc.text.fill", title: "使用条款")
            }
            Link(destination: LegalURLs.mailto) {
                aboutLinkRow(symbol: "envelope.fill", title: "联系我们", subtitle: LegalURLs.contactEmail)
            }
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }

    private func aboutLinkRow(symbol: String, title: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColor.sunOrange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(AppColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.textSecondary.opacity(0.6))
        }
    }

    private var healthSection: some View {
        Section("健康说明") {
            ZHText(content: "轻断食时钟仅用于计时与提醒，不提供医疗建议。\n若你有特殊健康情况，或计划进行较长时间断食，\n请先咨询专业人士。",
                   size: 13, color: AppColor.textSecondary, lineSpacing: 3)
        }
        .listRowBackground(AppColor.cardSurface.opacity(0.7))
    }
}
