import Foundation

enum SleepRhythmTrainingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case rhythmTraining
    case lateNightRecovery
    case travelReset
    case bedtimeRoutine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rhythmTraining:
            return String(localized: "节律训练")
        case .lateNightRecovery:
            return "晚睡纠偏"
        case .travelReset:
            return String(localized: "出差重建")
        case .bedtimeRoutine:
            return "睡前流程"
        }
    }

    var systemImageName: String {
        switch self {
        case .rhythmTraining:
            return "moon.stars.fill"
        case .lateNightRecovery:
            return "clock.badge.exclamationmark.fill"
        case .travelReset:
            return "airplane.departure"
        case .bedtimeRoutine:
            return "checklist.checked"
        }
    }
}

struct SleepRhythmRoutineStep: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let offsetMinutes: Int

    static let defaultSteps: [SleepRhythmRoutineStep] = [
        SleepRhythmRoutineStep(
            id: "stop_stimulants",
            title: "停止咖啡因和强光",
            detail: "把咖啡、浓茶、短视频和高亮屏幕先收掉。",
            symbol: "cup.and.saucer.fill",
            offsetMinutes: -180
        ),
        SleepRhythmRoutineStep(
            id: "wind_down",
            title: "洗漱收尾",
            detail: "完成洗漱、整理床边，把房间光线压低。",
            symbol: "shower.fill",
            offsetMinutes: -60
        ),
        SleepRhythmRoutineStep(
            id: "breathing",
            title: "放松呼吸",
            detail: "做 3-5 分钟慢呼吸，让心率先降下来。",
            symbol: "wind",
            offsetMinutes: -25
        ),
        SleepRhythmRoutineStep(
            id: "monitoring",
            title: "开启睡眠监测",
            detail: "确认 Apple Watch 佩戴稳定，必要时开启鼾声分析。",
            symbol: "applewatch.watchface",
            offsetMinutes: -10
        )
    ]

    static func steps(for mode: SleepRhythmTrainingMode) -> [SleepRhythmRoutineStep] {
        switch mode {
        case .rhythmTraining:
            return defaultSteps
        case .lateNightRecovery:
            return [
                SleepRhythmRoutineStep(
                    id: "late_cutoff",
                    title: "设置今晚截止线",
                    detail: "把工作、回复和娱乐都收在同一个截止点前。",
                    symbol: "timer",
                    offsetMinutes: -120
                ),
                SleepRhythmRoutineStep(
                    id: "low_light",
                    title: "低光夜醒预案",
                    detail: "提前准备低光环境，夜醒时不看时间、不刷手机。",
                    symbol: "lightbulb.min.fill",
                    offsetMinutes: -70
                ),
                SleepRhythmRoutineStep(
                    id: "body_downshift",
                    title: "身体降档",
                    detail: "热水澡、拉伸或慢呼吸任选一个，目标是先降唤醒度。",
                    symbol: "figure.cooldown",
                    offsetMinutes: -35
                ),
                SleepRhythmRoutineStep(
                    id: "monitoring",
                    title: "开启睡眠监测",
                    detail: "确认 Apple Watch 佩戴稳定，必要时开启鼾声分析。",
                    symbol: "applewatch.watchface",
                    offsetMinutes: -10
                )
            ]
        case .travelReset:
            return [
                SleepRhythmRoutineStep(
                    id: "local_anchor",
                    title: "确认本地时间锚点",
                    detail: "今晚按本地目标入睡，不再按出差前或原时区节奏拖延。",
                    symbol: "location.fill",
                    offsetMinutes: -150
                ),
                SleepRhythmRoutineStep(
                    id: "light_plan",
                    title: "安排明早日照",
                    detail: "提前决定明早起床后去哪里见自然光。",
                    symbol: "sun.max.fill",
                    offsetMinutes: -90
                ),
                SleepRhythmRoutineStep(
                    id: "travel_pack_down",
                    title: "行李与设备收尾",
                    detail: "把充电、闹钟、明日衣物提前处理完，避免临睡前翻找。",
                    symbol: "suitcase.fill",
                    offsetMinutes: -45
                ),
                SleepRhythmRoutineStep(
                    id: "monitoring",
                    title: "开启睡眠监测",
                    detail: "确认 Apple Watch 佩戴稳定，必要时开启鼾声分析。",
                    symbol: "applewatch.watchface",
                    offsetMinutes: -10
                )
            ]
        case .bedtimeRoutine:
            return defaultSteps
        }
    }
}

struct SleepRhythmRebuildPlan {
    let headline: String
    let score: Int?
    let title: String
    let summary: String
    let targetBedtime: Date?
    let estimatedDays: Int
    let phaseTitle: String
    let phaseDetail: String
    let diagnosisTitle: String
    let diagnosisDetail: String
    let rescueTitle: String
    let rescueDetail: String
    let actions: [String]
    let routineSteps: [SleepRhythmRoutineStep]
}
