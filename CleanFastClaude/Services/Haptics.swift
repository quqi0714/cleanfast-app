import UIKit
import CoreHaptics

/// 触觉反馈中心。
///
/// 三层策略：
/// 1. 关键时刻（达成、阶段、模式切换）走 `CHHapticEngine` 自定义波形 —— 真正发挥 Taptic Engine。
/// 2. 普通点击走缓存的 `UIFeedbackGenerator` —— `prepare()` 后无延迟。
/// 3. 不支持 haptics 的设备（iPad）静默降级。
@MainActor
enum Haptics {
    enum Pattern {
        case primaryAdvance
        case secondaryAction
        case cancel
        case selection
        case toggle
        case targetReached
        case stageChange
        case adjustTime
        case modeChanged
    }

    // MARK: - Generator cache（避免每次 play 都重新初始化，让 prepare() 真正起作用）

    private static let softGen = UIImpactFeedbackGenerator(style: .soft)
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let notificationGen = UINotificationFeedbackGenerator()

    // MARK: - CHHapticEngine（懒加载，仅在支持设备上初始化）

    private static let supportsHaptics: Bool =
        CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private static var engine: CHHapticEngine? = {
        guard supportsHaptics else { return nil }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            // 引擎被系统/中断停止时，下次 play 之前会自动重启
            engine.stoppedHandler = { _ in /* lazy-restart on next play */ }
            engine.resetHandler = { [weak engine] in
                try? engine?.start()
            }
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }()

    /// 应用进入前台 / Home 出现时调用一次，预热常用 generator，
    /// 消除首次 tap 50–200ms 的"哑火"。
    static func prepare() {
        softGen.prepare()
        lightGen.prepare()
        selectionGen.prepare()
    }

    // MARK: - Play

    static func play(_ pattern: Pattern) {
        switch pattern {
        case .primaryAdvance:
            softGen.impactOccurred(intensity: 0.85)
            softGen.prepare()
        case .secondaryAction, .cancel:
            lightGen.impactOccurred(intensity: 0.55)
            lightGen.prepare()
        case .selection:
            selectionGen.selectionChanged()
            selectionGen.prepare()
        case .modeChanged:
            playModeChanged()
        case .toggle:
            rigidGen.impactOccurred(intensity: 0.55)
            rigidGen.prepare()
        case .targetReached:
            playTargetReached()
        case .stageChange:
            playStageChange()
        case .adjustTime:
            softGen.impactOccurred(intensity: 0.60)
            softGen.prepare()
        }
    }

    // MARK: - Custom Taptic patterns

    /// "钟声"：一下软撞击 + 0.45s 衰减的余韵。
    /// 比通用的 `.success`（咚咚咚三连）更有品牌感、更克制。
    private static func playTargetReached() {
        guard let engine = ensuredEngine() else {
            notificationGen.notificationOccurred(.success)
            return
        }
        let thump = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.75),
                .init(parameterID: .hapticSharpness, value: 0.30),
            ],
            relativeTime: 0
        )
        let lingering = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.30),
                .init(parameterID: .hapticSharpness, value: 0.55),
            ],
            relativeTime: 0.18,
            duration: 0.45
        )
        // 余韵衰减曲线
        let decay = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0,    value: 1.0),
                .init(relativeTime: 0.20, value: 0.55),
                .init(relativeTime: 0.45, value: 0.0),
            ],
            relativeTime: 0.18
        )
        playPattern(events: [thump, lingering], curves: [decay], engine: engine) {
            notificationGen.notificationOccurred(.success)
        }
    }

    /// "嗒嗒"：双击，第一击稍强、第二击轻 → "向前推一格"的感觉。
    /// 取代之前与 `.cancel` 雷同的 light/0.45。
    private static func playStageChange() {
        guard let engine = ensuredEngine() else {
            lightGen.impactOccurred(intensity: 0.45)
            return
        }
        let tap1 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.55),
                .init(parameterID: .hapticSharpness, value: 0.40),
            ],
            relativeTime: 0
        )
        let tap2 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.38),
                .init(parameterID: .hapticSharpness, value: 0.55),
            ],
            relativeTime: 0.12
        )
        playPattern(events: [tap1, tap2], curves: [], engine: engine) {
            lightGen.impactOccurred(intensity: 0.45)
        }
    }

    /// "卡入"：80ms 渐强 + 末尾一记轻 click → 模式开关咬合的实体感。
    private static func playModeChanged() {
        guard let engine = ensuredEngine() else {
            mediumGen.impactOccurred(intensity: 0.62)
            return
        }
        let ramp = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.55),
                .init(parameterID: .hapticSharpness, value: 0.45),
            ],
            relativeTime: 0,
            duration: 0.08
        )
        let rampUp = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0,    value: 0.0),
                .init(relativeTime: 0.08, value: 1.0),
            ],
            relativeTime: 0
        )
        let click = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: 0.50),
                .init(parameterID: .hapticSharpness, value: 0.70),
            ],
            relativeTime: 0.10
        )
        playPattern(events: [ramp, click], curves: [rampUp], engine: engine) {
            mediumGen.impactOccurred(intensity: 0.62)
        }
    }

    // MARK: - Engine plumbing

    /// 确保引擎已启动；引擎被中断后再次调用会重新 start。
    private static func ensuredEngine() -> CHHapticEngine? {
        guard let engine else { return nil }
        do {
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }

    /// 通用播放器：构造 pattern → player → start，失败时走 fallback。
    private static func playPattern(
        events: [CHHapticEvent],
        curves: [CHHapticParameterCurve],
        engine: CHHapticEngine,
        fallback: () -> Void
    ) {
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    // MARK: - 兼容旧 API（避免外部调用方需要改）

    static func soft()         { play(.primaryAdvance) }
    static func light()        { play(.secondaryAction) }
    static func rigid()        { play(.toggle) }
    static func selection()    { play(.selection) }
    static func stageChange()  { play(.stageChange) }
    static func success()      { play(.targetReached) }
}
