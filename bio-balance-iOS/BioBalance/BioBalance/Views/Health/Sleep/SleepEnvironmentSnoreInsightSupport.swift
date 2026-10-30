/// SleepEnvironmentSnoreInsightSupport 作为睡眠环境鼾声洞察的支撑类型。
/// 负责定义洞察语气枚举（平静/适度/谨慎/升高）及其颜色映射。

import Foundation
import SwiftUI

enum SleepEnvironmentInsightTone: String, Codable, Sendable {
    case calm
    case moderate
    case caution
    case elevated

    var tint: Color {
        switch self {
        case .calm:
            return Color(hex: "35C759")
        case .moderate:
            return Color(hex: "7A8FAE")
        case .caution:
            return Color(hex: "E4A03F")
        case .elevated:
            return Color(hex: "E0645C")
        }
    }
}

struct SleepEnvironmentSnoreInsight: Equatable, Sendable {
    let headline: String
    let summary: String
    let environmentLabel: String
    let snoreLabel: String
    let stageLinkText: String
    let suggestions: [String]
    let coverageFlags: [String]
    let tone: SleepEnvironmentInsightTone
}

struct SleepEnvironmentSnoreInsightBuilder {
    struct Input: Sendable {
        let date: Date
        let environmentalAudioDb: Double?
        let recentEnvironmentalAudioAverageDb: Double?
        let snoreSummary: SnoreAnalysisSummary?
        let sleepSummary: SleepTrendNightSummary?
    }

    private let healthKitManager: HealthKitManager

    init(healthKitManager: HealthKitManager = .shared) {
        self.healthKitManager = healthKitManager
    }

    func build(for date: Date, snoreSummary: SnoreAnalysisSummary?, sleepSummary: SleepTrendNightSummary?) async -> SleepEnvironmentSnoreInsight {
        let env = try? await healthKitManager.fetchEnvironmentalAudioExposure(on: date)
        let recent = try? await healthKitManager.fetchDailyEnvironmentalAudioExposureAverages(days: 7)
        let recentValues = (recent ?? []).map(\.value).filter { $0 > 0 }
        let average = recentValues.isEmpty ? nil : recentValues.reduce(0, +) / Double(recentValues.count)
        return build(
            from: .init(
                date: date,
                environmentalAudioDb: env ?? nil,
                recentEnvironmentalAudioAverageDb: average,
                snoreSummary: snoreSummary,
                sleepSummary: sleepSummary
            )
        )
    }

