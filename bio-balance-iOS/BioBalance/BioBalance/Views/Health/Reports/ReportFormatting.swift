/// ReportFormatting 作为报告模块的编辑式格式化支撑。
/// 负责集中维护报告卡片的纸张色、墨色、金色强调和边框（ReportsEditorialStyle）。

import SwiftUI

// MARK: - 编辑式样式

/// 报告编辑式卡片的共享色板，集中维护纸张、墨色、金色强调和边框。
enum ReportsEditorialStyle {
    static let ink = Theme.Colors.textPrimary
    static let secondaryInk = Theme.Colors.textSecondary
    static let lavender = Color(hex: "F1EEFA")
    static let lavenderAccent = Color(hex: "7D70AA")
    static let warmGold = Color(hex: "E3A70C")
    static let warmGoldSoft = Color(hex: "F8EDCC")
    static let neutralPanel = Theme.Colors.secondarySurface
    static let border = Theme.Colors.surfaceBorder
}

extension Date {
    /// 生成时区敏感的自然日键，供图表对齐同一天的不同时刻样本。
    func reportsDayKey(calendar: Calendar = .current) -> Int64 {
        Int64(calendar.startOfDay(for: self).timeIntervalSince1970)
    }
}

// MARK: - 指标格式化工具

/// 单指标复盘展示真实量纲；评分归一化仍仅用于综合评分与状态摘要。
enum WeeklyReportTrendData {
    /// 只命中选中自然日，绝不借用相邻日期填补空白。
    static func selectedIndex(for date: Date?, dates: [Date], calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        return dates.firstIndex { calendar.isDate($0, inSameDayAs: date) }
    }

    static func valueText(_ value: Double, kind: ReportMetricKind) -> String {
        switch kind {
        case .sleep:
            let minutes = Int((value * 60).rounded())
            return String(localized: "\(minutes / 60) 小时 \(minutes % 60) 分钟")
        case .activity: return String(localized: "\(Int(value.rounded()).formatted()) 步")
        case .stress: return String(localized: "\(Int(value.rounded())) 压力指数")
        case .hrv: return String(format: "%.0f ms", value)
        }
    }

    static func points(for kind: ReportMetricKind, in summaries: [ReportDaySummary]) -> [ReportMetricPlotPoint] {
        summaries.sorted { $0.date < $1.date }.compactMap { summary in
            let raw: Double?
            switch kind {
            case .sleep: raw = summary.sleepHours
            case .activity: raw = summary.steps
            case .stress: raw = summary.stress
            case .hrv: raw = summary.hrv
            }
            guard let raw, raw.isFinite, raw >= 0 else { return nil }
            if (kind == .sleep || kind == .hrv) && raw == 0 { return nil }
            return ReportMetricPlotPoint(date: summary.date, kind: kind, value: raw,
                                         rawValueText: valueText(raw, kind: kind))
        }
    }

    static func usesBars(for kind: ReportMetricKind) -> Bool {
        kind == .sleep || kind == .activity
    }

    static func domain(for kind: ReportMetricKind, values: [Double]) -> ClosedRange<Double> {
        let maximum = values.filter { $0.isFinite && $0 >= 0 }.max() ?? 0
        switch kind {
        case .sleep: return 0...max(10, ceil(maximum / 2) * 2)
        case .activity: return 0...max(10_000, ceil(maximum / 5_000) * 5_000)
        case .stress: return 0...max(100, ceil(maximum / 20) * 20)
        case .hrv: return 0...max(60, ceil(maximum / 20) * 20)
        }
    }
}

