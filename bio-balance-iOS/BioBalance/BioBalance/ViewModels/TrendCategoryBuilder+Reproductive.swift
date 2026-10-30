import Foundation
import HealthKit

/// TrendCategoryBuilder Reproductive 子模块。
/// 从 TrendCategoryBuilder.swift 按职责拆分，对外接口不变。

extension TrendCategoryBuilder {

    static func reproductiveStatus(summary: PeriodSummary) -> TrendCategoryStatus {
        let hasCycles = !(summary.cycles ?? []).isEmpty
        let hasLogs = !(summary.dayLogs ?? []).isEmpty
        let hasPredictions = summary.predictions?.nextPeriodStart != nil || summary.predictions?.fertileStart != nil
        if hasCycles && hasLogs {
            return .ready
        }
        if hasCycles || hasLogs || hasPredictions {
            return .partial
        }
        return .noData
    }

    static func reproductiveMetrics(
        from summary: PeriodSummary,
        fallbackPoints: [TimeSeriesPointDouble]
    ) -> [TrendCategoryMetricModel] {
        let flowPoints = reproductiveSeries(from: summary.dayLogs, keyPath: \.flowLevel, fallback: fallbackPoints)
        let painPoints = reproductiveSeries(from: summary.dayLogs, keyPath: \.painLevel, fallback: [])
        let moodPoints = reproductiveSeries(from: summary.dayLogs, keyPath: \.moodLevel, fallback: [])

        return [
            reproductiveMetric("出血记录", "级", points: flowPoints, status: metricStatus(for: flowPoints), accent: "FF8FB8"),
            reproductiveMetric("痛经强度", "级", points: painPoints, status: metricStatus(for: painPoints), accent: "0F2342"),
            reproductiveMetric("情绪波动", "级", points: moodPoints, status: metricStatus(for: moodPoints), accent: "4C7DFF")
        ]
    }

    static func reproductiveMetric(
        _ title: String,
        _ unit: String,
        points: [TimeSeriesPointDouble],
        status: TrendCategoryStatus,
        accent: String
    ) -> TrendCategoryMetricModel {
        let summary = points.last.map {
            unit.isEmpty ? "\(Int($0.value.rounded()))" : "\(Int($0.value.rounded()))\(unit)"
        } ?? "暂无"
        return TrendCategoryMetricModel(
            title: title,
            unit: unit,
            points: points,
            secondaryPoints: [],
            status: status,
            emptyMessage: "继续补充周期和症状记录后，这里会形成更完整的趋势。",
            accentHex: accent,
            summary: summary
        )
    }