    func build(from input: Input) -> SleepEnvironmentSnoreInsight {
        let envDb = input.environmentalAudioDb
        let envAverage = input.recentEnvironmentalAudioAverageDb
        let snoreSummary = input.snoreSummary ?? derivedSnoreSummary(from: input.sleepSummary)
        let sleepSummary = input.sleepSummary

        var coverageFlags: [String] = []
        if envDb == nil {
            coverageFlags.append("缺少环境音量样本")
        }
        if snoreSummary == nil {
            coverageFlags.append("缺少鼾声摘要")
        }
        if sleepSummary == nil {
            coverageFlags.append("缺少睡眠阶段摘要")
        }

        let environmentLabel = environmentLabelText(current: envDb, baseline: envAverage)
        let snoreLabel = snoreLabelText(summary: snoreSummary)
        let stageLink = stageLinkText(summary: sleepSummary, snoreSummary: snoreSummary)

        let tone: SleepEnvironmentInsightTone
        let headline: String
        let summary: String
        let suggestions: [String]

        let isNoisy = (envDb ?? 0) >= 68
        let isAboveBaseline = {
            guard let envDb, let envAverage else { return false }
            return envDb - envAverage >= 5
        }()
        let snoreHigh = snoreSummary?.intensity == .high || (snoreSummary?.disturbanceScore ?? 0) >= 55
        let snorePresent = snoreSummary?.snoreDetected == true
        let awakeHeavy = (sleepSummary?.awakeMinutes ?? 0) >= 24

        if (isNoisy || isAboveBaseline) && snoreHigh {
            tone = .elevated
            headline = "环境噪声和鼾声在一起拖累昨夜恢复"
            summary = "昨夜环境音量偏高，同时鼾声干扰也比较明显，整夜恢复更容易被双重放大。"
            suggestions = [
                "今晚尽量把睡眠环境收安静一点，先减少外部噪声。",
                "如果方便，优先侧睡并继续观察连续几晚是否都出现明显鼾声。",
                "睡前 2 小时尽量减少额外刺激，让环境和身体一起降负荷。"
            ]
        } else if (isNoisy || isAboveBaseline) && (snorePresent || awakeHeavy) {
            tone = .caution
            headline = "环境偏吵，可能放大了夜间中断"
            summary = "鼾声本身未必是唯一问题，环境音量偏高时，夜间清醒和恢复断裂更容易被放大。"
            suggestions = [
                "今晚优先把床周围环境调安静，尤其避免持续底噪。",
                "如果夜间容易醒，睡前先把刺激性声音暴露压短。",
                "连续几晚都这样时，更值得回看环境和鼾声是否一起出现。"
            ]
        } else if !isNoisy && snoreHigh {
            tone = .caution
            headline = "昨夜更像是鼾声本身在影响恢复"
            summary = "环境音量没有明显偏高，但鼾声摘要偏重，说明干扰更可能主要来自呼吸噪声本身。"
            suggestions = [
                "继续观察是否连续多晚都出现高强度鼾声。",
                "优先侧睡，并尽量避免临睡前饮酒或太晚进食。",
                "如果白天困倦感持续明显，后续更值得关注这条信号。"
            ]
        } else if (envDb ?? 0) > 0 || snorePresent {
            tone = .moderate
            headline = "昨夜有轻度环境或鼾声干扰"
            summary = "昨夜已经能看到一些外部环境或鼾声痕迹，但整体更像轻度波动，还没到明显拖累恢复的程度。"
            suggestions = [
                "今晚继续守住固定入睡时间。",
                "把明显偏吵的环境时段压短一点。",
                "如果后续几晚干扰都累积，再结合睡眠评分一起看。"
            ]
        } else {
            tone = .calm
            headline = "昨夜环境和鼾声整体比较安静"
            summary = "环境音量和鼾声摘要都没有明显异常，昨夜恢复干扰更偏轻。"
            suggestions = [
                "继续保持当前睡眠环境。",
                "优先守住作息和睡前节律，不需要额外放大环境担忧。",
                "如果某天恢复变差，再回看是否有新的外部刺激出现。"
            ]
        }

        return SleepEnvironmentSnoreInsight(
            headline: headline,
            summary: summary,
            environmentLabel: environmentLabel,
            snoreLabel: snoreLabel,
            stageLinkText: stageLink,
            suggestions: suggestions,
            coverageFlags: coverageFlags,
            tone: tone
        )
    }

    private func environmentLabelText(current: Double?, baseline: Double?) -> String {
        guard let current else { return "环境音量待补样本" }
        if let baseline {
            let delta = current - baseline
            if delta >= 5 {
                return String(format: String(localized: "环境音量 %.0fdB，较近 7 天偏高"), current)
            }
            if delta <= -4 {
                return String(format: String(localized: "环境音量 %.0fdB，较近 7 天更安静"), current)
            }
        }
        if current >= 68 {
            return String(format: String(localized: "环境音量 %.0fdB，夜间偏吵"), current)
        }
        return String(format: String(localized: "环境音量 %.0fdB，整体可接受"), current)
    }

    private func snoreLabelText(summary: SnoreAnalysisSummary?) -> String {
        guard let summary else { return "鼾声摘要待补样本" }
        if !summary.snoreDetected {
            return String(localized: "昨夜没有明显鼾声聚集")
        }
        return String(localized: "鼾声 \(summary.intensity.title) · 干扰分 \(summary.disturbanceScore)")
    }

