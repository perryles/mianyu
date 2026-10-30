import Foundation
import HealthKit

/// TrendCategoryBuilder Insights 子模块。
/// 从 TrendCategoryBuilder.swift 按职责拆分，对外接口不变。

extension TrendCategoryBuilder {

    static func buildSleepAIInsight(
        nights: [SleepTrendNightSummary],
        sleepPoints: [TimeSeriesPointDouble],
        consistencyPoints: [TimeSeriesPointDouble],
        sleepScorePoints: [TimeSeriesPointDouble],
        hrvPoints: [TimeSeriesPointDouble],
        nightlyHeartRatePoints: [TimeSeriesPointDouble]
    ) -> SleepTrendAIInsightModel? {
        guard !sleepPoints.isEmpty || !nights.isEmpty else {
            return SleepTrendAIInsightModel(
                summary: "当前睡眠样本还不足，AI 暂时无法判断这段时间的结构变化。",
                observations: ["先继续积累 3 到 7 天的睡眠记录。"],
                guidance: "等趋势成形后，再结合睡眠规律性和恢复指标一起阅读。"
            )
        }

        let averageSleep = averageValue(for: sleepPoints) ?? 0
        let averageConsistency = averageValue(for: consistencyPoints)
        let averageSleepScore = averageValue(for: sleepScorePoints) ?? 0
        let lastNight = nights.last
        let deepRatio = lastNight?.deepRatio ?? 0
        let remRatio = lastNight?.remRatio ?? 0
        let hrvDelta = trendDelta(for: hrvPoints)
        let nightlyHeartRateDelta = trendDelta(for: nightlyHeartRatePoints)

        let summary: String
        if averageSleep < 390 {
            summary = "最近最值得先看的不是睡眠结构，而是总睡眠时长偏短；只要这个底盘没站稳，恢复信号通常也很难真正回升。"
        } else if averageSleepScore > 0, averageSleepScore < 70 {
            summary = "最近睡眠带来的恢复收益还不够稳定，问题更像出在整夜恢复完成度不足，而不只是某一个阶段单独偏低。"
        } else if deepRatio > 0 && deepRatio < 0.15 {
            summary = "最近睡眠时长不算最短，但深睡占比偏低，说明当前更值得关注恢复结构本身，而不是只补总时长。"
        } else if let averageConsistency, averageConsistency < 70 {
            summary = "最近更明显的变化是作息规律性在下降，这通常比单晚多睡或少睡更能解释为什么恢复感没有一起跟上。"
        } else {
            summary = "最近睡眠结构整体还算稳定，接下来更有参考价值的是继续看恢复指标有没有和睡眠一起同步改善。"
        }

        var observations: [String] = []
        observations.append(averageSleep < 390 ? "平均睡眠时长低于 6.5 小时。" : "睡眠时长已有基本积累。")
        if averageSleepScore > 0 {
            observations.append(averageSleepScore < 70 ? "睡眠评分所反映的综合恢复完成度仍不足。" : "睡眠评分所反映的综合恢复完成度已回到可读区间。")
        }
        if let averageConsistency {
            observations.append(averageConsistency < 70 ? "作息规律性下降，夜间入睡节律有波动。" : "作息规律性基本稳定。")
        }
        if deepRatio > 0 {
            observations.append(deepRatio < 0.15 ? "深睡占比低于当前周期理想水平。" : "深睡结构基本可接受。")
        } else if remRatio > 0 {
            observations.append(remRatio < 0.18 ? "REM 占比偏低，睡眠结构还不够完整。" : "REM 结构没有明显短板。")
        }
        if let hrvDelta, let nightlyHeartRateDelta, hrvDelta <= 0, nightlyHeartRateDelta > 0 {
            observations.append("睡眠 HRV 没有回升，同时夜间心率略有上行，恢复信号仍偏保守。")
        }

        let guidance: String
        if averageSleep < 390 {
            guidance = "先把总睡眠时长拉回稳定区间，再看深睡和恢复指标是否同步改善。"
        } else if averageSleepScore > 0, averageSleepScore < 70 {
            guidance = "先把综合恢复完成度稳定拉回可接受区间，再判断夜间恢复信号是否真正改善。"
        } else if let averageConsistency, averageConsistency < 70 {
            guidance = "先稳住睡眠节律，再判断深睡结构和恢复质量是否真正改善。"
        } else if deepRatio > 0, deepRatio < 0.15 {
            guidance = "继续观察深睡占比与睡眠 HRV 的联动，不要只看总时长。"
        } else {
            guidance = "接下来更适合持续观察最近 1 到 2 周睡眠结构是否能稳定维持。"
        }

        return SleepTrendAIInsightModel(
            summary: summary,
            observations: Array(observations.prefix(3)),
            guidance: guidance
        )
    }

