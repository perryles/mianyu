import SwiftUI

/// HabitViewModel 生活节律域：习惯行 / 饮水 / 微恢复 / 提醒 / 日历范围。
/// 从原 HabitViewModel.swift 拆出，对外接口不变。

@MainActor
extension HabitViewModel {

    func resetDisplayState() {
        sleepDuration = 0
        activeEnergy = 0
        basalEnergy = 0
        stepCount = 0
        sleepScore = 0
        restingHr = 0.0
        exerciseMinutes = 0
        standHours = 0
        sunlightMinutes = 0
        mindfulnessMinutes = 0
        environmentalAudioExposureDb = 0.0
        sleepingWristTemperature = 0.0
        walkingAsymmetryPercentage = 0.0
        selectedDateHRV = nil
        stateOfMindTitle = "未记录"
        stateOfMindDetail = "打开健康 App 记录心理状态后会显示在这里"
        stateOfMindIntensity = 0
        stateOfMindDate = nil
        waterAmount = 0
        caffeineAmount = 0
        waterCompletionRate = 0.0
        heartRateSeries = []
        heartRateDailyTrend = []
        activeEnergyTrend = []
        basalEnergyTrend = []
        standHoursTrend = []
        hrvTrend = []
        restingHeartRateTrend = []
        sunlightTrend = []
        wristTemperatureTrend = []
        walkingAsymmetryTrend = []
        exerciseMinutesTrend = []
        calendarWorkoutSummaries = [:]
        dailyActionCards = []
        wellnessActionCards = []
        dailyWellnessSummary = .empty(for: selectedDateContext)
        longTermHabitSummary = .empty(for: selectedDateContext)
        microRecoveryState = .idle
        fitnessStatsCards = []
        fitnessCalendarModel = HabitFitnessCalendarModel(
            scope: calendarScope,
            rangeTitle: "",
            streakText: "等待同步",
            summaryPills: ["连续 0 天", "锻炼 0 分钟", "消耗 0 kcal"],
            days: []
        )
        selectedActionDayDetail = nil
        selectedActionRecord = nil
    }

    func rebuildLifeHabitRows() {
        lifeHabitRows = [
            HabitLifeRowModel(
                destination: .drinkHub,
                title: "补水与饮品",
                symbol: "drop.circle.fill",
                valueText: drinkHubValueText,
                unitText: drinkHubUnitText,
                tintHex: "32ADE6"
            ),
            HabitLifeRowModel(
                destination: .sunlight,
                title: "晒太阳",
                symbol: "sun.max.fill",
                valueText: sunlightMinutes > 0 ? "\(sunlightMinutes)" : "暂无",
                unitText: sunlightMinutes > 0 ? "分钟" : "",
                tintHex: "F4B46B"
            ),
            HabitLifeRowModel(
                destination: .mindfulness,
                title: "呼吸正念",
                symbol: "wind",
                valueText: mindfulnessMinutes > 0 ? "\(mindfulnessMinutes)" : "暂无",
                unitText: mindfulnessMinutes > 0 ? "分钟" : "",
                tintHex: "7AB7A8"
            )
        ]
    }

    private var drinkHubValueText: String {
        if waterAmount > 0 && caffeineAmount > 0 {
            return "\(waterAmount)ml / \(caffeineAmount)mg"
        }
        if waterAmount > 0 {
            return "\(waterAmount)"
        }
        if caffeineAmount > 0 {
            return "\(caffeineAmount)"
        }
        return "暂无"
    }

    private var drinkHubUnitText: String {
        if waterAmount > 0 && caffeineAmount > 0 {
            return ""
        }
        if waterAmount > 0 {
            return String(localized: "毫升")
        }
        if caffeineAmount > 0 {
            return "毫克咖啡因"
        }
        return ""
    }

    func rebuildBodyHabitModels() {
        bodyHabitHeroCardModel = makeHeartRateHeroCard()
        bodyHabitMetricCards = [
            makeBasalEnergyCard(),
            makeActiveEnergyCard(),
            makeStandHoursCard(),
            makeHRVCard(),
            makeRestingHeartRateCard(),
            makeSunlightCard(),
            makeWristTemperatureCard(),
            makeWalkingAsymmetryCard()
        ]
    }

