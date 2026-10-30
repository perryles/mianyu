import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// FitnessCalendarViewModel 训练表现/恢复/下一步建议子模块。
/// 从 FitnessCalendarViewModel+Presentation.swift 再拆分：训练回顾、表现追踪/回顾、恢复管理、负荷/恢复评分。

@MainActor
extension FitnessCalendarViewModel {

    func makeWorkoutReviewModel() -> FitnessWorkoutReviewModel {
        let upperBound = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
        guard let summary = workoutSummaries.values
            .filter({ $0.date < upperBound && $0.workoutCount > 0 })
            .max(by: { $0.date < $1.date }) else {
            return FitnessWorkoutReviewModel(
                date: nil,
                workoutTitle: "最近训练",
                dateText: "当前范围暂无记录",
                badgeText: "等待训练",
                headline: "还没有可复盘的单次训练",
                detailText: "在 Apple Watch 或健康 App 中记录训练后，这里会优先展示时长、消耗、距离、配速和恢复线索。",
                intensityText: "暂无强度",
                recoveryText: "恢复待评估",
                accentHex: "58CC6A",
                metrics: []
            )
        }

        let day = buildDetachedDay(for: store.record(for: summary.date))
        let distance = summary.totalDistanceKilometers
        let pace = distance.flatMap { value in
            value > 0 ? Double(summary.totalMinutes) / value : nil
        }
        let effortText = day.manualWorkoutEffort?.title ?? intensityTier(for: day) + "强度"
        let load = trainingLoadScore(for: day)
        let recovery = recoveryScore(for: day)
        let accentHex = recovery >= 70 ? "58CC6A" : (recovery >= 50 ? "F4B46B" : "F06A7B")
        let workoutTitle = summary.dominantWorkoutTitle ?? "综合训练"

        let metrics = [
            FitnessWorkoutReviewMetric(
                id: "duration",
                title: "训练时长",
                valueText: "\(summary.totalMinutes)",
                unitText: "分钟",
                symbol: "timer",
                tintHex: "58CC6A"
            ),
            FitnessWorkoutReviewMetric(
                id: "energy",
                title: "运动消耗",
                valueText: summary.totalEnergyKilocalories.map(String.init) ?? "--",
                unitText: summary.totalEnergyKilocalories == nil ? "" : "kcal",
                symbol: "flame.fill",
                tintHex: "F4B46B"
            ),
            FitnessWorkoutReviewMetric(
                id: "distance",
                title: "距离",
                valueText: distance.map { String(format: "%.2f", $0) } ?? "--",
                unitText: distance == nil ? "" : "km",
                symbol: "location.fill",
                tintHex: "73C8E8"
            ),
            FitnessWorkoutReviewMetric(
                id: "pace",
                title: "平均配速",
                valueText: pace.map(Self.paceText) ?? "--",
                unitText: pace == nil ? "" : "/km",
                symbol: "speedometer",
                tintHex: "2AA7A1"
            ),
            FitnessWorkoutReviewMetric(
                id: "hrv",
                title: "当日 HRV",
                valueText: day.hrvValue.map { String(Int($0.rounded())) } ?? "--",
                unitText: day.hrvValue == nil ? "" : "ms",
                symbol: "waveform.path.ecg",
                tintHex: "DE5B84"
            ),
            FitnessWorkoutReviewMetric(
                id: "count",
                title: "当日训练",
                valueText: "\(summary.workoutCount)",
                unitText: "次",
                symbol: "figure.run",
                tintHex: "7A8CF0"
            )
        ]

        let detailText: String
        if let distance, distance > 0, let pace {
            detailText = "本次记录覆盖 \(String(format: "%.2f", distance)) 公里，平均配速 \(Self.paceText(pace))/km。结合训练负荷和恢复分，更适合判断这次输出是否被身体接住。"
        } else if let distance {
            detailText = "设备为这次训练记录了 \(String(format: "%.2f", distance)) 公里；距离为零时不计算配速，也不使用估算值补位。"
        } else {
            detailText = "这次记录已同步训练时长。能量和距离只有在设备写入对应数据时展示，不使用估算值补位。"
        }

        return FitnessWorkoutReviewModel(
            date: summary.date,
            workoutTitle: workoutTitle,
            dateText: ChineseDateText.writtenMonthDay(summary.date),
            badgeText: summary.workoutCount > 1 ? "当日 \(summary.workoutCount) 次" : "最近一次",
            headline: "\(summary.totalMinutes) 分钟 · \(effortText)",
            detailText: detailText,
            intensityText: "负荷 \(load) 分",
            recoveryText: "恢复 \(recovery) 分",
            accentHex: accentHex,
            metrics: metrics
        )
    }

