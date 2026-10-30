import Foundation
import HealthKit

/// TrendCategoryBuilder Workout 子模块。
/// 从 TrendCategoryBuilder.swift 按职责拆分，对外接口不变。

extension TrendCategoryBuilder {

    static func convertWorkoutSummaries(_ values: [WorkoutDaySummary]) -> [TimeSeriesPointDouble] {
        values.map { summary in
            TimeSeriesPointDouble(timestamp: Int64(summary.date.timeIntervalSince1970), value: Double(summary.totalMinutes))
        }
    }

    static func convertWorkoutCounts(_ values: [WorkoutDaySummary]) -> [TimeSeriesPointDouble] {
        values.map { summary in
            TimeSeriesPointDouble(timestamp: Int64(summary.date.timeIntervalSince1970), value: Double(summary.workoutCount))
        }
    }

    static func convertWorkoutDistances(_ values: [WorkoutDaySummary]) -> [TimeSeriesPointDouble] {
        values.compactMap { summary in
            guard let distance = summary.totalDistanceKilometers else { return nil }
            guard distance.isFinite, distance >= 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(summary.date.timeIntervalSince1970), value: distance)
        }
    }

    static func convertWorkoutEnergy(_ values: [WorkoutDaySummary]) -> [TimeSeriesPointDouble] {
        values.compactMap { summary in
            guard let measuredEnergy = summary.totalEnergyKilocalories else { return nil }
            let energy = Double(measuredEnergy)
            guard energy.isFinite, energy >= 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(summary.date.timeIntervalSince1970), value: energy)
        }
    }

    static func convertWorkoutPace(_ values: [WorkoutDaySummary]) -> [TimeSeriesPointDouble] {
        values.compactMap { summary in
            guard let distance = summary.totalDistanceKilometers, distance > 0 else { return nil }
            let pace = Double(summary.totalMinutes) / distance
            guard pace.isFinite, pace > 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(summary.date.timeIntervalSince1970), value: pace)
        }
    }

    static func convertWorkoutSpeed(_ values: [WorkoutDaySummary]) -> [TimeSeriesPointDouble] {
        values.compactMap { summary in
            guard summary.totalMinutes > 0,
                  let distance = summary.totalDistanceKilometers,
                  distance > 0 else { return nil }
            let hours = Double(summary.totalMinutes) / 60.0
            guard hours > 0 else { return nil }
            let speed = distance / hours
            guard speed.isFinite, speed > 0 else { return nil }
            return TimeSeriesPointDouble(timestamp: Int64(summary.date.timeIntervalSince1970), value: speed)
        }
    }

    static func dominantWorkoutTitle(from values: [WorkoutDaySummary]) -> String {
        values.reduce(into: [String: Double]()) { totals, summary in
            for (title, minutes) in summary.durationMinutesByWorkoutTitle {
                totals[title, default: 0] += minutes
            }
        }
        .max(by: { $0.value < $1.value })?.key ?? "待形成"
    }

    static func runningPaceSummary(from values: [TimeSeriesPointDouble]) -> String {
        guard let latest = values.last?.value, latest.isFinite, latest > 0 else {
            return "暂无"
        }
        return TrendMetricValueFormatter.string(for: latest, unit: "分/公里")
    }

    static func cyclingSpeedSummary(from values: [TimeSeriesPointDouble]) -> String {
        guard let latest = values.last?.value, latest.isFinite, latest > 0 else {
            return "暂无"
        }
        return TrendMetricValueFormatter.string(for: latest, unit: "km/h")
    }

    static func runningHeaderSummary(
        durationPoints: [TimeSeriesPointDouble],
        countPoints: [TimeSeriesPointDouble],
        distancePoints: [TimeSeriesPointDouble]
    ) -> String {
        if durationPoints.isEmpty && countPoints.isEmpty && distancePoints.isEmpty {
            return String(localized: "开始记录跑步后，这里会形成你的跑步节奏、里程和输出趋势。")
        }

        let windowDistance = completeWindowSum(
            for: distancePoints,
            expectedPointCount: durationPoints.count
        )
        let windowCount = sumOrNil(for: countPoints)
        let distanceText = windowDistance.map { String(format: "%.1fkm", $0) } ?? "记录不完整"
        let countText = windowCount.map { "\(Int($0.rounded())) 次" } ?? "暂无频次"
        return String(localized: "先用跑步时长、频次和距离看整体跑步节奏，当前窗口里程\(distanceText)，频次\(countText)。")
    }

    static func cyclingHeaderSummary(
        durationPoints: [TimeSeriesPointDouble],
        countPoints: [TimeSeriesPointDouble],
        distancePoints: [TimeSeriesPointDouble]
    ) -> String {
        if durationPoints.isEmpty && countPoints.isEmpty && distancePoints.isEmpty {
            return String(localized: "开始记录骑行后，这里会形成你的骑行时长、里程和输出趋势。")
        }

        let windowDistance = completeWindowSum(
            for: distancePoints,
            expectedPointCount: durationPoints.count
        )
        let windowCount = sumOrNil(for: countPoints)
        let distanceText = windowDistance.map { String(format: "%.1fkm", $0) } ?? "记录不完整"
        let countText = windowCount.map { "\(Int($0.rounded())) 次" } ?? "暂无频次"
        return String(localized: "先用骑行时长、频次和距离看整体骑行节奏，当前窗口里程\(distanceText)，频次\(countText)。")
    }

    static func nutritionHeaderSummary(
        range: TrendsRange,
        mealCaloriePoints: [TimeSeriesPointDouble],
        mealCountPoints: [TimeSeriesPointDouble],
        hydrationPoints: [TimeSeriesPointDouble],
        completionPoints: [TimeSeriesPointDouble],
        caffeinePoints: [TimeSeriesPointDouble]
    ) -> String {
        let mealCalories = Int(mealCaloriePoints.reduce(0) { $0 + max(0, $1.value) }.rounded())
        let mealCount = Int(mealCountPoints.reduce(0) { $0 + max(0, $1.value) }.rounded())

        if mealCount == 0 && hydrationPoints.isEmpty && completionPoints.isEmpty && caffeinePoints.isEmpty {
            return String(localized: "从餐食识别、补水或咖啡因记录开始，这里会按当前窗口形成真实摄入趋势。")
        }

        let latestHydration = hydrationPoints.last.map { "\(Int($0.value.rounded()))ml" } ?? "暂无补水"
        let latestCompletion = completionPoints.last.map { "\(Int($0.value.rounded()))%" } ?? "暂无达标率"
        if mealCount > 0 {
            return String(localized: "\(range.title)窗口已联动餐食识别：记录 \(mealCount) 餐、合计 \(mealCalories)kcal；补水\(latestHydration)，达标\(latestCompletion)。")
        }
        return String(localized: "当前窗口已有补水或咖啡因记录：补水\(latestHydration)，达标\(latestCompletion)。")
    }

    static func symptomsIllnessHeaderSummary(
        range: TrendsRange,
        symptomRecords: [SelfObservationRecord],
        medicationEntryPoints: [TimeSeriesPointDouble],
        prescriptionCount: Int
    ) -> String {
        let now = Date()
        let windowSymptomRecords = symptomRecords.filter {
            $0.recordedAt >= range.startDate && $0.recordedAt <= now
        }
        let windowRecordCount = windowSymptomRecords.count
        let windowMedicationCount = Int(medicationEntryPoints.reduce(0) { $0 + max(0, $1.value) }.rounded())
        let severityValues = windowSymptomRecords.map { Double($0.symptomSeverity) }
        let averageSeverity: Double? = severityValues.isEmpty
            ? nil
            : severityValues.reduce(0, +) / Double(severityValues.count)

        if windowRecordCount > 0 {
            let severityText = averageSeverity.map { String(format: "%.1f/5", $0) } ?? "未填写"
            return String(localized: "\(range.title)窗口记录了 \(windowRecordCount) 次症状，平均强度 \(severityText)；同期用药 \(windowMedicationCount) 次。")
        }
        if !symptomRecords.isEmpty || windowMedicationCount > 0 || prescriptionCount > 0 {
            return String(localized: "当前窗口没有新的症状记录；健康页已有 \(symptomRecords.count) 条历史症状、\(prescriptionCount) 份处方资料，可继续回看和维护。")
        }
        return String(localized: "健康页还没有症状或病史资料，可以进入详情记录症状、用药与处方信息。")
    }

    static func swimmingHeaderSummary(
        durationPoints: [TimeSeriesPointDouble],
        countPoints: [TimeSeriesPointDouble],
        distancePoints: [TimeSeriesPointDouble]
    ) -> String {
        if durationPoints.isEmpty && countPoints.isEmpty && distancePoints.isEmpty {
            return String(localized: "开始记录游泳后，这里会形成你的游泳时长、里程和输出趋势。")
        }

        let windowDistance = completeWindowSum(
            for: distancePoints,
            expectedPointCount: durationPoints.count
        )
        let windowCount = sumOrNil(for: countPoints)
        let distanceText = windowDistance.map { String(format: "%.1fkm", $0) } ?? "记录不完整"
        let countText = windowCount.map { "\(Int($0.rounded())) 次" } ?? "暂无频次"
        return String(localized: "先用游泳时长、频次和距离看整体游泳节奏，当前窗口里程\(distanceText)，频次\(countText)。")
    }

}