    func rebuildActionModels(
        calendarEnergyTrend: [TimeSeriesPointDouble]? = nil,
        calendarExerciseTrend: [TimeSeriesPointDouble]? = nil,
        calendarStandTrend: [TimeSeriesPointDouble]? = nil,
        calendarHrvTrend: [TimeSeriesPointDouble]? = nil
    ) {
        refreshDailyWellnessState()
        dailyActionCards = makeDailyActionCards()
        let calendarModel = makeFitnessCalendarModel(
            scope: calendarScope,
            energyTrend: calendarEnergyTrend,
            exerciseTrend: calendarExerciseTrend,
            standTrend: calendarStandTrend,
            hrvTrend: calendarHrvTrend
        )
        fitnessCalendarModel = calendarModel
        fitnessStatsCards = makeFitnessStatsCards(
            scope: calendarScope,
            days: calendarModel.days
        )
        selectedActionRecord = actionRecordStore.record(for: selectedDateContext)
    }

    func completeWellnessAction(_ kind: DailyWellnessActionKind) {
        switch kind {
        case .water:
            waterAmount = max(waterAmount, 0) + kind.definition.defaultAmount
            actionRecordStore.updateRecord(for: selectedDateContext) { record in
                record.waterMl = max(record.waterMl, waterAmount)
                record.completedActions.append(.water)
            }
            dailyWellnessStore.complete(kind: kind, on: selectedDateContext, source: .quickComplete, value: kind.definition.defaultAmount)
            let settings = HabitReminderManager.shared.load()
            HabitReminderManager.shared.scheduleWaterNudgeIfNeeded(settings: settings)
            Task { try? await HealthKitManager.shared.saveDietaryWater(milliliters: kind.definition.defaultAmount) }
        case .sunlight:
            sunlightMinutes = max(sunlightMinutes, kind.definition.defaultAmount)
            actionRecordStore.updateRecord(for: selectedDateContext) { record in
                record.sunlightMinutes = max(record.sunlightMinutes, kind.definition.defaultAmount)
                record.completedActions.append(.sunlight)
            }
            dailyWellnessStore.complete(kind: kind, on: selectedDateContext, source: .quickComplete, value: kind.definition.defaultAmount)
        case .breathing:
            mindfulnessMinutes = max(mindfulnessMinutes, kind.definition.defaultAmount)
            actionRecordStore.updateRecord(for: selectedDateContext) { record in
                record.mindfulnessMinutes = max(record.mindfulnessMinutes, kind.definition.defaultAmount)
                record.completedActions.append(.mindfulness)
            }
            dailyWellnessStore.complete(kind: kind, on: selectedDateContext, source: .quickComplete, value: kind.definition.defaultAmount)
        case .move:
            standHours = max(standHours, 1)
            actionRecordStore.updateRecord(for: selectedDateContext) { record in
                record.standHours = max(record.standHours, 1)
                record.completedActions.append(.stand)
            }
            dailyWellnessStore.complete(kind: kind, on: selectedDateContext, source: .quickComplete, value: kind.definition.defaultAmount)
        case .bedtimeWindDown:
            dailyWellnessStore.complete(kind: kind, on: selectedDateContext, source: .quickComplete, value: kind.definition.defaultAmount)
        }

        syncSelectedDayActionRecord()
        selectedActionRecord = actionRecordStore.record(for: selectedDateContext)
        refreshDailyWellnessState()
        rebuildLifeHabitRows()
        rebuildActionModels()
        persistHabitSummaryToAppGroup()
        showSuccessMessage("\(kind.definition.title)已完成", duration: .milliseconds(1_800))
    }

    func completeMicroRecovery() {
        let preferSunlight = sunlightMinutes < 5
        dailyWellnessStore.completeMicroRecovery(on: selectedDateContext, preferSunlight: preferSunlight)
        mindfulnessMinutes = max(mindfulnessMinutes, 3)
        standHours = max(standHours, 1)
        if preferSunlight {
            sunlightMinutes = max(sunlightMinutes, 5)
        } else {
            waterAmount += 250
        }
        actionRecordStore.updateRecord(for: selectedDateContext) { record in
            record.mindfulnessMinutes = max(record.mindfulnessMinutes, 3)
            record.standHours = max(record.standHours, 1)
            record.completedActions.append(.mindfulness)
            record.completedActions.append(.stand)
            if preferSunlight {
                record.sunlightMinutes = max(record.sunlightMinutes, 5)
                record.completedActions.append(.sunlight)
            } else {
                record.waterMl = max(record.waterMl, waterAmount)
                record.completedActions.append(.water)
            }
        }
        syncSelectedDayActionRecord()
        selectedActionRecord = actionRecordStore.record(for: selectedDateContext)
        refreshDailyWellnessState()
        rebuildLifeHabitRows()
        rebuildActionModels()
        persistHabitSummaryToAppGroup()
        microRecoveryState = .completed("3 分钟微恢复已完成")
        showSuccessMessage("微恢复流程已完成", duration: .milliseconds(1_800))
    }