    func makeCycleTrainingRhythmPlan() -> CycleTrainingRhythmPlan? {
        let periodSummary = PeriodStore.shared.summary(days: 90)
        let phase = CyclePhaseKind(phaseRawValue: periodSummary.current?.phase)
        guard phase != .unknown else { return nil }

        let latestLog = periodSummary.dayLogs?
            .sorted(by: { ($0.date ?? "") > ($1.date ?? "") })
            .first
        let todayRecord = store.record(for: todayDate)
        let recentAvgHrv = pointsMap(hrvTrend)
            .values
            .filter { $0 > 0 }
        let recentHrvAverage = HealthBaselineStrategy.usableValue(for: Array(recentAvgHrv), metric: .hrvSDNN)
        let latestStress = AppGroupManager.shared.getLatestStress().map { Int($0.rounded()) }

        return cycleRhythmEngine.makePlan(
            input: .init(
                phase: phase,
                cycleDay: periodSummary.current?.dayIndex,
                cycleLength: periodSummary.predictions?.cycleLength,
                flowLevel: latestLog?.flowLevel,
                painLevel: latestLog?.painLevel,
                moodLevel: latestLog?.moodLevel,
                stressScore: latestStress,
                sleepMinutes: AppGroupManager.shared.getSleepDurationMinutes(),
                sleepScore: AppGroupManager.shared.getSleepScore(),
                sleepGoalMinutes: SleepGoalResolver.goalMinutes(),
                hrv: selectedCalendarDay?.hrvValue,
                recentAvgHrv: recentHrvAverage,
                workoutMinutes: todayRecord.manualWorkoutMinutes > 0 ? todayRecord.manualWorkoutMinutes : selectedCalendarDay?.displayWorkoutMinutes,
                workoutEffort: todayRecord.manualWorkoutEffort,
                vo2Max: AppGroupManager.shared.getVO2MaxValue()
            )
        )
    }

    func makeRecoveryManagementModel(days: [HabitFitnessCalendarDay]) -> FitnessRecoveryManagementModel {
        let selected = selectedCalendarDay ?? visibleDays(from: days).last
        let recent = recentDays(endingAt: selected?.date ?? selectedDate, from: days, count: 7)
        let dailyScores = recent.map(recoveryScore(for:))
        let averageScore = dailyScores.isEmpty ? 0 : Int((Double(dailyScores.reduce(0, +)) / Double(dailyScores.count)).rounded())
        let score = selected.map(recoveryScore(for:)) ?? averageScore
        let statusText: String
        let detailText: String
        let accentHex: String

        switch score {
        case ..<45:
            statusText = "优先恢复"
            detailText = "这几天更像是训练刺激已经堆上来了，后面更值得优先补睡眠、补水和轻恢复，而不是继续硬顶。"
            accentHex = "F06A7B"
        case ..<70:
            statusText = "需要收一收"
            detailText = "恢复还在接，但没有完全跟上训练负荷。把今天当成过渡日，会比继续加量更稳。"
            accentHex = "F4B46B"
        default:
            statusText = "恢复在线"
            detailText = "最近训练和恢复比较平衡，可以继续推进主训练，但仍然要守住睡眠和恢复习惯。"
            accentHex = "58CC6A"
        }

        let focusItems = [
            FitnessRecoveryFocusItem(
                id: "hrv",
                title: "HRV",
                detail: selected?.hrvValue.map { "\((Int($0.rounded()))) ms" } ?? "暂无样本",
                tintHex: "DE5B84",
                symbol: "waveform.path.ecg"
            ),
            FitnessRecoveryFocusItem(
                id: "sleep",
                title: "恢复动作",
                detail: selected?.checkinMode == .recovery ? "今天已安排轻恢复" : "建议安排拉伸/散步/早点休息",
                tintHex: "2AA7A1",
                symbol: "leaf.fill"
            ),
            FitnessRecoveryFocusItem(
                id: "load",
                title: "昨日负荷",
                detail: recent.dropLast().last.map { "\(trainingLoadScore(for: $0)) 分" } ?? "暂无样本",
                tintHex: "F4B46B",
                symbol: "flame.fill"
            )
        ]

        return FitnessRecoveryManagementModel(
            title: "恢复管理",
            scoreText: "\(score) 分",
            statusText: statusText,
            detailText: detailText,
            accentHex: accentHex,
            focusItems: focusItems
        )
    }

