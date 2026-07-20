import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct CleanFastClaudeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider

struct CleanFastClaudeProvider: TimelineProvider {
    func placeholder(in context: Context) -> CleanFastClaudeEntry {
        CleanFastClaudeEntry(date: Date(), snapshot: .current())
    }

    func getSnapshot(in context: Context, completion: @escaping (CleanFastClaudeEntry) -> Void) {
        completion(CleanFastClaudeEntry(date: Date(), snapshot: .current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CleanFastClaudeEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.current(at: now)
        var entries: [CleanFastClaudeEntry] = [
            CleanFastClaudeEntry(date: now, snapshot: snapshot)
        ]

        if snapshot.state == .fasting || snapshot.state == .eating {
            appendActiveTimelineEntries(to: &entries, snapshot: snapshot, now: now)
        }

        if snapshot.state == .skipped,
           let nextDay = WidgetSnapshot.startOfNextDay(),
           nextDay > now {
            entries.append(CleanFastClaudeEntry(date: nextDay, snapshot: WidgetSnapshot.current(at: nextDay)))
        }
        // 自动模式存在"明天自动恢复"时（skipped 和跨午夜后的 notStarted 都可能带着
        // resumeDate），必须在恢复时刻放 entry，并给恢复后的断食段生成完整刷新序列，
        // 否则用户不开 App 的话 widget 会一直停在"未开始/休息"。
        if snapshot.timingMode == .automatic,
           snapshot.state == .notStarted || snapshot.state == .skipped,
           let resumeDate = snapshot.automaticResumeStartDate,
           resumeDate > now {
            let resumeSnapshot = WidgetSnapshot.current(at: resumeDate)
            entries.append(CleanFastClaudeEntry(date: resumeDate, snapshot: resumeSnapshot))
            if resumeSnapshot.state == .fasting || resumeSnapshot.state == .eating {
                appendActiveTimelineEntries(to: &entries, snapshot: resumeSnapshot, now: resumeDate)
            }
        }

        // 只要时间线里还有未来的 entry（会话推进 / 午夜失效 / 自动恢复），就用 .atEnd
        // 让 iOS 在末尾自动再请求一次，衔接下一段；纯静态的单条 entry 才用 .never。
        let policy: TimelineReloadPolicy = entries.count > 1 ? .atEnd : .never
        completion(Timeline(entries: entries.sorted(by: { $0.date < $1.date }), policy: policy))
    }

    /// 活跃态（断食 / 进食）统一时间线生成。
    ///
    /// 策略：**"近端密、远端稀"**
    /// - 接下来 4 小时：每 1 分钟一条 entry（240 条上限）→ 锁屏分钟级精度
    /// - 4 小时后到 targetEnd：每 10 分钟一条兜底 → 进度条不会卡住
    /// - 阶段切换时刻 + 目标到达时刻另加专属 entry
    ///
    /// 4h 之后 iOS 会基于 `.atEnd` 重新请求 timeline，下一批又是 240 条密集。
    /// 自动模式不需要在这里"穿越"未来 cycle —— `WidgetSnapshot.current(at:)` 内部
    /// 的 `advanceAutomatic` 已经能把 reload 时刻的状态推到正确的下一段。
    private func appendActiveTimelineEntries(
        to entries: inout [CleanFastClaudeEntry],
        snapshot: WidgetSnapshot,
        now: Date
    ) {
        guard let session = snapshot.session else { return }

        // 阶段图标变化（仅 fasting）
        if snapshot.state == .fasting {
            appendFastingStageEntries(to: &entries, session: session, now: now, horizon: session.targetEndDate)
        }

        // 近端密集：每分钟 1 条，最多 240 条 ≈ 4 小时
        let denseHorizon = min(session.targetEndDate, now.addingTimeInterval(4 * 3600))
        appendPeriodicEntries(to: &entries, from: now, to: denseHorizon, intervalMinutes: 1)

        // 远端兜底：每 10 分钟 1 条，让长会话末端的进度条仍然推进
        if denseHorizon < session.targetEndDate {
            appendPeriodicEntries(
                to: &entries,
                from: denseHorizon,
                to: session.targetEndDate,
                intervalMinutes: 10
            )
        }

        // 目标到达时刻：让 hasReachedTarget 翻转、自动模式滚到下一 cycle
        if !snapshot.hasReachedTarget, session.targetEndDate > now {
            entries.append(CleanFastClaudeEntry(
                date: session.targetEndDate,
                snapshot: WidgetSnapshot.current(at: session.targetEndDate)
            ))
        }
    }

    private func appendFastingStageEntries(
        to entries: inout [CleanFastClaudeEntry],
        session: WidgetSession,
        now: Date,
        horizon: Date
    ) {
        let stageBoundaries: [TimeInterval] = [2, 4, 8, 12].map { $0 * 3600 }
        for boundary in stageBoundaries {
            let date = session.startDate.addingTimeInterval(boundary)
            if date > now && date < session.targetEndDate && date <= horizon {
                entries.append(CleanFastClaudeEntry(date: date, snapshot: WidgetSnapshot.current(at: date)))
            }
        }
    }

    /// 在 [from, to] 区间内每 N 分钟插一个 timeline entry，
    /// 让 widget 的进度条 / 百分比文本能定期刷新（不依赖状态切换）。
    /// CountUpClock 内部用 `Text(timerInterval:)` 自走，不受影响；
    /// 但 progress 是 snapshot 上的静态字段，必须靠新 entry 才会更新。
    private func appendPeriodicEntries(
        to entries: inout [CleanFastClaudeEntry],
        from start: Date,
        to end: Date,
        intervalMinutes: Int
    ) {
        guard end > start else { return }
        let stride = TimeInterval(intervalMinutes * 60)
        var t = start.addingTimeInterval(stride)
        while t < end {
            entries.append(CleanFastClaudeEntry(date: t, snapshot: WidgetSnapshot.current(at: t)))
            t = t.addingTimeInterval(stride)
        }
    }
}

// MARK: - Widget configuration

struct CleanFastClaudeWidget: Widget {
    let kind = "CleanFastClaudeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CleanFastClaudeProvider()) { entry in
            CleanFastClaudeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    backgroundFor(entry: entry)
                }
        }
        .configurationDisplayName(LocalizedStringResource("轻断食时钟"))
        .description(LocalizedStringResource("看一眼当前断食 / 进食状态。"))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}

