import Foundation

/// 评估咖啡因残留对睡眠窗口与压力的影响。
struct CaffeineSleepStressCoachEngine {
    private let halfLifeHours: Double = 5.0
    private let maximumDoseMg = 5_000
    private let maximumDailyTotalMg = 20_000

    func loadDoseEvents(for day: Date, store: ActionRecordStore = .shared) -> [CaffeineDoseEvent] {
        store.caffeineDoseEvents(on: day)
    }

    func loadDoseEvents(for interval: DateInterval, store: ActionRecordStore = .shared) -> [CaffeineDoseEvent] {
        store.caffeineDoseEvents(in: interval)
    }

    func estimateRemaining(events: [CaffeineDoseEvent], at time: Date) -> Int {
        guard !events.isEmpty else { return 0 }
        let amount = events.reduce(0.0) { partialResult, event in
            let hours = max(0, time.timeIntervalSince(event.consumedAt) / 3600.0)
            let ratio = pow(0.5, hours / halfLifeHours)
            let dose = min(maximumDoseMg, max(0, event.amountMg))
            return min(Double(maximumDailyTotalMg), partialResult + Double(dose) * ratio)
        }
        return max(0, Int(amount.rounded()))
    }

    func burdenSnapshot(
        dailyTotalMg: Int,
        doseEvents: [CaffeineDoseEvent],
        now: Date
    ) -> CaffeineBurdenSnapshot {
        let hasTimedEvents = !doseEvents.isEmpty
        let normalizedDailyTotal = min(maximumDailyTotalMg, max(0, dailyTotalMg))
        let timedDoseTotal = boundedDoseTotal(doseEvents)
        return CaffeineBurdenSnapshot(
            consumedTodayMg: max(normalizedDailyTotal, timedDoseTotal),
            estimatedRemainingMg: hasTimedEvents
                ? estimateRemaining(events: doseEvents, at: now)
                : Int((Double(normalizedDailyTotal) * 0.55).rounded()),
            lastDoseAt: doseEvents.sorted(by: { $0.consumedAt < $1.consumedAt }).last?.consumedAt,
            timedDoseCount: doseEvents.count,
            confidence: hasTimedEvents ? 0.92 : (dailyTotalMg > 0 ? 0.42 : 0.18)
        )
    }

    func assessSleepRisk(
        dailyTotalMg: Int,
        doseEvents: [CaffeineDoseEvent],
        now: Date,
        targetBedtime: Date,
        sleepGoalMinutes: Int,
        stressScore: Int?,
        lastNightSleepMinutes: Int?,
        lastNightSleepScore: Int?
    ) -> CaffeineSleepRiskAssessment {
        let snapshot = burdenSnapshot(dailyTotalMg: dailyTotalMg, doseEvents: doseEvents, now: now)
        let remainingAtBedtime = doseEvents.isEmpty ? snapshot.estimatedRemainingMg : estimateRemaining(events: doseEvents, at: targetBedtime)
        let hoursToBed = max(0, targetBedtime.timeIntervalSince(now) / 3600.0)
        let stress = stressScore ?? 0
        let sleepMinutes = lastNightSleepMinutes ?? 0
        let sleepScore = lastNightSleepScore ?? 0
        let lateDoseExists = doseEvents.contains {
            let hour = Calendar.current.component(.hour, from: $0.consumedAt)
            return hour >= 15
        }

        let level: CaffeineRiskLevel
        if (sleepScore > 0 && sleepScore < 70 && snapshot.estimatedRemainingMg >= 60)
            || (sleepMinutes > 0 && sleepMinutes < Int(Double(sleepGoalMinutes) * 0.85) && snapshot.estimatedRemainingMg >= 60)
            || (stress >= 65 && snapshot.estimatedRemainingMg >= 70) {
            level = .recoveryRisk
        } else if remainingAtBedtime >= 80 || (lateDoseExists && snapshot.estimatedRemainingMg >= 55 && hoursToBed < 8) {
            level = .lateRisk
        } else if snapshot.estimatedRemainingMg >= 45 || dailyTotalMg >= 240 {
            level = .watch
        } else {
            level = .safe
        }

        let sleepWindowRisk: String
        if doseEvents.isEmpty && dailyTotalMg > 0 {
            sleepWindowRisk = "今天只有总量记录，补上饮用时间后，才能更准确判断今晚的入睡窗口。"
        } else {
            switch level {
            case .safe:
                sleepWindowRisk = "按当前残留看，今晚的入睡窗口压力相对可控。"
            case .watch:
                sleepWindowRisk = "今晚入睡窗口需要继续观察，后面尽量别再补刺激。"
            case .lateRisk:
                sleepWindowRisk = "当前残留更容易把刺激拖进晚上，建议提前收住。"
            case .recoveryRisk:
                sleepWindowRisk = "在恢复已经偏紧的情况下，这个残留更容易继续拖累今晚睡眠。"
            }
        }

        let stressAmplifierRisk: String
        if stress >= 65 && snapshot.estimatedRemainingMg >= 50 {
            stressAmplifierRisk = "今天压力本来就偏高，这杯更像继续透支而不是稳稳提神。"
        } else if stress >= 50 && snapshot.estimatedRemainingMg >= 40 {
            stressAmplifierRisk = "在紧绷感已经起来的时候，咖啡因会让身体更难自然放松。"
        } else {
            stressAmplifierRisk = "当前更像是常规刺激输入，重点是别让摄入继续拖到后半天。"
        }

        let todayAdvice: String
        switch level {
        case .safe:
            todayAdvice = "后面以补水和正常进食为主，今晚照常把节律守住就好。"
        case .watch:
            todayAdvice = "今天后半段尽量不再补高咖啡因，把晚上的收尾和入睡时间往前放。"
        case .lateRisk:
            todayAdvice = "现在更需要停住继续摄入，并把训练、工作和屏幕刺激一起收下来。"
        case .recoveryRisk:
            todayAdvice = "今天优先保恢复，后半天别再靠刺激硬顶，尽量把睡前流程提前。"
        }

        return CaffeineSleepRiskAssessment(
            currentRemainingMg: snapshot.estimatedRemainingMg,
            riskLevel: level,
            sleepWindowRisk: sleepWindowRisk,
            stressAmplifierRisk: stressAmplifierRisk,
            todayAdvice: todayAdvice,
            confidence: snapshot.confidence
        )
    }

