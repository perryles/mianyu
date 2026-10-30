import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import OSLog


/// DashboardViewModel 其他指标卡片构建与数值格式化。
/// 从原 DashboardViewModel.swift 拆出，对外接口不变。

@MainActor
extension DashboardViewModel {

    func makeHRVCard(current: Double?, previous: Double?, trend: [TimeSeriesPointDouble]) -> DashboardOtherMetricCardModel {
        let tone: DashboardOtherMetricStatusTone
        let status: String
        if let current {
            if current >= 65 {
                tone = .positive
                status = "优秀"
            } else if current >= 40 {
                tone = .normal
                status = "正常"
            } else {
                tone = .caution
                status = "偏低"
            }
        } else {
            tone = .muted
            status = "暂无"
        }

        return DashboardOtherMetricCardModel(
            id: DashboardOtherMetricDestination.hrv.rawValue,
            title: "HRV",
            valueText: formatValue(current, digits: 0, fallback: "暂无"),
            unitText: "ms",
            statusText: status,
            statusTone: tone,
            deltaText: deltaText(current: current, previous: previous, unit: "ms", positiveWord: "增加", negativeWord: "降低"),
            lastUpdatedText: lastUpdatedText(from: trend),
            trendPoints: trend,
            isInteractive: true,
            destination: .hrv
        )
    }

    func makeRestingHeartRateCard(current: Double?, previous: Double?, trend: [TimeSeriesPointDouble]) -> DashboardOtherMetricCardModel {
        let tone: DashboardOtherMetricStatusTone
        let status: String
        if let current {
            if current <= 58 {
                tone = .positive
                status = "优秀"
            } else if current <= 68 {
                tone = .normal
                status = "正常"
            } else {
                tone = .caution
                status = "偏高"
            }
        } else {
            tone = .muted
            status = "暂无"
        }

        return DashboardOtherMetricCardModel(
            id: DashboardOtherMetricDestination.restingHeartRate.rawValue,
            title: "静息心率",
            valueText: formatValue(current, digits: 0, fallback: "暂无"),
            unitText: "bpm",
            statusText: status,
            statusTone: tone,
            deltaText: deltaText(current: current, previous: previous, unit: "bpm", positiveWord: "升高", negativeWord: "降低"),
            lastUpdatedText: lastUpdatedText(from: trend),
            trendPoints: trend,
            isInteractive: true,
            destination: .restingHeartRate
        )
    }

    func makeHeartRhythmCard(result: HeartRhythmStabilityResult) -> DashboardOtherMetricCardModel {
        let status = HeartRhythmStabilityPresentation.statusText(for: result)
        let tone: DashboardOtherMetricStatusTone
        switch HeartRhythmStabilityPresentation.tone(for: result) {
        case .positive: tone = .positive
        case .normal: tone = .normal
        case .caution: tone = .caution
        case .muted: tone = .muted
        }

        return DashboardOtherMetricCardModel(
            id: DashboardOtherMetricDestination.heartRhythm.rawValue,
            title: HeartRhythmStabilityPresentation.title,
            valueText: HeartRhythmStabilityPresentation.valueText(for: result),
            unitText: HeartRhythmStabilityPresentation.unitText(for: result),
            statusText: status,
            statusTone: tone,
            deltaText: "",
            lastUpdatedText: result.lastEventDate.map {
                $0.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
            } ?? "",
            trendPoints: [],
            isInteractive: true,
            destination: .heartRhythm
        )
    }

    func makeWristTemperatureCard(current: Double?, previous: Double?, trend: [TimeSeriesPointDouble]) -> DashboardOtherMetricCardModel {
        let tone: DashboardOtherMetricStatusTone
        let status: String
        if let current {
            if current >= 34 && current <= 37.8 {
                tone = .normal
                status = "正常"
            } else {
                tone = .caution
                status = "留意"
            }
        } else {
            tone = .muted
            status = "暂无"
        }

        return DashboardOtherMetricCardModel(
            id: DashboardOtherMetricDestination.wristTemperature.rawValue,
            title: "手腕温度",
            valueText: formatValue(current, digits: 1, fallback: "暂无"),
            unitText: "℃",
            statusText: status,
            statusTone: tone,
            deltaText: deltaText(current: current, previous: previous, unit: "℃", positiveWord: "增加", negativeWord: "降低"),
            lastUpdatedText: lastUpdatedText(from: trend),
            trendPoints: trend,
            isInteractive: true,
            destination: .wristTemperature
        )
    }

