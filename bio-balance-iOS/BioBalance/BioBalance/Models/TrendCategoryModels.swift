/// Trend Category Models 定义业务数据模型，负责承载页面渲染、状态计算或模块通信所需的数据结构。
import Foundation
import SwiftUI

/// 趋势分类枚举 作为数据模型层里的状态与分类定义。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum TrendCategoryStatus: String, Codable, Sendable, Hashable {
    case ready
    case partial
    case noData

    var title: String {
        switch self {
        case .ready: return "已接入"
        case .partial: return "部分接入"
        case .noData: return "暂无记录"
        }
    }

    var tint: Color {
        switch self {
        case .ready: return Theme.Colors.mintGreen
        case .partial: return Color(hex: "FFB340")
        case .noData: return Theme.Colors.textTertiary
        }
    }
}

/// 趋势分类枚举 作为数据模型层里的状态与分类定义。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum TrendCategoryID: String, CaseIterable, Identifiable, Sendable, Hashable {
    case heartCardio
    case bodyMetrics
    case dailyActivity
    case sleepRecovery
    case mobilityGait
    case reproductive
    case vitalsRespiratory
    case runningDynamics
    case cyclingStats
    case swimmingWater
    case workoutsTraining
    case environmentSenses
    case nutritionHydration
    case mindfulnessMental
    case symptomsIllness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartCardio: return "心率"
        case .bodyMetrics: return "身体成分"
        case .dailyActivity: return "步速"
        case .sleepRecovery: return "睡眠"
        case .mobilityGait: return "步态行动"
        case .reproductive: return "周期健康"
        case .vitalsRespiratory: return "生命体征"
        case .runningDynamics: return "跑步趋势"
        case .cyclingStats: return "骑行表现"
        case .swimmingWater: return "游泳趋势"
        case .workoutsTraining: return "健身记录"
        case .environmentSenses: return "环境感官"
        case .nutritionHydration: return "营养摄入"
        case .mindfulnessMental: return "心理正念"
        case .symptomsIllness: return "症状与病史"
        }
    }

    var subtitle: String {
        switch self {
        case .heartCardio: return "Heart Rate Health"
        case .bodyMetrics: return "Body Metrics"
        case .dailyActivity: return "Walking Speed"
        case .sleepRecovery: return "Sleep"
        case .mobilityGait: return "Gait Motion"
        case .reproductive: return "Cycle Health"
        case .vitalsRespiratory: return "Vitals & Respiratory"
        case .runningDynamics: return "Running Dynamics"
        case .cyclingStats: return "Cycling Stats"
        case .swimmingWater: return "Swimming & Water"
        case .workoutsTraining: return "Workouts & Training"
        case .environmentSenses: return "Environment & Senses"
        case .nutritionHydration: return "Nutrition & Hydration"
        case .mindfulnessMental: return "Mindfulness & Mental"
        case .symptomsIllness: return "Symptoms & Illness"
        }
    }

    var icon: String {
        switch self {
        case .heartCardio: return "heart.text.square.fill"
        case .bodyMetrics: return "figure.arms.open"
        case .dailyActivity: return "figure.walk.motion"
        case .sleepRecovery: return "bed.double.fill"
        case .mobilityGait: return "figure.walk.departure"
        case .reproductive: return "calendar.badge.clock"
        case .vitalsRespiratory: return "lungs.fill"
        case .runningDynamics: return "figure.run.square.stack.fill"
        case .cyclingStats: return "bicycle.circle.fill"
        case .swimmingWater: return "water.waves"
        case .workoutsTraining: return "figure.strengthtraining.traditional"
        case .environmentSenses: return "sun.max.fill"
        case .nutritionHydration: return "drop.circle.fill"
        case .mindfulnessMental: return "brain.head.profile"
        case .symptomsIllness: return "cross.case.fill"
        }
    }

    var badgeIcon: String {
        switch self {
        case .heartCardio: return "waveform.path.ecg"
        case .bodyMetrics: return "ruler"
        case .dailyActivity: return "speedometer"
        case .sleepRecovery: return "moon.stars.fill"
        case .mobilityGait: return "figure.walk"
        case .reproductive: return "drop.fill"
        case .vitalsRespiratory: return "waveform"
        case .runningDynamics: return "speedometer"
        case .cyclingStats: return "bolt.heart.fill"
        case .swimmingWater: return "drop.fill"
        case .workoutsTraining: return "bolt.fill"
        case .environmentSenses: return "ear.and.waveform"
        case .nutritionHydration: return "fork.knife"
        case .mindfulnessMental: return "sparkles"
        case .symptomsIllness: return "bandage.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .heartCardio: return Color(hex: "F05275")
        case .bodyMetrics: return Color(hex: "8EC5FF")
        case .dailyActivity: return Theme.Colors.mintGreen
        case .sleepRecovery: return Color(hex: "7D8BFF")
        case .mobilityGait: return Color(hex: "5DADE2")
        case .reproductive: return Color(hex: "C97C7A")
        case .vitalsRespiratory: return Color(hex: "FF9F0A")
        case .runningDynamics: return Color(hex: "FF7A59")
        case .cyclingStats: return Color(hex: "32ADE6")
        case .swimmingWater: return Color(hex: "27C2FF")
        case .workoutsTraining: return Color(hex: "7CD992")
        case .environmentSenses: return Color(hex: "B58AF3")
        case .nutritionHydration: return Color(hex: "FFB340")
        case .mindfulnessMental: return Color(hex: "5E5CE6")
        case .symptomsIllness: return Color(hex: "C98BFF")
        }
    }
}

