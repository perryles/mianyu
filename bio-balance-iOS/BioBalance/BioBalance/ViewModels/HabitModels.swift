import SwiftUI

/// Habit 展示模型与枚举。
/// 从原 HabitViewModel.swift 拆出：与 VM 行为无关的纯数据模型保持独立。

import SwiftUI

/// HabitLifeRow枚举 作为视图模型层里的状态与分类定义。
/// 负责描述界面状态管理与业务编排过程中会用到的状态、分类或分支。
enum HabitLifeRowDestination: String, CaseIterable, Identifiable {
    case drinkHub
    case sunlight
    case mindfulness

    var id: String { rawValue }
}

/// Habit每日操作枚举 作为视图模型层里的状态与分类定义。
/// 负责描述界面状态管理与业务编排过程中会用到的状态、分类或分支。
enum HabitDailyActionDestination: String, Identifiable {
    case water
    case sunlight
    case mindfulness
    case stand

    var id: String { rawValue }
}

/// HabitLifeRow数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct HabitLifeRowModel: Identifiable {
    let destination: HabitLifeRowDestination
    let title: String
    let symbol: String
    let valueText: String
    let unitText: String
    let tintHex: String

    var id: String { destination.rawValue }
}

/// Habit每日操作数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct HabitDailyActionCardModel: Identifiable {
    let destination: HabitDailyActionDestination
    let title: String
    let reasonText: String
    let progressText: String
    let buttonTitle: String
    let tintHex: String
    let symbol: String
    let isCompleted: Bool
    let isShared: Bool

    var id: String { destination.rawValue }
}

/// Habit身体指标枚举 作为视图模型层里的状态与分类定义。
/// 负责描述界面状态管理与业务编排过程中会用到的状态、分类或分支。
enum HabitBodyMetricKind: String, CaseIterable, Identifiable {
    case basal
    case active
    case stand
    case hrv
    case restingHeartRate
    case sunlight
    case wristTemperature
    case walkingAsymmetry

    var id: String { rawValue }
}

/// Habit身体Hero数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct HabitBodyHeroCardModel {
    let title: String
    let statusText: String
    let detailText: String
    let averageText: String
    let maxText: String
    let minText: String
    let trendSummaryText: String
    let comparisonText: String
    let referenceValue: Double?
    let highlightValue: Double?
    let trendPoints: [HabitTrendPoint]
    let startLabel: String
    let endLabel: String
    let usesFallbackTrend: Bool
    let isEmpty: Bool

    static let placeholder = HabitBodyHeroCardModel(
        title: "心率变化",
        statusText: "暂无",
        detailText: "等待健康 App 同步心率记录",
        averageText: "--",
        maxText: "--",
        minText: "--",
        trendSummaryText: "暂无趋势",
        comparisonText: "等待健康 App 同步心率记录",
        referenceValue: nil,
        highlightValue: nil,
        trendPoints: [],
        startLabel: "",
        endLabel: "",
        usesFallbackTrend: false,
        isEmpty: true
    )
}

/// Habit身体指标数据模型 作为视图模型层里的数据载体。
/// 负责界面状态管理与业务编排。
struct HabitBodyMetricCardModel: Identifiable {
    let kind: HabitBodyMetricKind
    let title: String
    let valueText: String
    let unitText: String
    let goalText: String
    let subtitleText: String
    let trendSummaryText: String
    let comparisonText: String
    let referenceValue: Double?
    let highlightValue: Double?
    let symbol: String
    let tintHex: String
    let trendPoints: [HabitTrendPoint]
    let isEmpty: Bool

    var id: String { kind.rawValue }
}

/// Habit视图模型 作为视图模型层里的界面状态管理入口。
/// 负责界面状态管理与业务编排。

