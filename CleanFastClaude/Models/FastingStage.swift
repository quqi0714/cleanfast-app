import Foundation

/// 身体在断食过程中的几个常见阶段。
/// 描述使用克制语气（"通常""可能""逐渐"），不使用"自噬""深度燃脂"等焦虑感词汇。
enum FastingStage: Int, CaseIterable, Equatable {
    case digesting          // 0–2h   消化中
    case bloodSugarSettling // 2–4h   血糖渐稳
    case glycogenUse        // 4–8h   动用糖原
    case fuelSwitch         // 8–12h  燃料切换
    case deepFueling        // 12–16h 深度供能
    case completed          // 达成目标后

    var title: String {
        switch self {
        case .digesting:          return "消化中"
        case .bloodSugarSettling: return "血糖渐稳"
        case .glycogenUse:        return "动用糖原"
        case .fuelSwitch:         return "燃料切换"
        case .deepFueling:        return "深度供能"
        case .completed:          return "已经完成目标"
        }
    }

    var message: String {
        switch self {
        case .digesting:
            return "身体正在处理刚摄入的能量，胰岛素水平较高。\n轻松开始就好，记得多喝水哦。"
        case .bloodSugarSettling:
            return "食物逐渐吸收完，胰岛素开始下降，\n血糖正在变得平稳。记得多喝水哦。"
        case .glycogenUse:
            return "胃通常已经排空，\n身体可能更多使用糖原储备来供能。记得多喝水哦。"
        case .fuelSwitch:
            return "糖原渐少，身体可能逐渐切换到脂肪供能。\n这是一个常见的过渡阶段。记得多喝水哦。"
        case .deepFueling:
            return "脂肪供能变成主要方式，\n酮体水平可能在上升。记得多喝水哦。"
        case .completed:
            return "辛苦啦，目标已达成。\n继续也好，结束也好，听身体的。"
        }
    }

    /// 大致时间范围的简短描述，可用于 onboarding 或科普角。
    var rangeLabel: String {
        switch self {
        case .digesting:          return "0–2 小时"
        case .bloodSugarSettling: return "2–4 小时"
        case .glycogenUse:        return "4–8 小时"
        case .fuelSwitch:         return "8–12 小时"
        case .deepFueling:        return "12 小时+"
        case .completed:          return "达成目标"
        }
    }

    static func from(elapsedSeconds: TimeInterval, hasReachedTarget: Bool) -> FastingStage {
        if hasReachedTarget { return .completed }
        let h = elapsedSeconds / 3600
        switch h {
        case ..<2:  return .digesting
        case ..<4:  return .bloodSugarSettling
        case ..<8:  return .glycogenUse
        case ..<12: return .fuelSwitch
        default:    return .deepFueling
        }
    }
}