/// 报告指标格式化工具枚举
/// 提供归一化、原始值文本、绘图点、覆盖率、排行、分布等格式化能力，供各报告页面统一调用。
enum ReportMetricFormatter {
    /// 将原始指标归一化到 0–100 分，便于跨指标比较
    static func normalizedValue(for kind: ReportMetricKind, in summary: ReportDaySummary) -> Double? {
        switch kind {
        case .sleep:
            guard let hours = summary.sleepHours, hours > 0 else { return nil }
            return max(0, min(100, 100 - abs(hours - 7.5) * 16))
        case .stress:
            guard let stress = summary.stress, stress > 0 else { return nil }
            return max(0, min(100, 100 - stress))
        case .hrv:
            guard let hrv = summary.hrv, hrv > 0 else { return nil }
            return max(0, min(100, hrv * 1.4))
        case .activity:
            guard let steps = summary.steps, steps > 0 else { return nil }
            return max(0, min(100, steps / 80.0))
        }
    }

    /// 返回指标原始值的可读文本（带单位）
    static func rawValueText(for kind: ReportMetricKind, in summary: ReportDaySummary) -> String {
        switch kind {
        case .sleep:
            return summary.sleepHours.map { String(format: "%.1f h", $0) } ?? "--"
        case .stress:
            return summary.stress.map { "\(Int($0.rounded()))" } ?? "--"
        case .hrv:
            return summary.hrv.map { "\(Int($0.rounded())) ms" } ?? "--"
        case .activity:
            return summary.steps.map { String(format: "%.1fk", $0 / 1000.0) } ?? "--"
        }
    }

    /// 从多日摘要中生成指定指标的绘图点序列
    static func plotPoints(from summaries: [ReportDaySummary], kinds: [ReportMetricKind]) -> [ReportMetricPlotPoint] {
        summaries
            .sorted { $0.date < $1.date }
            .flatMap { summary in
                kinds.compactMap { kind in
                    guard let value = normalizedValue(for: kind, in: summary) else { return nil }
                    return ReportMetricPlotPoint(
                        date: summary.date,
                        kind: kind,
                        value: value,
                        rawValueText: rawValueText(for: kind, in: summary)
                    )
                }
            }
    }