    static func buildMobilityAIInsight(
        walkingStepLengthPoints: [TimeSeriesPointDouble],
        walkingSpeedPoints: [TimeSeriesPointDouble],
        walkingAsymmetryPoints: [TimeSeriesPointDouble],
        walkingDoubleSupportPoints: [TimeSeriesPointDouble],
        walkingSteadinessPoints: [TimeSeriesPointDouble]
    ) -> MobilityTrendAIInsightModel? {
        let coreSeries = [
            walkingStepLengthPoints,
            walkingSpeedPoints,
            walkingAsymmetryPoints,
            walkingDoubleSupportPoints,
            walkingSteadinessPoints
        ]
        let availableSeriesCount = coreSeries.filter { !$0.isEmpty }.count
        guard availableSeriesCount > 0 else {
            return MobilityTrendAIInsightModel(
                summary: "当前步态行动样本还不足，暂时更适合继续积累步行记录。",
                observations: ["先连续记录几天步行活动，步幅、速度、平衡、支撑依赖和稳定性才会开始形成趋势。"],
                guidance: ["等样本积累起来后，再结合步幅、速度、平衡和稳定性一起阅读。"],
                statusTitle: "样本积累中",
                sourceLabel: "本地洞察"
            )
        }

        let stepLengthDelta = trendDelta(for: walkingStepLengthPoints)
        let speedDelta = trendDelta(for: walkingSpeedPoints)
        let asymmetryDelta = trendDelta(for: walkingAsymmetryPoints)
        let doubleSupportDelta = trendDelta(for: walkingDoubleSupportPoints)
        let steadinessDelta = trendDelta(for: walkingSteadinessPoints)
        let avgStepLength = averageValue(for: walkingStepLengthPoints)
        let avgSpeed = averageValue(for: walkingSpeedPoints)
        let avgAsymmetry = averageValue(for: walkingAsymmetryPoints)
        let avgDoubleSupport = averageValue(for: walkingDoubleSupportPoints)
        let avgSteadiness = averageValue(for: walkingSteadinessPoints)

        let stepLengthDown = (stepLengthDelta ?? 0) < -0.02
        let speedDown = (speedDelta ?? 0) < -0.04
        let speedUp = (speedDelta ?? 0) > 0.04
        let asymmetryUp = (asymmetryDelta ?? 0) > 0.5
        let asymmetryDown = (asymmetryDelta ?? 0) < -0.5
        let supportUp = (doubleSupportDelta ?? 0) > 0.6
        let steadinessDown = (steadinessDelta ?? 0) < -0.8
        let enoughSamples = coreSeries.contains { $0.count >= 3 }

        let statusTitle: String
        let summary: String

        if !enoughSamples {
            statusTitle = "样本积累中"
            summary = "最近已经有部分步态记录，但样本还不够连续；现阶段更适合先把步幅、速度、平衡和稳定性放在一起观察，而不是急着下结论。"
        } else if (speedDown && asymmetryUp) || supportUp || steadinessDown {
            statusTitle = "稳定性波动"
            summary = "最近行动效率、步态平衡或稳定性支撑里至少有一条在走弱，这更像行动稳定性开始松动，而不是单个指标偶尔波动。"
        } else if speedUp && asymmetryDown && !(stepLengthDown || supportUp || steadinessDown) {
            statusTitle = "行动顺畅"
            summary = "最近速度、步态平衡和稳定性一起朝更顺畅的方向变化，说明这段时间的行动效率整体比较稳定。"
        } else {
            statusTitle = "整体稳定"
            summary = "最近步态行动整体还算平稳，接下来更值得看的是步幅、速度、平衡和稳定性是否还能继续同向维持。"
        }

        var observations: [String] = []
        if let avgStepLength {
            if stepLengthDown {
                observations.append("步行步长近期略有收短，当前平均约 \(String(format: "%.2f", avgStepLength)) m。")
            } else {
                observations.append("步行步长当前平均约 \(String(format: "%.2f", avgStepLength)) m，可作为行动输出结构的补充线索。")
            }
        }

        if let avgSpeed {
            if speedDown {
                observations.append("步行速度近期有回落，当前平均约 \(String(format: "%.2f", avgSpeed)) m/s。")
            } else if speedUp {
                observations.append("步行速度近期稳中有升，当前平均约 \(String(format: "%.2f", avgSpeed)) m/s。")
            } else {
                observations.append("步行速度整体较平稳，当前平均约 \(String(format: "%.2f", avgSpeed)) m/s。")
            }
        } else {
            observations.append("步行速度样本还在积累中。")
        }

        if let avgAsymmetry {
            if asymmetryUp {
                observations.append("步伐不对称略有抬升，左右协同波动比前段时间更明显。")
            } else if asymmetryDown {
                observations.append("步伐不对称有所回落，左右步态协同正在变得更平衡。")
            } else {
                observations.append("步伐不对称整体平稳，当前平均约 \(String(format: "%.1f", avgAsymmetry))%。")
            }
        } else {
            observations.append("步态平衡样本还不足，暂时先以速度信号为主。")
        }

        if let avgDoubleSupport {
            if supportUp {
                observations.append("双足支撑时间有所抬升，当前平均约 \(String(format: "%.1f", avgDoubleSupport))%，和步伐不对称一起看更像稳定性代偿在增加。")
            } else {
                observations.append("双足支撑时间整体平稳，当前平均约 \(String(format: "%.1f", avgDoubleSupport))%，稳定性支撑节奏暂时没有明显走偏。")
            }
        }

        if let avgSteadiness {
            if steadinessDown {
                observations.append("步行稳定性近期有回落，当前平均约 \(String(format: "%.1f", avgSteadiness))%。")
            } else {
                observations.append("步行稳定性整体较稳，当前平均约 \(String(format: "%.1f", avgSteadiness))%。")
            }
        }

        let guidance: [String]
        if (speedDown && asymmetryUp) || supportUp || steadinessDown {
            guidance = [
                "接下来优先观察未来 1 到 2 周速度、双足支撑时间和步行稳定性是否继续朝不利方向偏移。",
                "如果这种组合持续存在，更适合把步长、步伐不对称和双足支撑时间放在一起排查行动稳定性变化。"
            ]
        } else if !enoughSamples {
            guidance = [
                "先继续积累几天稳定的步行记录，样本足够后这里会给出更明确的行动判断。"
            ]
        } else {
            guidance = [
                "继续把步长、速度、平衡、双足支撑和稳定性放在一起读，不建议只盯单个高低点。",
                "如果几条线连续同向偏移，再回头对照恢复和心率模块会更容易读出原因。"
            ]
        }

        return MobilityTrendAIInsightModel(
            summary: summary,
            observations: Array(observations.prefix(5)),
            guidance: guidance,
            statusTitle: statusTitle,
            sourceLabel: "本地洞察"
        )
    }