/// 趋势分类指标数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendCategoryMetricModel: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let unit: String
    let points: [TimeSeriesPointDouble]
    let secondaryPoints: [TimeSeriesPointDouble]
    let status: TrendCategoryStatus
    let emptyMessage: String
    let accentHex: String
    let summary: String
}

/// 趋势Visualization枚举 作为数据模型层里的状态与分类定义。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum TrendVisualizationStyle: String, Sendable, Hashable {
    case lineArea
    case bar
    case rangeBand
    case distribution
    case heatStrip
    case segmentedSummary
    case vitalsAreaLine
    case vitalsSinglePoint
    case vitalsSegmentDotTrend
    case vitalsSoftRecoveryLine
    case vitalsDualRangeBar
}

/// 趋势Visualization解析器 作为数据模型层里的规则解析辅助类型。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum TrendVisualizationResolver {
    static func style(for metric: TrendCategoryMetricModel, category: TrendCategoryID? = nil) -> TrendVisualizationStyle {
        let title = metric.title.lowercased()
        let unit = metric.unit.lowercased()

        if let category {
            switch category {
            case .vitalsRespiratory:
                if metric.title.contains("呼吸率") {
                    return metric.points.count <= 1 ? .vitalsSinglePoint : .vitalsAreaLine
                }
                if metric.title.contains("血氧") {
                    return .vitalsSegmentDotTrend
                }
                if metric.title.contains("腕温") {
                    return .vitalsSoftRecoveryLine
                }
                if metric.title.contains("血压") {
                    return .vitalsDualRangeBar
                }
                return .lineArea
            case .sleepRecovery:
                if title.contains("深睡") || title.contains("rem") || title.contains("效率") || title.contains("规律") {
                    return .segmentedSummary
                }
                return .rangeBand
            case .dailyActivity:
                if metric.title.contains("静息能量") {
                    return .lineArea
                }
                return .bar
            case .workoutsTraining, .runningDynamics, .cyclingStats:
                return .bar
            case .environmentSenses:
                if metric.title == "日照时长" {
                    return .bar
                }
                if metric.title == "耳机暴露量" {
                    return .lineArea
                }
                if metric.title == "耳机暴露时长" {
                    return .bar
                }
                return .heatStrip
            case .nutritionHydration:
                if metric.title.contains("餐食") || metric.title == "饮水量" {
                    return .bar
                }
                if metric.title.contains("达标率") {
                    return .segmentedSummary
                }
                if metric.title.contains("咖啡因") {
                    return .lineArea
                }
                return .distribution
            default:
                break
            }
        }

        if title.contains("hrv") || title.contains("变异") || title.contains("心率") || title.contains("温度") {
            return .rangeBand
        }
        if title.contains("时长") || title.contains("步数") || title.contains("消耗") || title.contains("距离") || title.contains("分钟") {
            return .bar
        }
        if title.contains("占比") || title.contains("效率") || unit == "%" {
            return .segmentedSummary
        }
        if title.contains("暴露") || title.contains("噪音") || title.contains("日照") {
            return .heatStrip
        }
        if title.contains("摄入") || title.contains("饮水") || title.contains("营养") {
            return .distribution
        }
        return .lineArea
    }
}

/// 趋势摘要胶囊标签数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendSummaryPillModel: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let value: String
}

/// 趋势Hero摘要数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendHeroSummaryItem: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

/// 趋势图表Direction枚举 作为数据模型层里的能力或分类定义。
/// 负责描述业务数据结构定义过程中会用到的状态、分类或分支。
enum TrendChartDirection: String, Sendable, Hashable {
    case rising
    case falling
    case stable
    case volatile
    case insufficient
}

/// 趋势图表解读Line数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendChartInsightLineItem: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
}

/// 趋势图表解读数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendChartInsightSummary: Sendable, Hashable {
    let currentValueText: String
    let averageValueText: String
    let headline: String
    let selectionHeadline: String?
    let supportingLines: [TrendChartInsightLineItem]
    let footer: String
}

/// 睡眠趋势Clinical摘要数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct SleepTrendClinicalSummaryModel: Sendable, Hashable {
    let headline: String
    let explanation: String
    let heroItems: [TrendHeroSummaryItem]
    let stageHeadline: String
    let stageHighlights: [TrendSummaryPillModel]
}