    static func reproductiveSeries(
        from logs: [PeriodDayLog]?,
        keyPath: KeyPath<PeriodDayLog, Int?>,
        fallback: [TimeSeriesPointDouble]
    ) -> [TimeSeriesPointDouble] {
        let points = (logs ?? []).compactMap { log -> TimeSeriesPointDouble? in
            guard let rawDate = log.date, let date = dayFormatter.date(from: rawDate), let value = log[keyPath: keyPath] else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: Double(value))
        }
        return points.isEmpty ? fallback : points.sorted { $0.timestamp < $1.timestamp }
    }

    static func metricStatus(for points: [TimeSeriesPointDouble]) -> TrendCategoryStatus {
        if !points.isEmpty {
            return .ready
        }
        return .noData
    }

    static func metricStatusForPositiveValues(in points: [TimeSeriesPointDouble]) -> TrendCategoryStatus {
        if points.contains(where: { $0.value > 0 }) {
            return .ready
        }
        return .noData
    }

    static func reproductiveHeaderSummary(summary: PeriodSummary) -> String {
        guard let current = summary.current else {
            return String(localized: "继续记录周期后，这里会开始形成生理周期的阶段、窗口与体感趋势。")
        }
        let phase = phaseText(current.phase)
        let dayText = current.dayIndex.map { "第\($0)天" } ?? "周期观察"
        if current.isFertile == true {
            return String(localized: "当前处于\(phase) · \(dayText)，并落在易孕窗口内，适合结合症状与恢复状态一起看。")
        }
        return String(localized: "当前处于\(phase) · \(dayText)，可以继续结合最近记录判断周期节奏是否稳定。")
    }

    static func buildReproductiveDetail(summary: PeriodSummary) -> ReproductiveTrendDetailModel {
        let latestLog = (summary.dayLogs ?? []).sorted { ($0.date ?? "") > ($1.date ?? "") }.first
        let heroItems = [
            ReproductiveSummaryItem(
                title: "当前阶段",
                value: phaseText(summary.current?.phase),
                detail: summary.current?.dayIndex.map { "周期第\($0)天" } ?? "等待形成周期"
            ),
            ReproductiveSummaryItem(
                title: "下一关键时间",
                value: shortDate(summary.predictions?.nextPeriodStart),
                detail: predictionSourceText(summary.predictions?.source)
            ),
            ReproductiveSummaryItem(
                title: "易孕窗口",
                value: fertileWindowText(summary.predictions),
                detail: ovulationText(summary.predictions?.ovulationDate)
            ),
            ReproductiveSummaryItem(
                title: "最近记录",
                value: latestLog.map { "出血 \(reproductiveLevelText($0.flowLevel))" } ?? "--",
                detail: latestLog.map {
                    "痛经 \(reproductiveLevelText($0.painLevel)) · 情绪 \(reproductiveLevelText($0.moodLevel))"
                } ?? "等待记录"
            )
        ]

        return ReproductiveTrendDetailModel(
            summary: summary,
            heroItems: heroItems,
            insightItems: reproductiveInsights(summary: summary),
            latestLogSummary: latestLog.map {
                "出血 \(reproductiveLevelText($0.flowLevel)) / 痛经 \(reproductiveLevelText($0.painLevel)) / 情绪 \(reproductiveLevelText($0.moodLevel))"
            } ?? "暂无症状记录",
            latestLogDetail: latestLog?.note?.isEmpty == false ? (latestLog?.note ?? "") : "继续记录后，这里会更清楚地显示你的周期变化。",
            cycleStatusText: cycleStatusText(summary.current),
            cycleStatusDetail: cycleStatusDetail(summary: summary),
            highlights: [
                "排卵窗口提示来自已同步的易孕窗与排卵预测，不需要额外手动采集。",
                "把出血、痛经和情绪放在一起看，比单看经期开始日期更容易发现阶段波动。"
            ]
        )
    }

    static func reproductiveInsights(summary: PeriodSummary) -> [ReproductiveInsightItem] {
        let latestLog = (summary.dayLogs ?? []).sorted { ($0.date ?? "") > ($1.date ?? "") }.first
        var items: [ReproductiveInsightItem] = [
            ReproductiveInsightItem(
                title: "周期阶段洞察",
                detail: phaseInsight(current: summary.current)
            ),
            ReproductiveInsightItem(
                title: "排卵窗口提示",
                detail: fertileInsight(summary: summary)
            )
        ]
        if let latestLog {
            items.append(
                ReproductiveInsightItem(
                    title: "最近一次记录",
                    detail: latestLogInsight(latestLog)
                )
            )
        } else {
            items.append(
                ReproductiveInsightItem(
                    title: "记录建议",
                    detail: "先从当天出血、痛经和情绪开始记录，连续 3 到 7 天后趋势会更有参考价值。"
                )
            )
        }
        return Array(items.prefix(3))
    }

    static func cycleStatusText(_ current: PeriodCurrent?) -> String {
        guard let current else { return "周期观察" }
        let phase = phaseText(current.phase)
        return current.isPredicted == true ? "\(phase) · 预测周期" : phase
    }

    static func cycleStatusDetail(summary: PeriodSummary) -> String {
        if summary.current?.isFertile == true {
            return String(localized: "当前处在易孕窗口内，适合把症状、体感和恢复状态连起来一起看。")
        }
        if let next = summary.predictions?.nextPeriodStart {
            return String(localized: "下次预计经期 \(shortDate(next))，继续记录可以帮助校正周期节奏。")
        }
        return String(localized: "继续同步经期记录后，这里会形成更完整的周期预测。")
    }

    static func phaseInsight(current: PeriodCurrent?) -> String {
        guard let current else { return "当前还没有形成稳定周期，先补充经期开始日和当天症状记录。" }
        let phase = phaseText(current.phase)
        let day = current.dayIndex.map { "第\($0)天" } ?? "当前阶段"
        switch current.phase {
        case "MENSTRUATION":
            return String(localized: "当前处于\(phase) \(day)，更适合重点观察出血量和痛经是否比平时更重。")
        case "FOLLICULAR":
            return String(localized: "当前处于\(phase) \(day)，这一段更适合观察情绪和精力是否逐步回升。")
        case "OVULATION":
            return String(localized: "当前接近\(phase)，建议把前后几天的体感和情绪连起来一起看。")
        case "LUTEAL":
            return String(localized: "当前处于\(phase) \(day)，如果情绪或不适感上升，和前几天连着看更有意义。")
        default:
            return String(localized: "当前周期已开始形成，继续补记录后会更容易看出阶段差异。")
        }
    }

    static func fertileInsight(summary: PeriodSummary) -> String {
        guard let predictions = summary.predictions else {
            return String(localized: "易孕窗口会随着周期记录更新后自动调整。")
        }
        return String(localized: "\(fertileWindowText(predictions)) · \(ovulationText(predictions.ovulationDate))，这段时间更适合连续看前后几天的体感变化。")
    }

    static func latestLogInsight(_ log: PeriodDayLog) -> String {
        if let flow = log.flowLevel, flow >= 4 {
            return String(localized: "最近一次记录显示出血量偏高，建议和痛经及恢复状态一起看，而不是只看单天变化。")
        }
        if let pain = log.painLevel, pain >= 4 {
            return String(localized: "最近一次记录的不适感更明显，适合结合睡眠和压力趋势一起看。")
        }
        if let mood = log.moodLevel, mood >= 4 {
            return String(localized: "最近一次记录的情绪波动更突出，可以留意是否和黄体期或恢复不足同步出现。")
        }
        guard log.flowLevel != nil || log.painLevel != nil || log.moodLevel != nil else {
            return String(localized: "最近一次记录尚未填写出血、痛经或情绪，补充后再查看体感变化。")
        }
        return String(localized: "最近一次已记录项目整体较平稳，更适合继续观察接下来几天是否保持同样节奏。")
    }

    static func reproductiveLevelText(_ level: Int?) -> String {
        level.map { String($0) } ?? "未记录"
    }

    static func phaseText(_ raw: String?) -> String {
        switch raw {
        case "MENSTRUATION": return "经期"
        case "FOLLICULAR": return "卵泡期"
        case "OVULATION": return "排卵期"
        case "LUTEAL": return "黄体期"
        default: return "周期观察"
        }
    }

    static func predictionSourceText(_ raw: String?) -> String {
        switch raw?.uppercased() {
        case "HEALTHKIT", PeriodStore.healthPredictionSource:
            return String(localized: "健康 App 预测")
        case "LOCAL", PeriodStore.localPredictionSource:
            return String(localized: "本地估算")
        default:
            return String(localized: "周期预测")
        }
    }

    static func fertileWindowText(_ predictions: PeriodPredictions?) -> String {
        guard let start = predictions?.fertileStart, let end = predictions?.fertileEnd else { return "--" }
        return "\(shortDate(start)) - \(shortDate(end))"
    }

    static func ovulationText(_ raw: String?) -> String {
        guard let raw else { return "等待排卵提示" }
        return String(localized: "排卵提示 \(shortDate(raw))")
    }

    static func shortDate(_ raw: String?) -> String {
        guard let raw, let date = dayFormatter.date(from: raw) else { return "--" }
        return shortFormatter.string(from: date)
    }

}