    private func stageLinkText(summary: SleepTrendNightSummary?, snoreSummary: SnoreAnalysisSummary?) -> String {
        guard let summary else { return "还缺少睡眠阶段样本，暂时无法看环境和阶段的关系。" }
        if summary.awakeMinutes >= 24, snoreSummary?.snoreDetected == true {
            return String(localized: "夜间清醒时段偏多，而且鼾声存在，说明恢复更容易被打断。")
        }
        if let deepRatio = summary.deepRatio, deepRatio < 0.16, snoreSummary?.snoreDetected == true {
            return String(localized: "深睡占比偏低且伴随鼾声，更容易让第二天恢复感变浅。")
        }
        return String(localized: "当前更适合把环境音、鼾声和夜间中断一起读，而不是分开看。")
    }

    private func derivedSnoreSummary(from summary: SleepTrendNightSummary?) -> SnoreAnalysisSummary? {
        guard let summary else { return nil }

        let durationHours = Double(summary.asleepMinutes) / 60.0
        let poorEfficiency = max(0.0, 0.9 - (summary.efficiency ?? 0.84))
        let awakeFactor = Double(max(0, summary.awakeMinutes - 18)) / 90.0
        let deepPenalty = max(0.0, 0.16 - (summary.deepRatio ?? 0.16))
        let normalized = min(0.72, max(0.0, poorEfficiency * 1.8 + awakeFactor + deepPenalty * 1.6))
        let detected = normalized >= 0.16

        let intensity: SleepSnoreIntensity
        switch normalized {
        case ..<0.16: intensity = .none
        case ..<0.30: intensity = .low
        case ..<0.52: intensity = .medium
        default: intensity = .high
        }

        let snoreMinutes = detected ? max(4, durationHours * normalized * 10.0) : 0
        let disturbance = min(85, max(0, Int((normalized * 72.0).rounded())))
        let segments = derivedSegments(for: summary, intensity: intensity, count: detected ? max(1, Int(snoreMinutes / 5.0)) : 0)
        let histogram = derivedHistogram(from: segments, start: summary.startTime)

        return SnoreAnalysisSummary(
            snoreDetected: detected,
            snoreDurationMinutes: snoreMinutes,
            snoreFrequencyPerHour: detected ? Double(segments.count) / max(durationHours, 1) : 0,
            intensity: intensity,
            disturbanceScore: disturbance,
            riskFlag: intensity == .high ? .elevated : (detected ? .monitor : .none),
            segments: segments,
            histogram: histogram
        )
    }

    private func derivedSegments(for night: SleepTrendNightSummary, intensity: SleepSnoreIntensity, count: Int) -> [SnoreSegmentSummary] {
        guard count > 0 else { return [] }
        let totalSeconds = max(1, night.endTime.timeIntervalSince(night.startTime))
        return (0..<count).map { index in
            let start = night.startTime.addingTimeInterval(totalSeconds * (Double(index + 1) / Double(count + 2)))
            let duration = Double(8 + index % 4)
            return SnoreSegmentSummary(
                segmentStart: start,
                segmentEnd: start.addingTimeInterval(duration),
                durationSeconds: duration,
                intensity: intensity,
                peakDbfsBucket: intensity == .high ? 11 : (intensity == .medium ? 8 : 5),
                confidence: intensity == .high ? 0.82 : 0.68,
                disturbanceWeight: intensity == .high ? 0.92 : 0.54
            )
        }
    }

    private func derivedHistogram(from segments: [SnoreSegmentSummary], start: Date) -> [Int] {
        var result = Array(repeating: 0, count: 6)
        let bucketSize: TimeInterval = 90 * 60
        for segment in segments {
            let idx = min(5, max(0, Int(segment.segmentStart.timeIntervalSince(start) / bucketSize)))
            result[idx] += 1
        }
        return result
    }
}