    func toggleWellnessReminder(_ enabled: Bool) {
        var settings = dailyWellnessStore.loadReminderSettings()
        settings.isEnabled = enabled
        if enabled {
            Task {
                _ = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
                await MainActor.run {
                    self.dailyWellnessStore.saveReminderSettings(settings)
                    self.wellnessReminderEnabled = settings.isEnabled
                    self.wellnessReminderTimeText = settings.timeText
                }
            }
        } else {
            dailyWellnessStore.saveReminderSettings(settings)
            wellnessReminderEnabled = settings.isEnabled
            wellnessReminderTimeText = settings.timeText
        }
    }

    func updateCalendarScope(_ scope: HabitCalendarScope) {
        guard calendarScope != scope else { return }
        calendarScope = scope
        loadData(for: selectedDateContext)
    }

    func selectActionDay(_ day: HabitFitnessCalendarDay) {
        let hrvText: String
        if let hrv = day.hrvValue, hrv > 0 {
            hrvText = "\(Int(hrv.rounded())) ms"
        } else {
            hrvText = "暂无"
        }

        let workoutTitle = calendarWorkoutSummaries[Calendar.current.startOfDay(for: day.date)]?.dominantWorkoutTitle
            ?? day.checkinMode?.title
            ?? "综合活动"
        let movementSummary: String
        if day.displayWorkoutMinutes > 0 {
            movementSummary = "\(workoutTitle) · \(day.displayWorkoutMinutes) 分钟 · \(day.activeEnergy) kcal"
        } else if day.checkinMode == .recovery {
            movementSummary = "今天已作为轻恢复日打卡，节奏连续会继续累计。"
        } else if day.checkinMode == .rest {
            movementSummary = "今天已作为休息日打卡，属于训练节律的一部分。"
        } else if day.activeEnergy > 0 {
            movementSummary = "日常活动为主 · 消耗 \(day.activeEnergy) kcal · 站立 \(day.standHours) 小时"
        } else {
            movementSummary = "当天暂无明显训练记录"
        }

        // 距离、心情等编辑字段从本地记录读取，供详情页回显与再编辑。
        let localRecord = actionRecordStore.record(for: day.date)

        selectedActionDayDetail = ActionDayDetailModel(
            date: day.date,
            title: ChineseDateText.writtenMonthDay(day.date),
            workoutTitle: workoutTitle,
            movementSummary: movementSummary,
            statItems: [
                ActionDayDetailStatItem(title: "打卡", valueText: day.checkinMode?.shortTitle ?? "未打卡", tintHex: day.checkinMode?.tintHex ?? "94A3C3"),
                ActionDayDetailStatItem(title: "锻炼", valueText: day.displayWorkoutMinutes > 0 ? "\(day.displayWorkoutMinutes) 分钟" : "暂无", tintHex: "F06A7B"),
                ActionDayDetailStatItem(title: "消耗", valueText: day.activeEnergy > 0 ? "\(day.activeEnergy) kcal" : "暂无", tintHex: "FF9F66"),
                ActionDayDetailStatItem(title: "HRV", valueText: hrvText, tintHex: "DE5B84")
            ],
            statusTags: [],
            trendPoints: exerciseMinutesTrend
                .filter { Calendar.current.isDate($0.date, equalTo: day.date, toGranularity: .weekOfYear) }
                .filter { $0.value > 0 }
                .map { HabitTrendPoint(date: $0.date, value: $0.value) },
            insightText: "",
            isShared: localRecord.isShared,
            checkinMode: day.checkinMode,
            manualWorkoutMinutes: day.manualWorkoutMinutes,
            manualWorkoutDistanceKm: localRecord.manualWorkoutDistanceKm,
            manualWorkoutEffort: day.manualWorkoutEffort,
            dailyMood: localRecord.dailyMood,
            fitnessNote: day.fitnessNote,
            checkedInAt: day.checkedInAt
        )
    }

}