/// 睡眠趋势AI解读数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct SleepTrendAIInsightModel: Sendable, Hashable {
    let summary: String
    let observations: [String]
    let guidance: String
}

/// 步态趋势AI解读数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct MobilityTrendAIInsightModel: Sendable, Hashable {
    let summary: String
    let observations: [String]
    let guidance: [String]
    let statusTitle: String
    let sourceLabel: String
}

/// Generic趋势AI解读数据模型 作为数据模型层里的数据载体。
/// 负责承载通用分类的 AI 洞悉内容。
struct GenericTrendAIInsightModel: Sendable, Hashable {
    let summary: String
    let observations: [String]
    let guidance: [String]
}

/// 心率ECGVoltage数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct HeartECGVoltagePoint: Identifiable, Sendable, Hashable {
    var id: Double { timeOffset }
    let timeOffset: Double
    let millivolts: Double
}

/// 心率ECG记录数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct HeartECGRecordModel: Identifiable, Sendable, Hashable {
    let id: String
    let sampledAt: Date
    let classificationTitle: String
    let classificationDetail: String
    let averageHeartRateText: String
    let samplingFrequencyText: String
    let durationText: String
    let symptomsStatusText: String
    let algorithmVersionText: String?
    let voltagePoints: [HeartECGVoltagePoint]
}

/// 心率ECG摘要数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct HeartECGSummaryModel: Sendable, Hashable {
    let status: TrendCategoryStatus
    let headline: String
    let detail: String
    let recordCountText: String
    let latestRecord: HeartECGRecordModel?
}

/// 心率ClinicalMonitor数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct HeartClinicalMonitorItem: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let status: TrendCategoryStatus
}

/// 心率ClinicalMonitor数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct HeartClinicalMonitorSummary: Sendable, Hashable {
    let headline: String
    let detail: String
    let items: [HeartClinicalMonitorItem]
}

/// 生理周期摘要数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct ReproductiveSummaryItem: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

/// 生理周期解读数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct ReproductiveInsightItem: Identifiable, Sendable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
}

/// 生理周期趋势详情数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct ReproductiveTrendDetailModel: Sendable, Hashable {
    let summary: PeriodSummary
    let heroItems: [ReproductiveSummaryItem]
    let insightItems: [ReproductiveInsightItem]
    let latestLogSummary: String
    let latestLogDetail: String
    let cycleStatusText: String
    let cycleStatusDetail: String
    let highlights: [String]
}

/// 趋势分类数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendCategoryCardModel: Identifiable, Sendable, Hashable {
    var id: TrendCategoryID { category }
    let category: TrendCategoryID
    let status: TrendCategoryStatus
    let primaryValueText: String
    let summary: String
    let highlights: [String]
}

/// 趋势分类详情数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct TrendCategoryDetailModel: Identifiable, Sendable, Hashable {
    var id: TrendCategoryID { category }
    let category: TrendCategoryID
    let headerSummary: String
    let metrics: [TrendCategoryMetricModel]
    let status: TrendCategoryStatus
    let sleepStages: [SleepStage]
    let sleepClinicalSummary: SleepTrendClinicalSummaryModel?
    let sleepAIInsight: SleepTrendAIInsightModel?
    let sleepCompositeScores: [SleepCompositeScoreBreakdown]
    let sleepNightSummaries: [SleepTrendNightSummary]
    let sleepCoreMetrics: [TrendCategoryMetricModel]
    let sleepRecoveryMetrics: [TrendCategoryMetricModel]
    let genericAIInsight: GenericTrendAIInsightModel?
    let mobilityAIInsight: MobilityTrendAIInsightModel?
    let reproductiveDetail: ReproductiveTrendDetailModel?
    let heartECGSummary: HeartECGSummaryModel?
    let heartECGRecords: [HeartECGRecordModel]
    let heartClinicalMonitorSummary: HeartClinicalMonitorSummary?
}

struct SleepCompositeScoreBreakdown: Identifiable, Sendable, Hashable {
    var id: Int64 { Int64(day.timeIntervalSince1970) }
    let day: Date
    let sleepDurationScore: Double
    let sleepRegularityScore: Double
    let sleepEfficiencyScore: Double
    let deepRecoveryScore: Double
    let mentalRecoveryScore: Double
    let physiologicalRecoveryScore: Double
    let overallScore: Double
}

/// 重点趋势分类数据模型 作为数据模型层里的数据载体。
/// 负责业务数据结构定义。
struct FeaturedTrendCategoryModel: Identifiable, Sendable, Hashable {
    var id: TrendCategoryID { category }
    let category: TrendCategoryID
    let primaryMetric: TrendCategoryMetricModel
    let supportingMetrics: [TrendCategoryMetricModel]
    let sleepNightSummaries: [SleepTrendNightSummary]
    let sleepRecoveryMetrics: [TrendCategoryMetricModel]
}