    func makeLoadRecoveryLinkModel(days: [HabitFitnessCalendarDay]) -> FitnessLoadRecoveryLinkModel {
        let recent = recentDays(endingAt: selectedDate, from: days, count: 5)
        let linkedDays = recent.map { day in
            let load = trainingLoadScore(for: day)
            let recovery = recoveryScore(for: day)
            let stateText: String
            let tintHex: String

            if load >= 70 && recovery < 45 {
                stateText = "负荷压住恢复"
                tintHex = "F06A7B"
            } else if load >= 50 && recovery >= 60 {
                stateText = "刺激吸收不错"
                tintHex = "58CC6A"
            } else if load < 35 && recovery >= 65 {
                stateText = "适合推进"
                tintHex = "73C8E8"
            } else {
                stateText = "处于过渡"
                tintHex = "F4B46B"
            }

            return FitnessLoadRecoveryDayModel(
                date: day.date,
                label: weekdayShortString(day.date),
                loadScore: load,
                recoveryScore: recovery,
                stateText: stateText,
                tintHex: tintHex,
                isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate)
            )
        }

        let latest = linkedDays.last
        let headline: String
        let detailText: String
        let actionText: String
        let accentHex = latest?.tintHex ?? "73C8E8"

        switch latest?.stateText {
        case "负荷压住恢复":
            headline = "最近训练刺激偏多"
            detailText = "你的负荷已经顶上去，但恢复还没完全接住。今天更适合恢复、拉伸或控制强度。"
            actionText = "下一练先别加量"
        case "刺激吸收不错":
            headline = "负荷和恢复比较同步"
            detailText = "这几天的训练刺激基本被吸收了，说明当前节奏比较适合你。"
            actionText = "可以继续按当前节奏推进"
        case "适合推进":
            headline = "恢复窗口已经打开"
            detailText = "最近负荷不算高，恢复状态也还不错，更适合把高质量训练接回来。"
            actionText = "今天可以安排主训练"
        default:
            headline = "节律还在调整"
            detailText = "训练与恢复没有明显失衡，但也还没到特别适合冲量的时候，先保持稳定更划算。"
            actionText = "先把节奏守稳"
        }

