import SwiftUI

// MARK: - 报告核心数据模型

/// 报告单日数据摘要模型
/// 承载一天内所有健康指标的综合快照，供报告页面展示与分享使用。
struct ReportDaySummary: Identifiable, Hashable {
    let id: Int64
    let date: Date
    let score: Int?
    let sleepHours: Double?
    let stress: Double?
    let hrv: Double?
    let steps: Double?
    let activeEnergy: Double?
    /// 日均心率（bpm），可选：旧调用点未提供时为 nil
    var averageHeartRate: Double? = nil
    /// 日步行/跑步距离（米），可选：旧调用点未提供时为 nil
    var distanceMeters: Double? = nil
    let recoveryScriptPlan: RecoveryScriptPlan?
    let caffeineWeeklySummary: CaffeineWeeklyCoachSummary?
    let scoreBreakdown: ReportScoreBreakdown?
    let adviceSummary: ReportAdviceSummary?
    let trendContext: ReportTrendContext?
    let timelineReplay: BehaviorTimelineReplay? = nil

    /// 是否有任何有效健康数据
    var hasData: Bool {
        sleepHours != nil || stress != nil || hrv != nil || steps != nil || activeEnergy != nil
    }

    /// 安全获取评分，缺失时返回 0
    var scoreValue: Int {
        score ?? 0
    }

    static func == (lhs: ReportDaySummary, rhs: ReportDaySummary) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Collection where Element == ReportDaySummary {
    /// 计算有效日评分的整数均值；缺失评分不作为 0 分参与。
    var reportsAverageScore: Int? {
        let scores = compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
}

// MARK: - 指标枚举

/// 报告展示的四种健康指标类型
enum ReportMetricKind: String, CaseIterable, Hashable {
    case sleep
    case stress
    case hrv
    case activity

    /// 指标中文名称
    var title: String {
        switch self {
        case .sleep: return "睡眠"
        case .stress: return "压力"
        case .hrv: return "HRV"
        case .activity: return "活动"
        }
    }

    /// 指标对应 SF Symbol 图标
    var systemImage: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .stress: return "brain.head.profile"
        case .hrv: return "waveform.path.ecg"
        case .activity: return "figure.walk"
        }
    }

    /// 指标主题色
    var tint: Color {
        switch self {
        case .sleep: return Color(hex: "5B8CFF")
        case .stress: return Color(hex: "FF8A5B")
        case .hrv: return Color(hex: "8E6CFF")
        case .activity: return Theme.Colors.mintGreen
        }
    }
}

extension ReportMetricKind: Identifiable {
    var id: String { rawValue }
}

// MARK: - 评分贡献度模型

/// 评分贡献度的定性分类（加分/拖累/一般/缺样本）
enum ReportContributionTone: String, Hashable {
    case positive
    case caution
    case neutral
    case missing

    /// 分类中文标签
    var title: String {
        switch self {
        case .positive: return "加分"
        case .caution: return "拖累"
        case .neutral: return "一般"
        case .missing: return "缺样本"
        }
    }
}

/// 单项指标对综合评分的贡献详情
struct ReportScoreContribution: Identifiable, Hashable {
    var id: String { kind.rawValue }
    let kind: ReportMetricKind
    let score: Int?
    let valueText: String
    let detail: String
    let tone: ReportContributionTone
}

/// 综合评分拆解结果，包含所有分项贡献和主要加/减分项
struct ReportScoreBreakdown: Hashable {
    let items: [ReportScoreContribution]
    let leadingPositiveKind: ReportMetricKind?
    let leadingNegativeKind: ReportMetricKind?
    let headline: String

    /// 表现最好的分项
    var leadingPositive: ReportScoreContribution? {
        guard let leadingPositiveKind else { return nil }
        return items.first(where: { $0.kind == leadingPositiveKind })
    }

    /// 表现最差的分项
    var leadingNegative: ReportScoreContribution? {
        guard let leadingNegativeKind else { return nil }
        return items.first(where: { $0.kind == leadingNegativeKind })
    }
}

// MARK: - 建议摘要模型

/// 当天行动建议摘要
struct ReportAdviceSummary: Hashable {
    let title: String
    let summary: String
    let actionItems: [String]
    let priorityText: String
    let tintHex: String

    var tint: Color {
        Color(hex: tintHex)
    }
}

// MARK: - 趋势上下文模型

/// 近期趋势状态枚举
enum ReportTrendState: String, Hashable {
    case recovering
    case stable
    case strained

    /// 趋势状态中文标签
    var title: String {
        switch self {
        case .recovering: return "恢复回升"
        case .stable: return "整体稳定"
        case .strained: return "近期承压"
        }
    }
}

/// 近 7 天趋势上下文，用于描述当天在近期曲线中的位置
struct ReportTrendContext: Hashable {
    let title: String
    let comparisonText: String
    let summary: String
    let state: ReportTrendState
}

/// 周期洞察结果（周报/月报共用）
struct ReportPeriodInsight: Hashable {
    let headline: String
    let detail: String
}

// MARK: - 图表数据模型

/// 指标趋势图上的单个数据点
struct ReportMetricPlotPoint: Identifiable, Hashable {
    let date: Date
    let kind: ReportMetricKind
    let value: Double
    let rawValueText: String