    func makeSunlightCard(current: Double?, previous: Double?, trend: [TimeSeriesPointDouble]) -> DashboardOtherMetricCardModel {
        let tone: DashboardOtherMetricStatusTone
        let status: String
        if let current {
            if current >= 20 {
                tone = .positive
                status = "达标"
            } else if current > 0 {
                tone = .normal
                status = "进行中"
            } else {
                tone = .muted
                status = "暂无"
            }
        } else {
            tone = .muted
            status = "暂无"
        }

        return DashboardOtherMetricCardModel(
            id: DashboardOtherMetricDestination.sunlight.rawValue,
            title: "晒太阳时间",
            valueText: formatValue(current, digits: 0, fallback: "暂无"),
            unitText: "分钟",
            statusText: status,
            statusTone: tone,
            deltaText: deltaText(current: current, previous: previous, unit: "分钟", positiveWord: "增加", negativeWord: "减少"),
            lastUpdatedText: lastUpdatedText(from: trend),
            trendPoints: trend,
            isInteractive: true,
            destination: .sunlight
        )
    }

    func makeWalkingAsymmetryCard(current: Double?, previous: Double?, trend: [TimeSeriesPointDouble]) -> DashboardOtherMetricCardModel {
        let tone: DashboardOtherMetricStatusTone
        let status: String
        if let current {
            if current <= 10 {
                tone = .normal
                status = "正常"
            } else if current <= 15 {
                tone = .caution
                status = "留意"
            } else {
                tone = .caution
                status = "偏高"
            }
        } else {
            tone = .muted
            status = "暂无"
        }

        return DashboardOtherMetricCardModel(
            id: DashboardOtherMetricDestination.walkingAsymmetry.rawValue,
            title: "步态不对称",
            valueText: formatValue(current, digits: 1, fallback: "暂无"),
            unitText: "%",
            statusText: status,
            statusTone: tone,
            deltaText: deltaText(current: current, previous: previous, unit: "%", positiveWord: "增加", negativeWord: "降低"),
            lastUpdatedText: lastUpdatedText(from: trend),
            trendPoints: trend,
            isInteractive: true,
            destination: .walkingAsymmetry
        )
    }

    func sanitizeTrend(_ points: [TimeSeriesPointDouble]) -> [TimeSeriesPointDouble] {
        points
            .filter { $0.value >= 0 }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(7)
            .map { $0 }
    }

    func positiveValue(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    func previousValue(in trend: [TimeSeriesPointDouble], relativeTo date: Date) -> Double? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: date)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        return trend.last(where: { calendar.isDate($0.date, inSameDayAs: yesterdayStart) })?.value
    }

    func formatValue(_ value: Double?, digits: Int, fallback: String) -> String {
        guard let value else { return fallback }
        return String(format: "%.\(digits)f", value)
    }

    func deltaText(current: Double?, previous: Double?, unit: String, positiveWord: String, negativeWord: String) -> String {
        guard let current, let previous else { return "暂无昨日对比" }
        let delta = current - previous
        let magnitude = abs(delta)
        if magnitude < 0.05 {
            return String(localized: "持平 相比于昨天")
        }
        let formatted: String
        if unit == "℃" || unit == "%" {
            formatted = String(format: "%.1f", magnitude)
        } else {
            formatted = String(format: "%.0f", magnitude)
        }
        let word = delta > 0 ? positiveWord : negativeWord
        return String(localized: "\(word) \(formatted)\(unit) 相比于昨天")
    }

    func lastUpdatedText(from trend: [TimeSeriesPointDouble]) -> String {
        guard let last = trend.last else { return "暂无日期" }
        return last.date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }
}