        return FitnessLoadRecoveryLinkModel(
            title: "负荷与恢复",
            headline: headline,
            detailText: detailText,
            actionText: actionText,
            accentHex: accentHex,
            days: linkedDays
        )
    }

    func makePerformanceTrackModel(days: [HabitFitnessCalendarDay]) -> FitnessPerformanceTrackModel {
        let recent14 = recentDays(endingAt: selectedDate, from: days, count: 14)
        let latest7 = Array(recent14.suffix(7))
        let previous7 = Array(recent14.prefix(max(0, recent14.count - latest7.count)))
        let recentRange = makePerformanceRangeModel(range: .recent7, currentDays: latest7, previousDays: previous7)
        let visible = visibleDays(from: days)
        let periodStart = calendar.date(byAdding: calendarScope == .week ? .weekOfYear : .month, value: -1, to: selectedDate) ?? selectedDate
        let previousPeriod = recentDays(endingAt: periodStart, from: days, count: max(visible.count, calendarScope == .week ? 7 : 30))
        let periodRange = makePerformanceRangeModel(range: .currentPeriod, currentDays: visible, previousDays: previousPeriod)
        let primary = recentRange

        return FitnessPerformanceTrackModel(
            title: "体能追踪",
            scoreText: primary.scoreText,
            changeText: primary.changeText,
            statusText: primary.statusText,
            detailText: primary.detailText,
            accentHex: primary.accentHex,
            ranges: [recentRange, periodRange]
        )
    }

    func makePerformanceReviewModel(days: [HabitFitnessCalendarDay]) -> FitnessPerformanceReviewModel {
        let visible = visibleDays(from: days)
        let trainingDays = visible.filter { $0.displayWorkoutMinutes > 0 || $0.checkinMode == .workout || $0.isInferredWorkoutOnly }
        let recoveryDays = visible.filter { $0.checkinMode == .recovery }.count
        let totalMinutes = visible.reduce(0) { $0 + $1.displayWorkoutMinutes }
        let averageRecovery = trainingDays.isEmpty ? 0 : Int((Double(trainingDays.map(recoveryScore(for:)).reduce(0, +)) / Double(trainingDays.count)).rounded())
        let bestDay = trainingDays.max { performanceContribution(for: $0) < performanceContribution(for: $1) }

        let badgeText: String
        let summaryText: String
        let accentHex: String

        if trainingDays.isEmpty {
            badgeText = "等待起步"
            summaryText = "这一阶段还没有形成明确的训练样本，先把第一周的节奏建立起来，后面复盘就会更有东西。"
            accentHex = "73C8E8"
        } else if averageRecovery < 45 && totalMinutes >= targetMinutes {
            badgeText = "训练够了，恢复偏欠"
            summaryText = "这一阶段不缺训练刺激，问题更像是恢复跟得不够。后续如果想继续提升，先把恢复质量拉上来。"
            accentHex = "F06A7B"
        } else if totalMinutes >= targetMinutes && trainingDays.count >= targetTrainingDays {
            badgeText = "阶段表现在线"
            summaryText = "这一阶段训练频率和总量都比较完整，而且恢复没有明显掉队，整体像一段质量不错的推进期。"
            accentHex = "58CC6A"
        } else {
            badgeText = "还在搭节奏"
            summaryText = "训练已经开始积累，但这一阶段更像在铺底。继续把频率和恢复守住，表现会更快稳定下来。"
            accentHex = "F4B46B"
        }

        let items = [
            FitnessPerformanceReviewItem(
                id: "days",
                title: "训练完成度",
                valueText: "\(trainingDays.count)/\(targetTrainingDays) 天",
                detailText: "这一阶段形成的明确训练日",
                tintHex: "58CC6A"
            ),
            FitnessPerformanceReviewItem(
                id: "minutes",
                title: "总训练量",
                valueText: "\(totalMinutes) 分钟",
                detailText: targetMinutes > 0 ? "目标参考 \(targetMinutes) 分钟" : "累计训练分钟",
                tintHex: "73C8E8"
            ),
            FitnessPerformanceReviewItem(
                id: "recovery",
                title: "恢复吸收",
                valueText: averageRecovery > 0 ? "\(averageRecovery) 分" : "--",
                detailText: "训练日后的平均恢复状态",
                tintHex: "2AA7A1"
            ),
            FitnessPerformanceReviewItem(
                id: "best",
                title: "最佳表现日",
                valueText: bestDay.map { ChineseDateText.writtenMonthDay($0.date) } ?? "--",
                detailText: bestDay.map { "\($0.displayWorkoutMinutes) 分钟 · \(recoveryScore(for: $0)) 分恢复" } ?? "等待样本",
                tintHex: "F4B46B"
            ),
            FitnessPerformanceReviewItem(
                id: "recoveryDays",
                title: "恢复安排",
                valueText: "\(recoveryDays) 天",
                detailText: "主动安排的轻恢复日",
                tintHex: "DE5B84"
            )
        ]

        return FitnessPerformanceReviewModel(
            title: "阶段复盘",
            badgeText: badgeText,
            summaryText: summaryText,
            accentHex: accentHex,
            items: items,
            bestDay: bestDay
        )
    }

    func makeNextStepModel(days: [HabitFitnessCalendarDay]) -> FitnessNextStepModel {
        let today = todayCalendarDay ?? buildDetachedDay(for: store.record(for: todayDate))
        let recovery = recoveryScore(for: today)
        let load = trainingLoadScore(for: today)
        let weeklyDays = weeklyTrainingDays(referenceDate: todayDate, days: days)
        let cyclePlan = makeCycleTrainingRhythmPlan()
        let phaseChip = cyclePlan?.phaseLabel

        let headline: String
        let detailText: String
        let primaryActionTitle: String
        let primaryMode: FitnessCheckinMode?
        let accentHex: String
        let symbol: String

        if today.checkinMode == nil && today.isInferredWorkoutOnly {
            headline = "先把系统识别到的训练补完整"
            detailText = "今天已经有训练分钟或活动消耗了，补上模式、强度和一句备注，后面的连续成就与阶段复盘会更准。"
            primaryActionTitle = "补充今天记录"
            primaryMode = nil
            accentHex = "F4B46B"
            symbol = "square.and.pencil"
        } else if today.checkinMode == nil {
            if recovery >= 70 && load < 35 && weeklyDays < 4 {
                headline = "今天适合安排一练"
                detailText = "恢复窗口还不错，而且本周训练日还没满。可以先做一段中低强度训练，再根据体感决定是否加量。"
                primaryActionTitle = "标记完成训练"
                primaryMode = .workout
                accentHex = FitnessCheckinMode.workout.tintHex
                symbol = FitnessCheckinMode.workout.symbol
            } else if recovery < 50 || load >= 70 {
                headline = "今天更适合轻恢复"
                detailText = "负荷和恢复没有完全接住，先把拉伸、散步或早点休息安排上，会比继续硬冲更稳。"
                primaryActionTitle = "标记轻恢复"
                primaryMode = .recovery
                accentHex = FitnessCheckinMode.recovery.tintHex
                symbol = FitnessCheckinMode.recovery.symbol
            } else {
                headline = "先选一个今天的训练状态"
                detailText = "当前没有明显失衡。你可以根据体感选择训练或恢复，至少先把今天的节奏留住。"
                primaryActionTitle = "补充今天记录"
                primaryMode = nil
                accentHex = "73C8E8"
                symbol = "target"
            }
        } else if today.checkinMode == .workout {
            if today.manualWorkoutMinutes == 0 && today.exerciseMinutes == 0 {
                headline = "训练已打卡，建议补上时长"
                detailText = "今天的训练状态已经确认了，再补训练分钟和强度，阶段复盘会更像真正的训练日志。"
                primaryActionTitle = "补充训练详情"
                primaryMode = nil
                accentHex = FitnessCheckinMode.workout.tintHex
                symbol = "timer"
            } else if recovery < 50 {
                headline = "训练完成后，把恢复接上"
                detailText = "今天已经有训练刺激，恢复分偏紧。接下来更值得补水、拉伸和早点收尾。"
                primaryActionTitle = "查看今天详情"
                primaryMode = nil
                accentHex = "F06A7B"
                symbol = "heart.text.square.fill"
            } else {
                headline = "今天训练已经成立"
                detailText = "训练和恢复没有明显打架。保留一句体感备注，后面回看这一天会更有参考价值。"
                primaryActionTitle = "补一句备注"
                primaryMode = nil
                accentHex = FitnessCheckinMode.workout.tintHex
                symbol = "checkmark.seal.fill"
            }
        } else if today.checkinMode == .recovery {
            headline = "今天按恢复日执行"
            detailText = "恢复日已经记上了。后续更适合低负荷活动、拉伸和睡眠，不需要为了连续感硬补训练。"
            primaryActionTitle = "查看恢复记录"
            primaryMode = nil
            accentHex = FitnessCheckinMode.recovery.tintHex
            symbol = FitnessCheckinMode.recovery.symbol
        } else {
            headline = "休息日也算节奏"
            detailText = "今天已经标记为休息日。让身体把前面的训练吸收掉，下一次训练会更容易接住。"
            primaryActionTitle = "查看休息记录"
            primaryMode = nil
            accentHex = FitnessCheckinMode.rest.tintHex
            symbol = FitnessCheckinMode.rest.symbol
        }

        var chips = [
            "本周 \(weeklyDays)/4 天",
            "恢复 \(recovery) 分",
            "负荷 \(load) 分"
        ]
        if let phaseChip {
            chips.append(phaseChip)
        }

        return FitnessNextStepModel(
            title: "下一步建议",
            headline: cyclePlan?.todayTrainingMode.title ?? headline,
            detailText: cyclePlan?.todayReason ?? detailText,
            primaryActionTitle: primaryActionTitle,
            primaryMode: primaryMode,
            secondaryActionTitle: "打开今天详情",
            accentHex: cyclePlan == nil ? accentHex : "C47C74",
            symbol: cyclePlan == nil ? symbol : "circle.hexagongrid.circle.fill",
            chips: chips
        )
    }

    func makePerformanceRangeModel(
        range: FitnessPerformanceTrackRange,
        currentDays: [HabitFitnessCalendarDay],
        previousDays: [HabitFitnessCalendarDay]
    ) -> FitnessPerformanceTrackRangeModel {
        let currentScore = performanceScore(for: currentDays)
        let previousScore = performanceScore(for: previousDays)
        let delta = currentScore - previousScore
        let changePrefix = delta > 0 ? "+" : ""
        let changeText = previousScore == 0 ? "刚开始建立趋势" : "\(changePrefix)\(delta) 分"

        let statusText: String
        let detailText: String
        let accentHex: String

        switch delta {
        case let value where value >= 8:
            statusText = "提升明显"
            detailText = "\(range.title) 的训练频率、分钟数和恢复吸收都比前一段更好，体能走势在向上。"
            accentHex = "58CC6A"
        case let value where value >= 1:
            statusText = "稳步抬升"
            detailText = "训练量和恢复质量正在慢慢接起来，这种温和抬升通常更可持续。"
            accentHex = "2AA7A1"
        case let value where value <= -8:
            statusText = "进入回撤"
            detailText = "训练输出或恢复吸收比前一段明显回落，值得看看是不是累积疲劳或节奏断档。"
            accentHex = "F06A7B"
        case let value where value < 0:
            statusText = "略有回落"
            detailText = "表现没有崩，但训练质量或恢复吸收稍微弱了一点，先把节奏接稳。"
            accentHex = "F4B46B"
        default:
            statusText = currentScore == 0 ? "等待样本" : "基本持平"
            detailText = currentScore == 0
                ? "还没有足够训练样本形成趋势。"
                : "体能走势整体平稳，继续记录后趋势会越来越清晰。"
            accentHex = "73C8E8"
        }

        return FitnessPerformanceTrackRangeModel(
            range: range,
            scoreText: currentScore > 0 ? "\(currentScore) 分" : "--",
            changeText: changeText,
            statusText: statusText,
            detailText: detailText,
            accentHex: accentHex
        )
    }

    func trainingLoadScore(for day: HabitFitnessCalendarDay) -> Int {
        let minutesComponent = min(45, day.displayWorkoutMinutes)
        let energyComponent = min(35, day.activeEnergy / 12)
        let inferredComponent = day.isInferredWorkoutOnly ? 8 : 0
        let effortComponent: Int
        switch day.manualWorkoutEffort {
        case .light:
            effortComponent = 8
        case .moderate:
            effortComponent = 14
        case .hard:
            effortComponent = 22
        case nil:
            effortComponent = day.displayWorkoutMinutes >= 45 ? 10 : 0
        }
        return min(100, minutesComponent + energyComponent + effortComponent + inferredComponent)
    }

    func recoveryScore(for day: HabitFitnessCalendarDay) -> Int {
        let hrvComponent: Int
        if let hrv = day.hrvValue {
            hrvComponent = min(40, max(0, Int(((hrv - 18) / 0.9).rounded())))
        } else {
            hrvComponent = day.checkinMode == .recovery ? 24 : 18
        }

        let modeComponent: Int
        switch day.checkinMode {
        case .recovery:
            modeComponent = 28
        case .rest:
            modeComponent = 24
        case .workout:
            modeComponent = 8
        case nil:
            modeComponent = 12
        }

        let standComponent = min(12, max(0, day.standHours) * 2)
        let energyPenalty = min(22, day.activeEnergy / 30)
        let minutePenalty = min(18, day.displayWorkoutMinutes / 6)

        return max(5, min(100, hrvComponent + modeComponent + standComponent - energyPenalty - minutePenalty + 22))
    }

    func performanceContribution(for day: HabitFitnessCalendarDay) -> Int {
        let load = trainingLoadScore(for: day)
        let recovery = recoveryScore(for: day)
        let synergy = day.displayWorkoutMinutes > 0 ? max(0, min(20, (recovery - 45) / 2)) : 0
        return max(0, min(100, Int((Double(load) * 0.68).rounded()) + synergy))
    }

    func performanceScore(for days: [HabitFitnessCalendarDay]) -> Int {
        guard !days.isEmpty else { return 0 }
        let trainingCount = days.filter { $0.displayWorkoutMinutes > 0 || $0.checkinMode == .workout || $0.isInferredWorkoutOnly }.count
        let trainingContribution = days.reduce(0) { $0 + performanceContribution(for: $1) }
        let recoveryContribution = days.reduce(0) { $0 + recoveryScore(for: $1) }
        let blended = Double(trainingContribution) * 0.7 + Double(recoveryContribution) * 0.3
        let normalized = blended / Double(max(days.count, 1))
        return max(0, min(100, Int(normalized.rounded()) + min(10, trainingCount * 2)))
    }

}