@ViewBuilder
private func backgroundFor(entry: CleanFastClaudeEntry) -> some View {
    let color = ringColor(entry.snapshot)
    ZStack {
        // 1. 底层：温暖底色 → 状态色斜向渐变
        LinearGradient(
            colors: [
                WidgetColor.background,
                color.opacity(0.18),
                color.opacity(0.28),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // 2. 右上柔光斑：制造立体感，模拟主 App AmbientBackground 的飘移光
        RadialGradient(
            colors: [color.opacity(0.32), .clear],
            center: UnitPoint(x: 0.92, y: 0.08),
            startRadius: 0,
            endRadius: 130
        )
        .blendMode(.plusLighter)

        // 3. 左下深色暗角：拉开层次，让中央内容更突出
        RadialGradient(
            colors: [Color.black.opacity(0.10), .clear],
            center: UnitPoint(x: 0.05, y: 0.95),
            startRadius: 0,
            endRadius: 180
        )

        // 4. 顶部细高光线：模拟环境光从上方落下
        LinearGradient(
            colors: [Color.white.opacity(0.08), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .blendMode(.plusLighter)
    }
}

// MARK: - Top-level dispatcher view

struct CleanFastClaudeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CleanFastClaudeEntry

    var body: some View {
        switch family {
        case .systemSmall:          SmallWidgetView(entry: entry)
        case .systemMedium:         MediumWidgetView(entry: entry)
        case .accessoryRectangular: LockRectangularView(entry: entry)
        case .accessoryCircular:    LockCircularView(entry: entry)
        case .accessoryInline:      LockInlineView(entry: entry)
        default:                    SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Helpers

private func ringColor(_ snapshot: WidgetSnapshot) -> Color {
    switch snapshot.state {
    case .notStarted: return WidgetColor.sunOrange
    case .fasting:    return WidgetColor.stageColor(elapsedHours: snapshot.elapsed / 3600,
                                                     hasReachedTarget: snapshot.hasReachedTarget)
    case .eating:     return WidgetColor.mintGreen
    case .skipped:    return Color.gray.opacity(0.55)
    }
}

private func stateLabel(_ snapshot: WidgetSnapshot) -> String {
    switch snapshot.state {
    case .notStarted: return String(localized: "未开始")
    case .fasting:    return snapshot.hasReachedTarget ? String(localized: "目标达成") : String(localized: "断食中")
    case .eating:     return snapshot.hasReachedTarget ? String(localized: "窗口已满") : String(localized: "进食窗口")
    case .skipped:    return String(localized: "今天休息")
    }
}

/// 副标题：断食时显示当前阶段（消化中 / 血糖渐稳 / …），其他状态返回 nil。
private func subtitleLabel(_ snapshot: WidgetSnapshot) -> String? {
    snapshot.fastingStageTitle
}

private func lockShortLabel(_ snapshot: WidgetSnapshot) -> String {
    switch snapshot.state {
    case .notStarted: return "\(snapshot.targetMinutes / 60)h"
    case .fasting:    return snapshot.hasReachedTarget ? "+" : String(localized: "断")
    case .eating:     return snapshot.hasReachedTarget ? "+" : String(localized: "食")
    case .skipped:    return String(localized: "休")
    }
}

private func lockDetailLabel(_ snapshot: WidgetSnapshot) -> String {
    switch snapshot.state {
    case .notStarted:
        return String(localized: "准备好再开始")
    case .fasting, .eating:
        guard let session = snapshot.session else { return "" }
        let hours = Int(session.targetDuration / 3600)
        if snapshot.hasReachedTarget {
            return snapshot.state == .fasting
                ? String(localized: "目标 \(hours)h 已达成")
                : String(localized: "窗口已满")
        }
        return String(localized: "目标 \(hours)h")
    case .skipped:
        return String(localized: "明天再继续")
    }
}

private func stageSymbolName(_ snapshot: WidgetSnapshot) -> String {
    switch snapshot.state {
    case .notStarted: return "moon.stars.fill"
    case .fasting:    return WidgetColor.stageSymbol(elapsedHours: snapshot.elapsed / 3600,
                                                       hasReachedTarget: snapshot.hasReachedTarget)
    case .eating:     return "fork.knife"
    case .skipped:    return "moon.zzz.fill"
    }
}

// MARK: - Home Screen: Small

struct SmallWidgetView: View {
    let entry: CleanFastClaudeEntry
    var snapshot: WidgetSnapshot { entry.snapshot }
    private var color: Color { ringColor(snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：状态点 + 标题（同行带阶段副标题）+ 阶段图标 halo
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.55), radius: 3)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stateLabel(snapshot))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetColor.textPrimary)
                    if let subtitle = subtitleLabel(snapshot) {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(color.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Spacer()
                StageGlyph(symbol: stageSymbolName(snapshot), color: color, size: 13)
            }

            Spacer(minLength: 4)

            // 中部：大号正计时（带轻量发光，呼应主 App cinematic）
            CountUpClock(snapshot: snapshot, size: 26)
                .foregroundStyle(WidgetColor.textPrimary)
                .shadow(color: color.opacity(0.22), radius: 6, y: 1)

            Spacer(minLength: 6)

            // 底部：精致能量条 + 百分比 / 目标
            VStack(alignment: .leading, spacing: 4) {
                EnergyBar(progress: snapshot.progress,
                          color: color,
                          height: 8)
                HStack {
                    Text("\(Int(snapshot.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                    Spacer()
                    Text(bottomLine(snapshot))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(WidgetColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func bottomLine(_ s: WidgetSnapshot) -> String {
        switch s.state {
        case .notStarted: return String(localized: "目标 \(s.targetMinutes / 60)h")
        case .fasting, .eating:
            guard let session = s.session else { return "" }
            let hours = Int(session.targetDuration) / 3600
            if s.hasReachedTarget {
                return s.state == .fasting
                    ? String(localized: "目标 \(hours)h 已达成")
                    : String(localized: "窗口已满")
            }
            return String(localized: "目标 \(hours)h")
        case .skipped: return String(localized: "明天再继续")
        }
    }
}

// MARK: - Home Screen: Medium

struct MediumWidgetView: View {
    let entry: CleanFastClaudeEntry
    var snapshot: WidgetSnapshot { entry.snapshot }
    private var color: Color { ringColor(snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部：状态点 + 标题 · 阶段名  +  右侧百分比 + 阶段图标 halo
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .shadow(color: color.opacity(0.55), radius: 3)
                Text(stateLabel(snapshot))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetColor.textPrimary)
                if let subtitle = subtitleLabel(snapshot) {
                    Text("·")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(WidgetColor.textSecondary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(color.opacity(0.9))
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(snapshot.progress * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                StageGlyph(symbol: stageSymbolName(snapshot), color: color, size: 14)
            }

            // 中部：大号正计时（带柔光，呼应主 App cinematic 大数字）
            CountUpClock(snapshot: snapshot, size: 34)
                .foregroundStyle(WidgetColor.textPrimary)
                .shadow(color: color.opacity(0.25), radius: 8, y: 2)

            Spacer(minLength: 2)

            // 底部：精致能量条（带阶段 marker）
            EnergyBar(progress: snapshot.progress,
                      color: color,
                      markers: snapshot.stageMarkers,
                      height: 14)

            // 最底部：右下角的进食/起始提示
            if let line = endLine(snapshot) {
                Text(line)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func endLine(_ s: WidgetSnapshot) -> String? {
        guard let session = s.session, s.state == .fasting || s.state == .eating else {
            return s.state == .notStarted ? String(localized: "准备好了再开始") : nil
        }
        // 跟随系统 locale/时制偏好（中文默认 24h 不变，en-US 显示 3:30 PM）
        let when = session.targetEndDate.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current

        if s.hasReachedTarget {
            return s.state == .fasting
                ? String(localized: "目标已达成，继续计时")
                : String(localized: "进食窗口已满")
        }

        // 拆成"今天/明天/无前缀" 3 套独立的本地化 key，避免英文翻译里
        // "Eat at" 跟动态前缀粘连成 "Eat attomorrow"。
        if cal.isDateInToday(session.targetEndDate) {
            return s.state == .fasting
                ? String(localized: "可于今天 \(when) 进食")
                : String(localized: "建议今天 \(when) 前结束")
        }
        if cal.isDateInTomorrow(session.targetEndDate) {
            return s.state == .fasting
                ? String(localized: "可于明天 \(when) 进食")
                : String(localized: "建议明天 \(when) 前结束")
        }
        return s.state == .fasting
            ? String(localized: "可于 \(when) 进食")
            : String(localized: "建议 \(when) 前结束")
    }
}

// MARK: - Lock Screen: Rectangular

struct LockRectangularView: View {
    let entry: CleanFastClaudeEntry
    var snapshot: WidgetSnapshot { entry.snapshot }
    private var color: Color { ringColor(snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：图标 + 状态 · 阶段                百分比
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: stageSymbolName(snapshot))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(titleLine)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if snapshot.state == .fasting || snapshot.state == .eating {
                    Text("\(Int(snapshot.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            // 第二行：大号已用时间（HH 小时 MM 分，无秒，每 ~10 min 跳一次）
            Text(elapsedHM(snapshot))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // 第三行：进度条
            LockMiniProgress(progress: snapshot.progress, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLine: String {
        let state = stateLabel(snapshot)
        if snapshot.state == .fasting, let stage = snapshot.fastingStageTitle {
            return "\(state) · \(stage)"
        }
        return state
    }

    /// 锁屏主信息行：
    /// - 断食中：已用时间 "X 小时 Y 分"
    /// - 进食中：倒计时 "还剩 X 小时 Y 分"（用户更想知道"还能吃多久"）
    /// - 任一状态达成 / 窗口已满：溢出 "+X 小时 Y 分"
    /// 全部分钟级精度，靠 timeline 每分钟的 entry 推进，无秒针抖动。
    private func elapsedHM(_ s: WidgetSnapshot) -> String {
        switch s.state {
        case .notStarted:
            return String(localized: "目标 \(s.targetMinutes / 60) 小时")
        case .fasting:
            guard let session = s.session else { return "—" }
            if s.hasReachedTarget {
                let overrun = max(0, Int(s.date.timeIntervalSince(session.targetEndDate)))
                return formatHM(overrun, prefix: "+")
            }
            return formatHM(max(0, Int(s.elapsed)))
        case .eating:
            guard let session = s.session else { return "—" }
            if s.hasReachedTarget {
                // 进食窗口已满 → 显示已超出多少
                let overrun = max(0, Int(s.date.timeIntervalSince(session.targetEndDate)))
                return formatHM(overrun, prefix: "+")
            }
            // 进食中 → 倒计时到窗口结束
            let remaining = max(0, Int(session.targetEndDate.timeIntervalSince(s.date)))
            return String(localized: "还剩 \(formatHM(remaining))")
        case .skipped:
            return String(localized: "今天休息")
        }
    }

    private func formatHM(_ seconds: Int, prefix: String = "") -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(localized: "\(prefix)\(h) 小时 \(m) 分")
        }
        return String(localized: "\(prefix)\(m) 分")
    }
}

// MARK: - Lock Screen: Circular

struct LockCircularView: View {
    let entry: CleanFastClaudeEntry
    var snapshot: WidgetSnapshot { entry.snapshot }
    private var color: Color { ringColor(snapshot) }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 4)
                .padding(3)
            Circle()
                .trim(from: 0, to: max(0.035, min(snapshot.progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Circle()
                .fill(color.opacity(0.12))
                .padding(14)
            VStack(spacing: -1) {
                Image(systemName: stageSymbolName(snapshot))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(lockShortLabel(snapshot))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - Lock Screen: Inline

struct LockInlineView: View {
    let entry: CleanFastClaudeEntry
    var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch snapshot.state {
        case .notStarted:
            Label("准备好再开始 · \(snapshot.targetMinutes / 60)h", systemImage: "moon.stars.fill")
        case .fasting:
            if let s = snapshot.session {
                Label {
                    if snapshot.hasReachedTarget {
                        Text("目标达成 +") + timerText(s.targetEndDate)
                    } else if let stage = snapshot.fastingStageTitle {
                        Text("\(stage) ") + timerText(s.startDate)
                    } else {
                        Text("断食 ") + timerText(s.startDate)
                    }
                } icon: {
                    Image(systemName: "timer")
                }
            } else {
                Text("断食")
            }
        case .eating:
            if let s = snapshot.session {
                Label {
                    if snapshot.hasReachedTarget {
                        Text("窗口已满 +") + timerText(s.targetEndDate)
                    } else {
                        Text("进食窗口 ") + timerText(s.startDate)
                    }
                } icon: {
                    Image(systemName: "fork.knife")
                }
            } else {
                Text("进食")
            }
        case .skipped:
            Label("今天休息", systemImage: "moon.zzz.fill")
        }
    }

    private func timerText(_ start: Date) -> Text {
        Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: true)
    }
}

// MARK: - Reusable bits

private struct LockMiniProgress: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let fillW = max(h, w * max(0.001, min(progress, 1)))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                Capsule()
                    .fill(color)
                    .frame(width: fillW)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.38), lineWidth: 0.5)
                    )
            }
        }
        .frame(height: 5)
    }
}

/// 自走表大数字。**始终正计时**：从 `session.startDate` 起算，跨过目标后继续向上累加，
/// 跟主 App 的"无论达成与否，主时钟都向上走"的语义一致。
struct CountUpClock: View {
    let snapshot: WidgetSnapshot
    var size: CGFloat = 22

    var body: some View {
        switch snapshot.state {
        case .notStarted:
            Text(staticDuration(TimeInterval(snapshot.targetMinutes * 60)))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
        case .fasting, .eating:
            if let session = snapshot.session {
                clockText(for: session)
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("00:00").font(.system(size: size, weight: .bold, design: .rounded))
            }
        case .skipped:
            Text("—").font(.system(size: size, weight: .bold, design: .rounded))
        }
    }

    private func staticDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        return String(format: "%d:00:00", h)
    }

    private func clockText(for session: WidgetSession) -> Text {
        if snapshot.hasReachedTarget {
            return Text("+") + Text(timerInterval: session.targetEndDate...Date.distantFuture,
                                    countsDown: false, showsHours: true)
        }
        return Text(timerInterval: session.startDate...Date.distantFuture,
                    countsDown: false, showsHours: true)
    }
}

/// 精致的能量条：内嵌阴影底 + 同色渐变填充 + 顶部高光描边 + 行末柔和发光。
/// 可选传入 stage markers，会以小圆点形式漂浮在条上对应小时位置。
struct EnergyBar: View {
    let progress: Double            // 0...1
    let color: Color
    var markers: [WidgetStageMarker] = []
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let fillW = max(h, w * max(0.001, min(progress, 1)))

            ZStack(alignment: .leading) {
                // 1. Track —— 内嵌深色渐变 + 顶部高光描边，制造微凹陷感
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                WidgetColor.trackOverlay.opacity(0.06),
                                WidgetColor.trackOverlay.opacity(0.14),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(WidgetColor.trackOverlay.opacity(0.08), lineWidth: 0.5)
                    )

                // 2. Fill —— 同色上下渐变 + 边缘柔和发光（让条像在亮）
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: fillW)
                    .shadow(color: color.opacity(0.45), radius: 5, x: 0, y: 0)
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), .clear],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.6
                            )
                            .frame(width: fillW)
                    )

                // 3. 阶段 marker —— 小白圆，已过为彩色，未到为浅色
                ForEach(markers) { marker in
                    let cx = max(h / 2, min(w - h / 2, w * marker.fraction))
                    StageMarkerChip(symbol: marker.symbol, color: marker.color, isActive: marker.isActive)
                        .position(x: cx, y: h / 2)
                }
            }
        }
        .frame(height: height)
    }
}

/// 顶部右上角的小图标"光晕徽章"：图标外裹一层柔色圆形底 + 极细描边 + 微阴影。
/// 让小组件的图标比裸 SF Symbol 更精致一点，呼应主 App 的中心徽章风格。
struct StageGlyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .padding(5)
            .background(
                Circle()
                    .fill(color.opacity(0.14))
            )
            .overlay(
                Circle()
                    .stroke(color.opacity(0.30), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.30), radius: 4, y: 1)
    }
}

private struct StageMarkerChip: View {
    let symbol: String
    let color: Color
    let isActive: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : color.opacity(0.55))
            .frame(width: 18, height: 18)
            .background(
                Circle()
                    .fill(isActive ? color : WidgetColor.cardSurface)
            )
            .overlay(
                Circle()
                    .stroke(
                        isActive ? Color.white.opacity(0.6) : color.opacity(0.35),
                        lineWidth: 0.6
                    )
            )
            .shadow(
                color: isActive ? color.opacity(0.45) : Color.black.opacity(0.10),
                radius: isActive ? 3 : 2, y: 1
            )
    }
}