    func weeklySummary(
        events: [CaffeineDoseEvent],
        dailyTotals: [Date: Int],
        averageSleepMinutes: Double?,
        averageStress: Double?,
        sleepGoalMinutes: Int
    ) -> CaffeineWeeklyCoachSummary {
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.consumedAt) }
        let highTotalDays = dailyTotals.filter { $0.value >= 260 }.count
        let lateDays = grouped.values.filter {
            $0.contains { Calendar.current.component(.hour, from: $0.consumedAt) >= 15 }
        }.count
        let recoveryDragLikely = (averageSleepMinutes ?? Double(sleepGoalMinutes)) < Double(sleepGoalMinutes) * 0.9 || (averageStress ?? 0) >= 55

        var patterns: [String] = []
        if highTotalDays > 0 {
            patterns.append("这周有 \(highTotalDays) 天总量偏高。")
        }
        if lateDays > 0 {
            patterns.append("这周有 \(lateDays) 天摄入偏晚。")
        }
        if recoveryDragLikely && (highTotalDays > 0 || lateDays > 0) {
            patterns.append("这周的咖啡因节律已经开始拖慢恢复。")
        }
        if patterns.isEmpty {
            patterns.append("这周整体摄入还算克制，关键是继续守住晚间时间点。")
        }

        let dangerousMoments = grouped.values
            .compactMap { dayEvents -> (Date, Int, Int)? in
                let latest = dayEvents.max(by: { $0.consumedAt < $1.consumedAt })
                let total = boundedDoseTotal(Array(dayEvents))
                guard let latest else { return nil }
                let hour = Calendar.current.component(.hour, from: latest.consumedAt)
                let riskScore = total + (hour >= 15 ? 80 : 0)
                return (latest.consumedAt, total, riskScore)
            }
            .sorted { $0.2 > $1.2 }
            .prefix(2)
            .map {
                let formatter = DateFormatter()
                formatter.locale = Locale.autoupdatingCurrent
                formatter.dateFormat = "M月d日 HH:mm"
                return String(localized: "\(formatter.string(from: $0.0)) 左右累计 \($0.1)mg")
            }

        let headline: String
        if recoveryDragLikely && lateDays > 0 {
            headline = "这周更像是摄入偏晚在拖恢复。"
        } else if highTotalDays > 0 {
            headline = "这周更值得先把总量收回来。"
        } else if lateDays > 0 {
            headline = "这周更需要把时间点往前收。"
        } else {
            headline = "这周的咖啡因节律总体可控。"
        }

        return CaffeineWeeklyCoachSummary(
            headline: headline,
            patterns: patterns,
            dangerousMoments: dangerousMoments,
            confidence: events.isEmpty ? 0.35 : 0.86
        )
    }

    /// 对持久化历史执行饱和求和，避免异常剂量或重复记录造成整数溢出。
    private func boundedDoseTotal(_ events: [CaffeineDoseEvent]) -> Int {
        events.reduce(0) { total, event in
            let dose = min(maximumDoseMg, max(0, event.amountMg))
            return min(maximumDailyTotalMg, total + dose)
        }
    }
}
