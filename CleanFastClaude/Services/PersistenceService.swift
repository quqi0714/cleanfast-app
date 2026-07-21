import Foundation
import os.log

final class PersistenceService: Sendable {
    /// 解码失败时打 console 日志，方便用户上报或测试时排查损坏的 UserDefaults。
    private static let log = Logger(subsystem: "com.MaxQ.CleanFast", category: "Persistence")

    nonisolated static let shared = PersistenceService()

    /// App Group 标识符——主 App 和 Widget 共享同一份 UserDefaults。
    /// 必须和两个 target 在 Signing & Capabilities → App Groups 里勾选的一致。
    static let appGroupIdentifier = "group.com.MaxQ.CleanFast"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 默认初始化使用 App Group UserDefaults（生产路径）。
    /// 测试可注入独立 suite 的 UserDefaults 隔离状态。
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: PersistenceService.appGroupIdentifier)
            ?? .standard
    }

    private enum Key {
        static let state                  = "state.v1"
        static let session                = "session.v1"
        static let skippedDateString      = "skippedDate.v1"
        static let notificationEnabled    = "notificationEnabled.v1"
        static let targetMinutes          = "targetMinutes.v1"
        static let hasCompletedOnboarding = "hasCompletedOnboarding.v1"
        static let timingMode             = "timingMode.v1"
        static let appAppearance          = "appAppearance.v1"
        static let homeStyle              = "homeStyle.v1"
        static let manualStartNeedsTimeChoice = "manualStartNeedsTimeChoice.v1"
        static let automaticFastingStartMinute = "automaticFastingStartMinute.v1"
        static let automaticResumeDateString = "automaticResumeDate.v1"
        static let completedFastCount         = "completedFastCount.v1"
        static let reviewRequestedForCount    = "reviewRequestedForCount.v1"
    }

    var state: FastingState {
        get {
            guard let raw = defaults.string(forKey: Key.state),
                  let state = FastingState(rawValue: raw)
            else { return .notStarted }
            return state
        }
        set { defaults.set(newValue.rawValue, forKey: Key.state) }
    }

    var session: FastingSession? {
        get {
            guard let data = defaults.data(forKey: Key.session) else { return nil }
            do {
                return try decoder.decode(FastingSession.self, from: data)
            } catch {
                // 损坏的 session JSON：日志记录便于排查，并清掉这条无效数据避免下次再撞。
                Self.log.error("session.v1 decode failed: \(String(describing: error), privacy: .public). Clearing corrupted entry.")
                defaults.removeObject(forKey: Key.session)
                return nil
            }
        }
        set {
            if let value = newValue {
                do {
                    let data = try encoder.encode(value)
                    defaults.set(data, forKey: Key.session)
                } catch {
                    Self.log.error("session.v1 encode failed: \(String(describing: error), privacy: .public).")
                }
            } else {
                defaults.removeObject(forKey: Key.session)
            }
        }
    }

    /// "yyyy-MM-dd" in the system calendar/timezone.
    var skippedDateString: String? {
        get { defaults.string(forKey: Key.skippedDateString) }
        set {
            if let v = newValue { defaults.set(v, forKey: Key.skippedDateString) }
            else { defaults.removeObject(forKey: Key.skippedDateString) }
        }
    }

    var notificationEnabled: Bool {
        get { defaults.object(forKey: Key.notificationEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notificationEnabled) }
    }

    /// 用户选择的目标断食时长（分钟）。进食窗口自动 = 24h − 此值。
    var targetMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.targetMinutes)
            return v == 0 ? 16 * 60 : v
        }
        set { defaults.set(newValue, forKey: Key.targetMinutes) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    var timingMode: TimingMode {
        get {
            guard let raw = defaults.string(forKey: Key.timingMode),
                  let mode = TimingMode(rawValue: raw)
            else { return .manual }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.timingMode) }
    }

    var appAppearance: AppAppearance {
        get {
            guard let raw = defaults.string(forKey: Key.appAppearance),
                  let appearance = AppAppearance(rawValue: raw)
            else { return .system }
            return appearance
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appAppearance) }
    }

    var homeStyle: HomeStyle {
        get {
            guard let raw = defaults.string(forKey: Key.homeStyle),
                  let style = HomeStyle(rawValue: raw)
            else { return .classic }
            return style
        }
        set { defaults.set(newValue.rawValue, forKey: Key.homeStyle) }
    }

    var manualStartNeedsTimeChoice: Bool {
        get { defaults.bool(forKey: Key.manualStartNeedsTimeChoice) }
        set { defaults.set(newValue, forKey: Key.manualStartNeedsTimeChoice) }
    }

    var automaticFastingStartMinute: Int? {
        get {
            guard defaults.object(forKey: Key.automaticFastingStartMinute) != nil else { return nil }
            return defaults.integer(forKey: Key.automaticFastingStartMinute)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.automaticFastingStartMinute)
            } else {
                defaults.removeObject(forKey: Key.automaticFastingStartMinute)
            }
        }
    }

    /// 累计「达成目标」的断食次数（手动结束达标 + 自动模式实时切换各计一次）。
    var completedFastCount: Int {
        get { defaults.integer(forKey: Key.completedFastCount) }
        set { defaults.set(newValue, forKey: Key.completedFastCount) }
    }

    /// 最近一次已发出评分请求时的 completedFastCount，防止同一里程碑重复求评。
    var reviewRequestedForCount: Int {
        get { defaults.integer(forKey: Key.reviewRequestedForCount) }
        set { defaults.set(newValue, forKey: Key.reviewRequestedForCount) }
    }

    var automaticResumeDateString: String? {
        get { defaults.string(forKey: Key.automaticResumeDateString) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.automaticResumeDateString)
            } else {
                defaults.removeObject(forKey: Key.automaticResumeDateString)
            }
        }
    }
}
