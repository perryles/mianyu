import SwiftUI

/// HabitViewModel 身体指标域 子模块。
/// 从原 HabitViewModel.swift 拆出，对外接口不变。

@MainActor
extension HabitViewModel {

    func makeHeartRateHeroCard() -> HabitBodyHeroCardModel {
        let hasDenseSeries = heartRateSeries.count >= 6
        let linePoints: [HabitTrendPoint]
        let detailText: String
        let statusText: String
        let avgValue: Int
        let maxValue: Int
        let minValue: Int
        let startLabel: String
        let endLabel: String

        if hasDenseSeries {
            linePoints = heartRateSeries.map { HabitTrendPoint(date: $0.date, value: Double($0.value)) }
            let values = heartRateSeries.map(\.value)
            avgValue = Int((Double(values.reduce(0, +)) / Double(max(values.count, 1))).rounded())
            maxValue = values.max() ?? 0
            minValue = values.min() ?? 0
            detailText = "日内心率变化"
            statusText = heartRateStatusText(average: avgValue)
            startLabel = shortTimeString(heartRateSeries.first?.date)
            endLabel = shortTimeString(heartRateSeries.last?.date)
        } else {
            let filtered = heartRateDailyTrend.filter { $0.value > 0 }
            linePoints = filtered.map { HabitTrendPoint(date: $0.date, value: $0.value) }
            let values = filtered.map { Int($0.value.rounded()) }
            avgValue = values.isEmpty ? 0 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
            maxValue = values.max() ?? 0
            minValue = values.min() ?? 0
            detailText = filtered.isEmpty ? "等待健康 App 同步心率记录" : "近 7 天平均心率趋势"
            statusText = filtered.isEmpty ? "暂无" : "7日趋势"
            startLabel = monthDayString(filtered.first?.date)
            endLabel = monthDayString(filtered.last?.date)
        }

        let summary = trendSummary(
            for: .restingHeartRate,
            points: linePoints,
            neutralText: hasDenseSeries ? "日内波动待观察" : "近一周心率待观察"
        )
        let averageValue = linePoints.isEmpty ? nil : Double(avgValue)
        let highlightValue = linePoints.last?.value

        return HabitBodyHeroCardModel(
            title: "心率变化",
            statusText: statusText,
            detailText: detailText,
            averageText: avgValue > 0 ? "\(avgValue)" : "--",
            maxText: maxValue > 0 ? "\(maxValue)" : "--",
            minText: minValue > 0 ? "\(minValue)" : "--",
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageValue,
            highlightValue: highlightValue,
            trendPoints: linePoints,
            startLabel: startLabel,
            endLabel: endLabel,
            usesFallbackTrend: !hasDenseSeries,
            isEmpty: linePoints.isEmpty
        )
    }