    /// 计算指定指标在一段时间内的平均归一化分值
    static func averageNormalizedValue(for kind: ReportMetricKind, in summaries: [ReportDaySummary]) -> Int? {
        let values = summaries.compactMap { normalizedValue(for: kind, in: $0) }
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    /// 计算指定指标在一段时间内的平均原始值文本
    static func averageRawValueText(for kind: ReportMetricKind, in summaries: [ReportDaySummary]) -> String {
        switch kind {
        case .sleep:
            let values = summaries.compactMap(\.sleepHours)
            guard !values.isEmpty else { return "--" }
            let average = values.reduce(0, +) / Double(values.count)
            return String(format: "%.1f h", average)
        case .stress:
            let values = summaries.compactMap(\.stress)
            guard !values.isEmpty else { return "--" }
            let average = values.reduce(0, +) / Double(values.count)
            return "\(Int(average.rounded()))"
        case .hrv:
            let values = summaries.compactMap(\.hrv)
            guard !values.isEmpty else { return "--" }
            let average = values.reduce(0, +) / Double(values.count)
            return "\(Int(average.rounded())) ms"
        case .activity:
            let values = summaries.compactMap(\.steps)
            guard !values.isEmpty else { return "--" }
            let average = values.reduce(0, +) / Double(values.count)
            return String(format: "%.1fk", average / 1000.0)
        }
    }

    /// 判断某天内是否存在指定指标的有效数据
    static func hasMetric(_ kind: ReportMetricKind, in summary: ReportDaySummary) -> Bool {
        normalizedValue(for: kind, in: summary) != nil
    }

    /// 从多日摘要中生成各指标的覆盖率项
    static func coverageItems(from summaries: [ReportDaySummary], expectedCount: Int) -> [ReportMetricCoverageItem] {
        let denominator = max(expectedCount, summaries.count, 1)
        return ReportMetricKind.allCases.map { kind in
            ReportMetricCoverageItem(
                kind: kind,
                availableCount: summaries.filter { hasMetric(kind, in: $0) }.count,
                expectedCount: denominator
            )
        }
    }

    /// 计算整体覆盖率百分比（0–100）
    static func overallCoveragePercent(from summaries: [ReportDaySummary], expectedCount: Int) -> Int {
        let items = coverageItems(from: summaries, expectedCount: expectedCount)
        guard !items.isEmpty else { return 0 }
        let average = items.map(\.ratio).reduce(0, +) / Double(items.count)
        return Int((average * 100).rounded())
    }

    /// 生成指标排行项，按分值从高到低排序
    static func metricRankItems(from summaries: [ReportDaySummary]) -> [ReportMetricRankItem] {
        ReportMetricKind.allCases.compactMap { kind in
            guard let score = averageNormalizedValue(for: kind, in: summaries) else { return nil }
            return ReportMetricRankItem(
                kind: kind,
                score: score,
                rawValueText: averageRawValueText(for: kind, in: summaries),
                note: metricRankNote(kind: kind, score: score)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.score > rhs.score
        }
    }

    /// 将评分按区间统计为分布桶
    static func scoreDistribution(from points: [ReportDaySummary]) -> [ReportScoreDistributionBucket] {
        let scored = points.compactMap(\.score)
        let buckets: [(String, ClosedRange<Int>, Color)] = [
            ("优秀", 85...100, Theme.Colors.mintGreen),
            ("稳定", 70...84, Color(hex: "5B8CFF")),
            ("波动", 50...69, Color(hex: "F3A53B")),
            ("承压", 0...49, Color(hex: "F46B5A"))
        ]

        return buckets.map { title, range, tint in
            ReportScoreDistributionBucket(
                title: title,
                range: range,
                tint: tint,
                count: scored.filter { range.contains($0) }.count
            )
        }
    }

    /// 根据指标类型和分值生成对应的解读备注
    private static func metricRankNote(kind: ReportMetricKind, score: Int) -> String {
        switch (kind, score) {
        case (.sleep, 82...): return "睡眠节律是当前恢复基础。"
        case (.sleep, 60..<82): return "睡眠基础可用，但仍有优化空间。"
        case (.sleep, _): return "睡眠是优先复盘项。"
        case (.stress, 82...): return "压力负荷控制得比较好。"
        case (.stress, 60..<82): return "压力整体可控，留意高峰日。"
        case (.stress, _): return "压力正在明显拖慢恢复。"
        case (.hrv, 82...): return "HRV 弹性表现较好。"
        case (.hrv, 60..<82): return "HRV 处在中间区间。"
        case (.hrv, _): return "HRV 偏弱，适合降低强度。"
        case (.activity, 82...): return "活动量能托住日常节律。"
        case (.activity, 60..<82): return "活动量够用但不突出。"
        case (.activity, _): return "活动不足，建议补轻量移动。"
        }
    }
}

// MARK: - 评分色板

/// 报告评分颜色映射工具
/// 将评分区间统一映射到主题色，保证所有图表和卡片使用一致的视觉语言。
enum ReportsScorePalette {
    /// 根据评分返回对应的主题色
    static func tint(for score: Int?) -> Color {
        guard let score else { return Color(hex: "8AA0B8") }
        switch score {
        case 85...: return Theme.Colors.mintGreen
        case 70..<85: return Color(hex: "5B8CFF")
        case 50..<70: return Color(hex: "F3A53B")
        default: return Color(hex: "F46B5A")
        }
    }
}

// MARK: - 图表样式常量

/// 报告图表样式常量集合
/// 集中管理图表的线条、网格、标签、选区等视觉参数，避免散落在各处重复定义。
enum ReportsChartStyle {
    /// 评分曲线默认样式
    static let score = BBChartStyle.trendLine
    /// 网格线样式
    static let grid = BBChartStyle.grid.opacity(0.72)
    /// 坐标轴标签颜色
    static let axisLabel = Theme.Colors.textTertiary
    /// 均值参考线颜色
    static let averageLine = Theme.Colors.textSecondary.opacity(0.62)
    /// 稳定基线颜色
    static let stabilityLine = BBChartStyle.baseline.opacity(0.58)
    /// 选区指示线颜色
    static let selectionLine = BBChartStyle.selection
    /// 图表绘图区背景色
    static let plotBackground = BBChartStyle.plotBackground
}