    var id: String { "\(Int64(date.timeIntervalSince1970))-\(kind.rawValue)" }
}

/// 评分分布桶（用于柱状图展示评分区间分布）
struct ReportScoreDistributionBucket: Identifiable {
    let title: String
    let range: ClosedRange<Int>
    let tint: Color
    let count: Int

    var id: String { title }
}

/// 指标排行项（用于维度排行卡片）
struct ReportMetricRankItem: Identifiable {
    let kind: ReportMetricKind
    let score: Int
    let rawValueText: String
    let note: String

    var id: String { kind.rawValue }
}

/// 指标数据覆盖率项
struct ReportMetricCoverageItem: Identifiable {
    let kind: ReportMetricKind
    let availableCount: Int
    let expectedCount: Int

    var id: String { kind.rawValue }

    /// 覆盖率比例（0-1）
    var ratio: Double {
        guard expectedCount > 0 else { return 0 }
        return min(1, max(0, Double(availableCount) / Double(expectedCount)))
    }

    /// 覆盖率百分比文本
    var percentText: String {
        "\(Int((ratio * 100).rounded()))%"
    }
}

/// 周期行动项（用于恢复行动计划卡片）
struct ReportPeriodActionItem: Identifiable {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var id: String { "\(title)-\(detail)" }
}

// MARK: - Takeaway 模型

/// 报告关键结论条目（用于 Takeaways 卡片）
struct ReportsTakeaway: Identifiable, Hashable {
    var id: String { "\(title)-\(value)-\(detail)" }
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
}

// MARK: - 历史记录模型

/// 报告历史条目
struct ReportHistoryItem: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let score: Int
    let highlights: [String]
    
    init(id: UUID = UUID(), date: Date, score: Int, highlights: [String]) {
        self.id = id
        self.date = date
        self.score = score
        self.highlights = highlights
    }
    
    /// 生成最近 N 天的示例数据
    static func sampleLastDays(_ count: Int, calendar: Calendar = .current) -> [ReportHistoryItem] {
        let today = calendar.startOfDay(for: Date())
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let seed = max(1, 97 - offset * 2)
            return ReportHistoryItem(
                date: date,
                score: max(45, min(95, seed)),
                highlights: [
                    "睡眠 \(max(5, 8 - offset % 3))h",
                    "压力 \(max(18, 55 - offset % 20))",
                    "HRV \(max(32, 62 - offset % 12))"
                ]
            )
        }
    }
}

/// 告警历史记录
struct AlertHistoryItem: Identifiable, Hashable {
    /// 告警类型枚举
    enum Kind: String, CaseIterable, Identifiable {
        case heartRate = "心率"
        case stress = "压力"
        case sleep = "睡眠"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .heartRate: return "heart.fill"
            case .stress: return "brain.head.profile"
            case .sleep: return "bed.double.fill"
            }
        }
    }
    
    let id: UUID
    let kind: Kind
    let date: Date
    let title: String
    let detail: String
    
    init(id: UUID = UUID(), kind: Kind, date: Date, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.detail = detail
    }
    
    /// 生成最近 N 条示例告警
    static func sampleRecent(_ count: Int, calendar: Calendar = .current) -> [AlertHistoryItem] {
        let now = Date()
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .hour, value: -(offset * 7 + 3), to: now) else { return nil }
            let kind: Kind = {
                switch offset % 3 {
                case 0: return .heartRate
                case 1: return .stress
                default: return .sleep
                }
            }()
            
            switch kind {
            case .heartRate:
                return AlertHistoryItem(kind: kind, date: date, title: "心率偏高", detail: "峰值 132 BPM，持续约 6 分钟")
            case .stress:
                return AlertHistoryItem(kind: kind, date: date, title: "压力升高", detail: "压力指数 84，建议进行呼吸练习")
            case .sleep:
                return AlertHistoryItem(kind: kind, date: date, title: "睡眠中断", detail: "夜间觉醒 3 次，建议优化作息")
            }
        }
    }
}

// MARK: - 统一状态文本

/// 评分状态文本统一映射
/// 消除多处重复的状态文本判断逻辑，所有页面共用同一套评分→文案映射。
enum ReportScoreStatus {
    /// 根据评分返回统一的状态短文本（用于标签、胶囊等场景）
    static func shortLabel(for score: Int?) -> String {
        guard let score else { return "等待样本" }
        switch score {
        case 85...: return "状态很稳"
        case 70..<85: return "总体平稳"
        case 50..<70: return "轻度波动"
        default: return "需要恢复"
        }
    }

    /// 根据评分返回 Hero 卡片用的标题文案
    static func headline(for score: Int?) -> String {
        guard let score else { return "健康数据正在汇总中" }
        switch score {
        case 85...: return "状态不错，恢复节奏比较完整"
        case 70..<85: return "时间基本够，连续性还有提升空间"
        case 50..<70: return "今天有些波动，先把恢复放前面"
        default: return "身体正在承压，今天不宜继续透支"
        }
    }

    /// 根据评分返回恢复基础文案（用于今日画像卡片）
    static func recoveryBaseText(for score: Int?) -> String {
        guard let score else { return "等待数据" }
        switch score {
        case 85...: return "可推进"
        case 70..<85: return "稳态"
        case 50..<70: return "需恢复"
        default: return "先保护"
        }
    }
}