    func makeBasalEnergyCard() -> HabitBodyMetricCardModel {
        let currentValue = basalEnergy
        let hasTrend = basalEnergyTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(basalEnergyTrend)
        let summary = trendSummary(for: .basal, points: trendPoints, neutralText: "本周底盘消耗平稳")
        return HabitBodyMetricCardModel(
            kind: .basal,
            title: "基础代谢",
            valueText: currentValue > 0 ? "\(currentValue)" : "暂无",
            unitText: currentValue > 0 ? "kcal" : "",
            goalText: "静息消耗",
            subtitleText: currentValue > 0 ? "今日基础代谢" : (hasTrend ? "所选日暂无" : "等待同步"),
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "flame",
            tintHex: "8FB8A9",
            trendPoints: trendPoints,
            isEmpty: currentValue <= 0 && basalEnergyTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeActiveEnergyCard() -> HabitBodyMetricCardModel {
        let goal = AppGroupManager.shared.getActiveEnergyGoal() ?? 500
        let hasTrend = activeEnergyTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(activeEnergyTrend)
        let summary = trendSummary(for: .active, points: trendPoints, neutralText: "本周活动负荷持平")
        return HabitBodyMetricCardModel(
            kind: .active,
            title: "活动消耗",
            valueText: activeEnergy > 0 ? "\(activeEnergy)" : "暂无",
            unitText: activeEnergy > 0 ? "kcal" : "",
            goalText: activeEnergy > 0 ? "\(activeEnergy) / \(goal) kcal" : "目标 \(goal) kcal",
            subtitleText: activeEnergy > 0 ? "主动能量" : (hasTrend ? "所选日暂无" : "等待同步"),
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "flame.fill",
            tintHex: "F06A7B",
            trendPoints: trendPoints,
            isEmpty: activeEnergy <= 0 && activeEnergyTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeStandHoursCard() -> HabitBodyMetricCardModel {
        let goal = AppGroupManager.shared.getStandHoursGoal() ?? 12
        let hasTrend = standHoursTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(standHoursTrend)
        let summary = trendSummary(for: .stand, points: trendPoints, neutralText: "本周站立节律平稳")
        return HabitBodyMetricCardModel(
            kind: .stand,
            title: "站立时间",
            valueText: standHours > 0 ? "\(standHours)" : "暂无",
            unitText: standHours > 0 ? "小时" : "",
            goalText: standHours > 0 ? "\(standHours) / \(goal) 小时" : "目标 \(goal) 小时",
            subtitleText: standHours > 0 ? "站立达成度" : (hasTrend ? "所选日暂无" : "等待同步"),
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "figure.stand",
            tintHex: "73C8E8",
            trendPoints: trendPoints,
            isEmpty: standHours <= 0 && standHoursTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeHRVCard() -> HabitBodyMetricCardModel {
        let current = selectedDateHRV ?? 0
        let hasTrend = hrvTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(hrvTrend)
        let summary = trendSummary(for: .hrv, points: trendPoints, neutralText: "恢复波动暂时平稳")
        return HabitBodyMetricCardModel(
            kind: .hrv,
            title: "HRV",
            valueText: current > 0 ? "\(Int(current.rounded()))" : "暂无",
            unitText: current > 0 ? "ms" : "",
            goalText: current > 0 ? hrvStatusText(current) : (hasTrend ? "所选日暂无" : "等待同步"),
            subtitleText: "恢复参考",
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "waveform.path.ecg",
            tintHex: "E0547D",
            trendPoints: trendPoints,
            isEmpty: current <= 0 && hrvTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeRestingHeartRateCard() -> HabitBodyMetricCardModel {
        let current = restingHr
        let hasTrend = restingHeartRateTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(restingHeartRateTrend)
        let summary = trendSummary(for: .restingHeartRate, points: trendPoints, neutralText: "静息基线保持平稳")
        return HabitBodyMetricCardModel(
            kind: .restingHeartRate,
            title: "静息心率",
            valueText: current > 0 ? "\(Int(current.rounded()))" : "暂无",
            unitText: current > 0 ? "bpm" : "",
            goalText: current > 0 ? heartRateStatusText(average: Int(current.rounded())) : (hasTrend ? "所选日暂无" : "等待同步"),
            subtitleText: "安静基线",
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "heart.circle.fill",
            tintHex: "EF5350",
            trendPoints: trendPoints,
            isEmpty: current <= 0 && restingHeartRateTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeSunlightCard() -> HabitBodyMetricCardModel {
        let current = sunlightMinutes
        let hasTrend = sunlightTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(sunlightTrend)
        let summary = trendSummary(for: .sunlight, points: trendPoints, neutralText: "本周日照暴露平稳")
        return HabitBodyMetricCardModel(
            kind: .sunlight,
            title: "晒太阳时间",
            valueText: current > 0 ? "\(current)" : "暂无",
            unitText: current > 0 ? "分钟" : "",
            goalText: current > 0 ? (current >= 20 ? "已达标" : "还差 \(max(0, 20 - current)) 分钟") : (hasTrend ? "所选日暂无" : "等待同步"),
            subtitleText: "节律参考",
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "sun.max.fill",
            tintHex: "F4B46B",
            trendPoints: trendPoints,
            isEmpty: current <= 0 && sunlightTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeWristTemperatureCard() -> HabitBodyMetricCardModel {
        let current = sleepingWristTemperature
        let hasTrend = wristTemperatureTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(wristTemperatureTrend)
        let summary = trendSummary(for: .wristTemperature, points: trendPoints, neutralText: "夜间体温波动平稳")
        return HabitBodyMetricCardModel(
            kind: .wristTemperature,
            title: "手腕温度",
            valueText: current > 0 ? String(format: "%.1f", current) : "暂无",
            unitText: current > 0 ? "℃" : "",
            goalText: current > 0 ? wristTemperatureStatusText(current) : (hasTrend ? "所选日暂无" : "等待同步"),
            subtitleText: "夜间体温",
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "thermometer.medium",
            tintHex: "8266C6",
            trendPoints: trendPoints,
            isEmpty: current <= 0 && wristTemperatureTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeWalkingAsymmetryCard() -> HabitBodyMetricCardModel {
        let current = walkingAsymmetryPercentage
        let hasTrend = walkingAsymmetryTrend.contains(where: { $0.value > 0 })
        let trendPoints = convertTrend(walkingAsymmetryTrend)
        let summary = trendSummary(for: .walkingAsymmetry, points: trendPoints, neutralText: "步态平衡暂时平稳")
        return HabitBodyMetricCardModel(
            kind: .walkingAsymmetry,
            title: "步态不对称",
            valueText: current > 0 ? String(format: "%.1f", current) : "暂无",
            unitText: current > 0 ? "%" : "",
            goalText: current > 0 ? walkingAsymmetryStatusText(current) : (hasTrend ? "所选日暂无" : "等待同步"),
            subtitleText: "步态平衡",
            trendSummaryText: summary.badgeText,
            comparisonText: summary.detailText,
            referenceValue: averageTrendValue(trendPoints),
            highlightValue: trendPoints.last?.value,
            symbol: "figure.walk.motion",
            tintHex: "33A6DA",
            trendPoints: trendPoints,
            isEmpty: current <= 0 && walkingAsymmetryTrend.allSatisfy { $0.value <= 0 }
        )
    }

    func makeDailyActionCards() -> [HabitDailyActionCardModel] {
        let currentRecord = actionRecordStore.record(for: selectedDateContext)
        let waterGap = max(0, waterTarget - waterAmount)
        let sunlightGap = max(0, 20 - sunlightMinutes)
        let mindfulnessGap = mindfulnessMinutes == 0 ? 10 : max(0, 10 - mindfulnessMinutes)
        let standGoal = AppGroupManager.shared.getStandHoursGoal() ?? 12
        let standGap = max(0, standGoal - standHours)

        let cards: [(gap: Int, card: HabitDailyActionCardModel)] = [
            (
                waterGap,
                HabitDailyActionCardModel(
                    destination: .water,
                    title: "补水一下",
                    reasonText: waterGap > 0 ? "今天距离饮水目标还差 \(waterGap) ml，先补一杯更容易追平节奏。" : "今天的补水节奏已经跟上了。",
                    progressText: waterTarget > 0 ? "\(waterAmount) / \(waterTarget) ml" : "\(waterAmount) ml",
                    buttonTitle: waterGap > 0 ? "去喝水" : "查看记录",
                    tintHex: "32ADE6",
                    symbol: "drop.fill",
                    isCompleted: waterGap == 0 && waterAmount > 0,
                    isShared: currentRecord.isShared
                )
            ),
            (
                sunlightGap,
                HabitDailyActionCardModel(
                    destination: .sunlight,
                    title: "晒一会太阳",
                    reasonText: sunlightGap > 0 ? "当前日照偏少，补一点自然光更有助于提神和节律稳定。" : "今天已经有不错的日照暴露了。",
                    progressText: sunlightMinutes > 0 ? "\(sunlightMinutes) 分钟" : "等待同步",
                    buttonTitle: sunlightGap > 0 ? "看日照" : "查看趋势",
                    tintHex: "F4B46B",
                    symbol: "sun.max.fill",
                    isCompleted: sunlightGap == 0 && sunlightMinutes > 0,
                    isShared: currentRecord.isShared
                )
            ),
            (
                mindfulnessGap,
                HabitDailyActionCardModel(
                    destination: .mindfulness,
                    title: "做一次呼吸正念",
                    reasonText: mindfulnessMinutes == 0 ? "今天还没有正念记录，留 3 到 5 分钟给自己会更划算。" : "再补一点呼吸练习，恢复感会更完整。",
                    progressText: mindfulnessMinutes > 0 ? "\(mindfulnessMinutes) 分钟" : "0 分钟",
                    buttonTitle: "开始呼吸",
                    tintHex: "7AB7A8",
                    symbol: "wind",
                    isCompleted: mindfulnessGap == 0 && mindfulnessMinutes > 0,
                    isShared: currentRecord.isShared
                )
            ),
            (
                standGap,
                HabitDailyActionCardModel(
                    destination: .stand,
                    title: "起身活动",
                    reasonText: standGap > 0 ? "今天站立小时还差 \(standGap) 小时，分散起身会比集中补更轻松。" : "站立节奏已经不错，继续保持就好。",
                    progressText: "\(standHours) / \(standGoal) 小时",
                    buttonTitle: standGap > 0 ? "看日历" : "查看详情",
                    tintHex: "69B8F0",
                    symbol: "figure.walk",
                    isCompleted: standGap == 0 && standHours > 0,
                    isShared: currentRecord.isShared
                )
            )
        ]

        let pending = cards.filter { !$0.card.isCompleted }.sorted { $0.gap > $1.gap }.map { $0.card }
        let completed = cards.filter { $0.card.isCompleted }.map { $0.card }
        let combined = pending + completed
        return Array(combined.prefix(4))
    }

    func refreshDailyWellnessState() {
        let actionRecord = actionRecordStore.record(for: selectedDateContext)
        let context = DailyWellnessEvaluationContext(
            waterMl: waterAmount,
            sunlightMinutes: sunlightMinutes,
            mindfulnessMinutes: mindfulnessMinutes,
            standHours: standHours,
            actionRecord: actionRecord,
            now: Date()
        )
        _ = dailyWellnessStore.refreshFromHealthData(on: selectedDateContext, context: context)
        dailyWellnessSummary = dailyWellnessStore.summary(endingAt: selectedDateContext, days: 7)
        refreshLongTermHabitSummary()
        let progressMap = Dictionary(
            uniqueKeysWithValues: DailyWellnessEvaluator()
                .evaluate(date: selectedDateContext, context: context)
                .map { ($0.kind, $0) }
        )
        wellnessActionCards = DailyWellnessActionKind.allCases.map { kind in
            let definition = kind.definition
            let completed = dailyWellnessSummary.todayRecord.completedAction(kind)
            let progress = progressMap[kind]
            let isCompleted = completed != nil || progress?.isCompleted == true
            return DailyWellnessActionCardModel(
                kind: kind,
                title: definition.title,
                subtitle: definition.subtitle,
                targetText: definition.targetText,
                progressText: progress?.progressText ?? definition.targetText,
                detailText: isCompleted ? "今天这一项已经完成。" : (progress?.detailText ?? definition.subtitle),
                quickCompleteText: definition.quickCompleteText,
                symbol: definition.symbol,
                tintHex: definition.tintHex,
                isCompleted: isCompleted,
                sourceText: wellnessSourceText(completed?.source ?? progress?.source)
            )
        }
        let reminder = dailyWellnessStore.loadReminderSettings()
        wellnessReminderEnabled = reminder.isEnabled
        wellnessReminderTimeText = reminder.timeText
    }

    func refreshLongTermHabitSummary() {
        longTermHabitSummary = longTermHabitEngine.evaluate(
            endingAt: selectedDateContext,
            dailyRecords: dailyWellnessStore.allRecords(),
            actionRecords: actionRecordStore.allRecords(),
            challengeRecords: RecoveryChallengeStore.shared.allRecords()
        )
    }

    func wellnessSourceText(_ source: DailyWellnessCompletionSource?) -> String {
        switch source {
        case .healthData:
            return String(localized: "来自健康数据")
        case .quickComplete:
            return String(localized: "一键完成")
        case .microRecovery:
            return "微恢复完成"
        case .none:
            return String(localized: "未完成")
        }
    }

    func setSelectedDayShared(_ isShared: Bool) {
        actionRecordStore.setShared(isShared, for: selectedDateContext)
        selectedActionRecord = actionRecordStore.record(for: selectedDateContext)
        rebuildActionModels()
    }

    func setActionRecordShared(_ isShared: Bool, for date: Date) {
        actionRecordStore.setShared(isShared, for: date)
        if let detail = selectedActionDayDetail, Calendar.current.isDate(detail.date, inSameDayAs: date) {
            selectedActionDayDetail = ActionDayDetailModel(
                date: detail.date,
                title: detail.title,
                workoutTitle: detail.workoutTitle,
                movementSummary: detail.movementSummary,
                statItems: detail.statItems,
                statusTags: detail.statusTags,
                trendPoints: detail.trendPoints,
                insightText: detail.insightText,
                isShared: isShared,
                checkinMode: detail.checkinMode,
                manualWorkoutMinutes: detail.manualWorkoutMinutes,
                manualWorkoutDistanceKm: detail.manualWorkoutDistanceKm,
                manualWorkoutEffort: detail.manualWorkoutEffort,
                dailyMood: detail.dailyMood,
                fitnessNote: detail.fitnessNote,
                checkedInAt: detail.checkedInAt
            )
        }
        if Calendar.current.isDate(selectedDateContext, inSameDayAs: date) {
            selectedActionRecord = actionRecordStore.record(for: date)
        }
        rebuildActionModels()
    }

    func saveFitnessDayDetail(for date: Date, draft: FitnessDayDetailDraft) {
        actionRecordStore.updateRecord(for: date) { record in
            record.fitnessCheckinMode = draft.mode
            record.manualWorkoutMinutes = draft.mode == .workout ? max(0, draft.minutes) : 0
            record.manualWorkoutDistanceKm = draft.mode == .workout ? max(0, draft.distanceKm) : 0
            record.manualWorkoutEffort = draft.mode == .workout ? draft.effort : nil
            record.fitnessNote = draft.mode == .workout ? draft.note : ""
            record.dailyMood = draft.mood
            record.checkedInAt = draft.mode == nil ? nil : (record.checkedInAt ?? Date())
            record.isShared = draft.isShared
        }
        if Calendar.current.isDate(selectedDateContext, inSameDayAs: date) {
            selectedActionRecord = actionRecordStore.record(for: date)
        }
        rebuildActionModels()
        refreshSelectedActionDayDetailIfNeeded(for: date)

        // 写回健康 App 异步进行；失败不影响本地已保存的记录。
        Task {
            _ = await FitnessHealthWritebackService.shared.sync(draft: draft, for: date)
        }
    }

    func refreshSelectedActionDayDetailIfNeeded(for date: Date) {
        guard let detail = selectedActionDayDetail,
              Calendar.current.isDate(detail.date, inSameDayAs: date),
              let day = fitnessCalendarModel.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else {
            return
        }
        selectActionDay(day)
    }

}
