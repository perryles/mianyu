import Foundation

struct PeriodBasalTemperatureEntry: Equatable, Sendable {
    let text: String

    var normalizedText: String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
    }

    var isValid: Bool {
        guard let value = Double(normalizedText) else { return false }
        return (30...45).contains(value)
    }
}

enum PeriodSymptomIntensity: Int, CaseIterable, Identifiable, Equatable, Sendable {
    case none = 0
    case mild = 1
    case noticeable = 3
    case strong = 5

    init(level: Int) {
        switch min(max(level, 0), 5) {
        case 0:
            self = .none
        case 1...2:
            self = .mild
        case 3...4:
            self = .noticeable
        default:
            self = .strong
        }
    }

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "未记录")
        case .mild: return String(localized: "轻度")
        case .noticeable: return String(localized: "中度")
        case .strong: return String(localized: "重度")
        }
    }
}

enum PeriodProgressGeometry {
    static func filledWidth(progress: CGFloat, availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth) * min(max(progress, 0), 1)
    }

    static func indicatorOffset(
        progress: CGFloat,
        availableWidth: CGFloat,
        indicatorDiameter: CGFloat
    ) -> CGFloat {
        let availableWidth = max(0, availableWidth)
        let indicatorDiameter = max(0, indicatorDiameter)
        let filledWidth = filledWidth(progress: progress, availableWidth: availableWidth)
        return max(0, min(filledWidth - indicatorDiameter / 2, availableWidth - indicatorDiameter))
    }
}

enum PeriodLearningState: Equatable, Sendable {
    case learning
    case lowConfidence
    case mediumConfidence
    case stable

    init(completedCycleCount: Int) {
        switch max(0, completedCycleCount) {
        case 0...1: self = .learning
        case 2: self = .lowConfidence
        case 3...5: self = .mediumConfidence
        default: self = .stable
        }
    }

    init(cycles: [PeriodCycle]) {
        self.init(completedCycleCount: cycles.filter { $0.endDate != nil }.count)
    }

    var title: String {
        switch self {
        case .learning: return String(localized: "学习中")
        case .lowConfidence: return String(localized: "低置信")
        case .mediumConfidence: return String(localized: "逐渐稳定")
        case .stable: return String(localized: "节律稳定")
        }
    }

    var detail: String {
        switch self {
        case .learning: return String(localized: "记录还不够，预测日期仅作参考")
        case .lowConfidence: return String(localized: "已开始识别你的节律，继续记录会更准确")
        case .mediumConfidence: return String(localized: "周期轮廓正在变清晰，日期仍可能调整")
        case .stable: return String(localized: "已基于近期完整周期形成较稳定的估计")
        }
    }
}

struct PeriodQuickRecordValues: Equatable, Sendable {
    let flowLevel: Int
    let painLevel: Int
    let moodLevel: Int
}

enum PeriodQuickRecordPreset: String, CaseIterable, Identifiable, Sendable {
    case noBleeding
    case typical
    case lightNoPain
    case mediumMildPain
    case heavyModeratePain

    static let commonPresets: [PeriodQuickRecordPreset] = [
        .lightNoPain,
        .mediumMildPain,
        .heavyModeratePain
    ]

    var id: String { rawValue }

    var isMenstruating: Bool { self != .noBleeding }

    var title: String {
        switch self {
        case .noBleeding: return "否"
        case .typical: return "是"
        case .lightNoPain: return "少量"
        case .mediumMildPain: return "中等"
        case .heavyModeratePain: return "偏多"
        }
    }

    var detail: String {
        switch self {
        case .noBleeding: return "今天未出血"
        case .typical: return "中等量 · 无痛"
        case .lightNoPain: return "无明显痛感"
        case .mediumMildPain: return "轻微痛感"
        case .heavyModeratePain: return "中度痛感"
        }
    }

    func resolvedValues(
        existingFlowLevel: Int,
        existingPainLevel: Int,
        existingMoodLevel: Int,
        hasExistingLog: Bool
    ) -> PeriodQuickRecordValues {
        let existingMood = hasExistingLog ? max(0, min(5, existingMoodLevel)) : 0

        switch self {
        case .noBleeding:
            return PeriodQuickRecordValues(
                flowLevel: 0,
                painLevel: hasExistingLog ? max(0, min(5, existingPainLevel)) : 0,
                moodLevel: existingMood
            )
        case .typical:
            return PeriodQuickRecordValues(
                flowLevel: hasExistingLog && existingFlowLevel > 0
                    ? max(1, min(4, existingFlowLevel))
                    : 2,
                painLevel: hasExistingLog ? max(0, min(5, existingPainLevel)) : 0,
                moodLevel: existingMood
            )
        case .lightNoPain:
            return PeriodQuickRecordValues(flowLevel: 1, painLevel: 0, moodLevel: existingMood)
        case .mediumMildPain:
            return PeriodQuickRecordValues(flowLevel: 2, painLevel: 1, moodLevel: existingMood)
        case .heavyModeratePain:
            return PeriodQuickRecordValues(flowLevel: 3, painLevel: 2, moodLevel: existingMood)
        }
    }
}