    static func averageValue(for points: [TimeSeriesPointDouble]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    static func buildGenericAIInsight(
        category: TrendCategoryID,
        metrics: [TrendCategoryMetricModel],
        headerSummary: String,
        heartECGSummary: HeartECGSummaryModel? = nil,
        heartClinicalMonitorSummary: HeartClinicalMonitorSummary? = nil
    ) -> GenericTrendAIInsightModel? {
        guard category != .sleepRecovery, category != .mobilityGait, category != .reproductive else {
            return nil
        }

        let readyMetrics = metrics.filter { $0.status == .ready && !$0.points.isEmpty }
        let partialMetrics = metrics.filter { $0.status == .partial }
        let noDataMetrics = metrics.filter { $0.status == .noData }
        let primaryMetric = readyMetrics.first ?? metrics.first
        let secondaryMetrics = Array(readyMetrics.dropFirst().prefix(2))
        let primaryDirection = primaryMetric.map { insightDirection(for: $0, category: category) } ?? .insufficient

        let summary: String = {
            switch category {
            case .heartCardio:
                if !readyMetrics.isEmpty {
                    return String(localized: "当前心率已经不适合只看单个指标高低，更有参考价值的是把连续趋势、心电记录和监测事件放在一起读。")
                }
                return String(localized: "当前更适合先把基础心率样本积累起来，后续再叠加 ECG 和监测层信息一起看。")
            case .bodyMetrics:
                if readyMetrics.contains(where: { $0.title == "体重" }),
                   readyMetrics.contains(where: { $0.title == "体脂率" }) {
                    switch primaryDirection {
                    case .rising:
                        return String(localized: "最近身体成分主线在上行，当前更值得分清这是体重本身在抬升，还是体脂率也在一起推高整体结构。")
                    case .falling:
                        return String(localized: "最近身体成分主线在回落，当前更值得确认下降的是单纯体重，还是成分结构也在一起变化。")
                    case .stable, .volatile, .insufficient:
                        return String(localized: "当前更适合把体重和体脂率一起看，判断最近的体型变化到底只是体重波动，还是成分结构本身在移动。")
                    }
                }
                if !readyMetrics.isEmpty {
                    return String(localized: "身体成分已经形成初步样本，最近主线\(directionSentence(primaryDirection))，接下来更值得连续看体重、BMI 和体脂率是不是在朝同一个方向变化。")
                }
                return String(localized: "当前还缺少连续的身体成分样本，先把体重和体脂率稳定记录下来，这页才会更有判断价值。")
            case .dailyActivity:
                if readyMetrics.contains(where: { $0.title == "步行速度" }) {
                    return String(localized: "最近步速主线\(directionSentence(primaryDirection))，当前更值得把步行速度、步数和步行距离放在一起看，判断最近变化更像效率回落还是节律变慢。")
                }
                return String(localized: "当前还在等待更连续的步速样本，先继续积累几天步行记录，这里的判断才会更有参考价值。")
            case .vitalsRespiratory:
                if !readyMetrics.isEmpty {
                    return String(localized: "最近基础体征主线\(directionSentence(primaryDirection))，当前更值得把呼吸率、血氧和腕温一起读，确认是不是多条信号在同步偏移。")
                }
                return String(localized: "当前还没有足够的生命体征样本，先补齐基础记录后，这里才更容易看出体征有没有连续变化。")
            case .runningDynamics:
                if readyMetrics.contains(where: { $0.title == "跑步总时长" }),
                   readyMetrics.contains(where: { $0.title == "跑步距离" }) {
                    return String(localized: "最近跑步主线\(directionSentence(primaryDirection))，当前更值得把跑步时长、距离和频次放在一起读，判断是跑量连续抬升，还是只是偶发冲高。")
                }
                if !readyMetrics.isEmpty {
                    return String(localized: "跑步样本已经开始形成，当前适合把跑步频次、距离和输出节奏放在一起连续阅读。")
                }
                return String(localized: "当前还缺少足够的跑步记录，先把跑步样本稳定积累起来，这里的结论才更有参考价值。")
            case .cyclingStats:
                if readyMetrics.contains(where: { $0.title == "骑行总时长" }),
                   readyMetrics.contains(where: { $0.title == "骑行距离" }) {
                    return String(localized: "最近骑行主线\(directionSentence(primaryDirection))，当前更值得把骑行时长、距离和频次放在一起读，判断是骑行量连续抬升，还是只是偶发冲高。")
                }
                if !readyMetrics.isEmpty {
                    return String(localized: "骑行样本已经开始形成，当前适合把骑行频次、距离和输出节奏放在一起连续阅读。")
                }
                return String(localized: "当前还缺少足够的骑行记录，先把骑行样本稳定积累起来，这里的结论才更有参考价值。")
            case .swimmingWater:
                if readyMetrics.contains(where: { $0.title == "游泳总时长" }),
                   readyMetrics.contains(where: { $0.title == "游泳距离" }) {
                    return String(localized: "最近游泳主线\(directionSentence(primaryDirection))，当前更值得把游泳时长、距离和频次放在一起读，判断是游泳量连续累积，还是只是局部冲高。")
                }
                if !readyMetrics.isEmpty {
                    return String(localized: "游泳样本已经开始形成，当前适合把游泳频次、距离和输出节奏放在一起连续阅读。")
                }
                return String(localized: "当前还缺少足够的游泳记录，先把游泳样本稳定积累起来，这里的结论才更有参考价值。")
            case .workoutsTraining:
                if readyMetrics.contains(where: { $0.title == "训练总时长" }),
                   readyMetrics.contains(where: { $0.title == "训练次数" }) {
                    return String(localized: "最近训练主线\(directionSentence(primaryDirection))，当前更值得把训练总时长和训练次数放在一起读，判断是在稳步堆量还是只是零散出现。")
                }
                if !readyMetrics.isEmpty {
                    return String(localized: "训练节律已经有初步样本，接下来更值得观察训练量是不是能连续维持。")
                }
                return String(localized: "当前还缺少足够的训练记录，先把训练频率和时长稳定记录下来，这里的结论才更有参考价值。")
            case .environmentSenses:
                if !readyMetrics.isEmpty {
                    return String(localized: "最近环境输入主线\(directionSentence(primaryDirection))，当前更值得把日照、环境音和耳机暴露放在一起读，判断外部刺激是不是已经连续拖动日常节律。")
                }
                return String(localized: "环境感官分类已经接入，但这段时间还没有形成足够样本；先继续记录后再看趋势会更合适。")
            case .nutritionHydration:
                if readyMetrics.contains(where: { $0.title == "饮水量" }) {
                    return String(localized: "最近补水主线\(directionSentence(primaryDirection))，当前更值得把饮水量、达标率和咖啡因残留放在一起读，判断补水节奏和刺激输入是不是在同步偏移。")
                }
                if !readyMetrics.isEmpty {
                    return String(localized: "补水与刺激样本已经开始形成，当前适合把补水节奏和咖啡因残留放在一起连续阅读。")
                }
                return String(localized: "当前还缺少足够的补水与咖啡因记录，先把日常样本积累起来，这里的结论才更有参考价值。")
            case .mindfulnessMental:
                if !readyMetrics.isEmpty {
                    return String(localized: "最近心理节律主线\(directionSentence(primaryDirection))，当前更值得把正念时长和心理状态一起看，确认变化更像调节投入变化还是情绪波动本身在抬升。")
                }
                return String(localized: "当前还在等待更连续的心理状态和正念样本，先稳定记录几天，这里的判断会更容易变得可读。")
            case .symptomsIllness:
                return String(localized: "这里更适合把症状频率和病程线索放在一起读，避免只凭一次记录就判断趋势。")
            default:
                if !readyMetrics.isEmpty {
                    return String(localized: "\(category.title) 已经形成初步可读趋势，当前更值得把核心指标放在一起看连续变化，而不是只看单次高低。")
                }
                return String(localized: "当前还在等待\(category.title)的有效样本，连续记录后，这里的趋势判断会逐步变得更清晰。")
            }
        }()

        var observations: [String] = []

        if let primaryMetric {
            observations.append("\(primaryMetric.title) 目前是这个分类最值得优先阅读的主线，当前读数为 \(primaryMetric.summary)，最近走势\(directionShortText(primaryDirection))。")
        }

        if !secondaryMetrics.isEmpty {
            let compareTitles = secondaryMetrics.map(\.title).joined(separator: "、")
            switch category {
            case .bodyMetrics:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起对照，判断最近变化到底落在体重本身，还是成分比例也在同步变化。")
            case .vitalsRespiratory:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起看，判断最近是不是多条基础体征在同时偏移。")
            case .workoutsTraining:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起读，更容易看出训练量是连续堆积，还是只在局部日期冒高。")
            case .environmentSenses:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起读，更容易判断外部刺激是在同步累积还是暂时还没有形成稳定样本。")
            case .nutritionHydration:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起读，更容易判断补水节奏和刺激输入是不是在同步偏移。")
            case .mindfulnessMental:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起对照，看心理波动是否和正念投入节奏同步变化。")
            default:
                observations.append("AI 建议把 \(compareTitles) 和主指标一起对照阅读，更容易判断变化是同步还是分化。")
            }
        } else if !partialMetrics.isEmpty {
            observations.append("\(partialMetrics.prefix(2).map(\.title).joined(separator: "、")) 还在补样本阶段，当前判断需要保留一点余量。")
        }

        if !noDataMetrics.isEmpty {
            observations.append("目前 \(noDataMetrics.prefix(2).map(\.title).joined(separator: "、")) 还没有形成稳定记录，这一类判断更适合继续观察。")
        }

        if category == .heartCardio, let heartECGSummary {
            observations.append("ECG 专项当前状态为\(heartECGSummary.headline)，可以作为连续心率趋势的离散补充证据。")
        }
        if category == .heartCardio, let heartClinicalMonitorSummary {
            observations.append("监测层当前已纳入\(heartClinicalMonitorSummary.items.prefix(3).map(\.title).joined(separator: "、"))，适合补充看是否有异常事件同步出现。")
        }
        if category == .dailyActivity,
           let walkingSpeedMetric = readyMetrics.first(where: { $0.title == "步行速度" }) {
            observations.append("步行速度当前为 \(walkingSpeedMetric.summary)，更适合和步数、步行距离一起看最近的移动效率是不是在同步变化。")
        }
        if category == .bodyMetrics,
           let bodyFatMetric = readyMetrics.first(where: { $0.title == "体脂率" }) {
            observations.append("体脂率当前为 \(bodyFatMetric.summary)，这条线更适合和体重联动看，而不是单独判断。")
        }
        if category == .workoutsTraining,
           let trainingMetric = readyMetrics.first(where: { $0.title == "训练次数" }) {
            observations.append("训练次数当前为 \(trainingMetric.summary)，它更适合用来判断最近节奏是否连续，而不只是有没有运动。")
        }
        if category == .environmentSenses,
           let daylightMetric = readyMetrics.first(where: { $0.title == "日照时长" }) {
            observations.append("日照时长当前为 \(daylightMetric.summary)，更适合作为这类外部输入节律的底盘信号。")
        }
        if category == .environmentSenses,
           let headphoneDurationMetric = readyMetrics.first(where: { $0.title == "耳机暴露时长" }) {
            observations.append("耳机暴露时长当前为 \(headphoneDurationMetric.summary)，更适合和耳机暴露量一起看听觉刺激是否连续堆积。")
        }
        if category == .environmentSenses,
           let headphoneLevelMetric = readyMetrics.first(where: { $0.title == "耳机暴露量" }) {
            observations.append("耳机暴露量当前为 \(headphoneLevelMetric.summary)，可以帮助区分听觉刺激更像音量偏高，还是主要由时长拉长带来。")
        }
        if category == .nutritionHydration,
           let hydrationMetric = readyMetrics.first(where: { $0.title == "饮水量" }) {
            observations.append("饮水量当前为 \(hydrationMetric.summary)，更适合和达标率、咖啡因残留一起看补水节奏是否连续。")
        }
        if category == .mindfulnessMental,
           let stateMetric = readyMetrics.first(where: { $0.title == "心理状态" }) {
            observations.append("心理状态当前为 \(stateMetric.summary)，建议和正念时长一起对照，而不是只看单次主观打分。")
        }

        let guidance: [String] = {
            switch category {
            case .runningDynamics:
                return [
                    "优先把跑步时长、跑步距离和跑步频次按周连起来看，判断跑量是不是稳定累积。",
                    "如果配速开始连续变化，再结合顶部洞悉更容易看出这是能力提升还是训练结构变化。"
                ]
            case .cyclingStats:
                return [
                    "优先把骑行时长、骑行距离和骑行频次按周连起来看，判断骑行量是不是稳定累积。",
                    "如果速度开始连续变化，再结合顶部洞悉更容易看出这是能力提升还是训练结构变化。"
                ]
            case .swimmingWater:
                return [
                    "优先把游泳时长、游泳距离和游泳频次按周连起来看，判断游泳量是不是稳定累积。",
                    "如果速度开始连续变化，再结合顶部洞悉更容易看出这是能力提升还是训练结构变化。"
                ]
            case .bodyMetrics:
                return [
                    "优先把体重、BMI 和体脂率连续放在一起看，判断最近的变化更像体重波动还是成分迁移。",
                    "瘦体重已经纳入成分趋势；身体水分没有可靠数据来源，因此不会用占位值参与 AI 判断。"
                ]
            case .vitalsRespiratory:
                return [
                    "优先观察呼吸率、血氧和腕温是不是一起偏离基线，不建议只盯单个异常点。",
                    "如果这种偏移连续出现，再回来看顶部洞悉会比单天阅读更有意义。"
                ]
            case .workoutsTraining:
                return [
                    "优先把训练时长和训练次数按周连起来看，判断训练节奏有没有稳定维持。",
                    "如果后续主训练类型连续变化，再结合上方 AI 洞悉更容易看出训练结构迁移。"
                ]
            case .environmentSenses:
                return [
                    "优先把日照和声音暴露连起来看，判断外部输入是不是已经形成持续刺激环境。",
                    "如果这些输入连续偏高，再回头对照睡眠和恢复页会更有意义。"
                ]
            case .nutritionHydration:
                return [
                    "优先把饮水量、饮水达标率和咖啡因残留按周连起来看，判断补水节奏是不是稳定形成。",
                    "如果补水和刺激输入连续同向偏移，再结合顶部洞悉更容易看出日常节律是不是在被拖动。"
                ]
            case .mindfulnessMental:
                return [
                    "优先把心理状态和正念时长一起看，判断最近波动更像情绪起伏还是练习节奏松掉。",
                    "如果连续几天都出现同方向变化，AI 对心理节律的判断会更稳。"
                ]
            default:
                break
            }
            if readyMetrics.count >= 2 {
                return [
                    "优先把顶部 AI 洞悉和下方核心趋势图对照着看，判断这些变化是不是连续发生。",
                    "如果后续还有更多样本进来，AI 会更容易区分短期波动和真正的趋势偏移。"
                ]
            }
            return [
                "先继续记录几天，让 AI 有足够样本形成更稳定的观察结论。",
                "下次回来看时，重点对照主指标是否开始出现连续变化。"
            ]
        }()

        return GenericTrendAIInsightModel(
            summary: summary.isEmpty ? headerSummary : summary,
            observations: Array(observations.filter { !$0.isEmpty }.prefix(4)),
            guidance: Array(guidance.filter { !$0.isEmpty }.prefix(2))
        )
    }

    static func insightDirection(for metric: TrendCategoryMetricModel, category: TrendCategoryID) -> TrendChartDirection {
        let points = metric.points
        guard points.count >= 2 else { return .insufficient }
        guard let delta = trendDelta(for: points) else { return .insufficient }

        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        let baseline = max(abs(values.first ?? 0), 1)
        let relativeDelta = abs(delta) / baseline

        let relativeThreshold = insightRelativeThreshold(for: metric, category: category)
        let absoluteThreshold = insightAbsoluteThreshold(for: metric, category: category)
        let volatilityRatio = insightVolatilityRatio(for: metric, category: category)

        if range > absoluteThreshold, abs(delta) < range * volatilityRatio, points.count >= 4 {
            return .volatile
        }
        if abs(delta) <= absoluteThreshold || relativeDelta < relativeThreshold {
            return .stable
        }
        if delta > 0 {
            return .rising
        }
        if delta < 0 {
            return .falling
        }
        return .stable
    }

    static func insightRelativeThreshold(for metric: TrendCategoryMetricModel, category: TrendCategoryID) -> Double {
        switch category {
        case .bodyMetrics:
            return metric.unit == "%" ? 0.03 : 0.02
        case .dailyActivity:
            return 0.08
        case .vitalsRespiratory:
            return metric.unit == "%" ? 0.01 : 0.04
        case .workoutsTraining:
            return 0.12
        case .environmentSenses:
            return 0.08
        case .mindfulnessMental:
            return 0.10
        default:
            return 0.05
        }
    }

    static func insightAbsoluteThreshold(for metric: TrendCategoryMetricModel, category: TrendCategoryID) -> Double {
        switch category {
        case .bodyMetrics:
            if metric.title.contains("体重") { return 0.6 }
            if metric.title.contains("BMI") { return 0.25 }
            if metric.title.contains("体脂") { return 1.2 }
            return 0.5
        case .dailyActivity:
            if metric.title.contains("步行速度") { return 0.08 }
            if metric.title.contains("步数") { return 800 }
            if metric.title.contains("距离") { return 0.8 }
            return 1
        case .vitalsRespiratory:
            if metric.title.contains("呼吸") { return 1.2 }
            if metric.title.contains("血氧") { return 1.0 }
            if metric.title.contains("腕温") { return 0.15 }
            return 0.5
        case .workoutsTraining:
            if metric.title.contains("时长") { return 20 }
            if metric.title.contains("次数") { return 1 }
            return 1
        case .environmentSenses:
            if metric.title.contains("日照") { return 20 }
            if metric.title.contains("暴露") { return 3 }
            return 1
        case .mindfulnessMental:
            if metric.title.contains("正念") { return 8 }
            if metric.title.contains("心理状态") { return 0.6 }
            return 1
        default:
            return 1
        }
    }

    static func insightVolatilityRatio(for metric: TrendCategoryMetricModel, category: TrendCategoryID) -> Double {
        switch category {
        case .dailyActivity, .workoutsTraining:
            return 0.22
        case .environmentSenses:
            return 0.2
        case .mindfulnessMental:
            return 0.18
        default:
            return 0.15
        }
    }

    static func directionSentence(_ direction: TrendChartDirection) -> String {
        switch direction {
        case .rising:
            return String(localized: "在上行")
        case .falling:
            return String(localized: "在回落")
        case .stable:
            return String(localized: "相对平稳")
        case .volatile:
            return String(localized: "波动偏大")
        case .insufficient:
            return String(localized: "还不足以判断方向")
        }
    }

    static func directionShortText(_ direction: TrendChartDirection) -> String {
        switch direction {
        case .rising:
            return String(localized: "偏上行")
        case .falling:
            return String(localized: "偏回落")
        case .stable:
            return String(localized: "相对平稳")
        case .volatile:
            return String(localized: "波动偏大")
        case .insufficient:
            return String(localized: "样本不足")
        }
    }

    static func trendDelta(for points: [TimeSeriesPointDouble]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value else { return nil }
        return last - first
    }

}
