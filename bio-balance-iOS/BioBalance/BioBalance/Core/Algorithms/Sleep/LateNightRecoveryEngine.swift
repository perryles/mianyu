import Foundation

// MARK: - 熬夜严重程度

enum LateNightSeverity: String, Codable, Sendable, Comparable {
    case mild
    case moderate
    case severe

    static func < (lhs: LateNightSeverity, rhs: LateNightSeverity) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ s: LateNightSeverity) -> Int {
        switch s {
        case .mild: return 0
        case .moderate: return 1
        case .severe: return 2
        }
    }

    var label: String {
        switch self {
        case .mild: return "轻度熬夜"
        case .moderate: return "明显熬夜"
        case .severe: return "严重熬夜"
        }
    }

    var symbol: String {
        switch self {
        case .mild: return "moon.zzz.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .severe: return "bolt.triangle.fill"
        }
    }

    var accentColor: String {
        switch self {
        case .mild: return "accentOrange"
        case .moderate: return "accentRed"
        case .severe: return "accentRed"
        }
    }
}

// MARK: - 熬夜检测结果

struct LateNightDetectionResult: Equatable, Sendable {
    let isLateNight: Bool
    let severity: LateNightSeverity
    let sleepStartTime: Date?
    let sleepDurationMinutes: Int?
    let sleepDeficitMinutes: Int?
    let lateCaffeineMg: Int
    let stressLevel: Int?
    let reasons: [String]

    var deficitHours: Double? {
        guard let deficit = sleepDeficitMinutes, deficit > 0 else { return nil }
        return Double(deficit) / 60.0
    }
}

// MARK: - 恢复行动项

struct RecoveryAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let timeWindow: String
}

// MARK: - 次日恢复计划

struct LateNightRecoveryPlan: Equatable, Sendable {
    let detection: LateNightDetectionResult
    let recoveryCountdownDays: Int
    let morningActions: [RecoveryAction]
    let afternoonActions: [RecoveryAction]
    let eveningActions: [RecoveryAction]
    let caffeineCutoffHour: Int
    let napWindowStart: Date?
    let napWindowEnd: Date?
    let targetBedtimeOffsetMinutes: Int
    let headline: String
    let encouragement: String
    let watchPrompt: String

    var hasNapWindow: Bool {
        napWindowStart != nil && napWindowEnd != nil
    }
}

// MARK: - 熬夜恢复摘要（供 UI 使用）

struct LateNightRecoverySummary: Equatable, Sendable {
    let isActive: Bool
    let hasNoSleepData: Bool
    let plan: LateNightRecoveryPlan?

    var detection: LateNightDetectionResult? { plan?.detection }
    var severity: LateNightSeverity? { plan?.detection.severity }
    var countdownDays: Int? { plan?.recoveryCountdownDays }
}

// MARK: - 熬夜识别与恢复引擎

struct LateNightRecoveryEngine {
    struct Input {
        let sleepData: SleepData?
        let sleepInterval: SleepInterval?
        let sleepGoalMinutes: Int
        let caffeineEvents: [CaffeineDoseEvent]
        let stressLevel: Int?
        let now: Date
        let calendar: Calendar

        static func make(
            sleepData: SleepData?,
            sleepInterval: SleepInterval?,
            sleepGoalMinutes: Int = 480,
            caffeineEvents: [CaffeineDoseEvent] = [],
            stressLevel: Int? = nil,
            now: Date = Date(),
            calendar: Calendar = .current
        ) -> Input {
            Input(
                sleepData: sleepData,
                sleepInterval: sleepInterval,
                sleepGoalMinutes: sleepGoalMinutes,
                caffeineEvents: caffeineEvents,
                stressLevel: stressLevel,
                now: now,
                calendar: calendar
            )
        }
    }

    // MARK: - 熬夜检测

    func detect(input: Input) -> LateNightDetectionResult {
        let sleepStart = input.sleepInterval?.start
            ?? input.sleepData?.start_time.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let duration = input.sleepData.flatMap { $0.duration_minutes > 0 ? $0.duration_minutes : nil }

        // 入睡时间判定：凌晨 1 点后入睡算熬夜
        let lateNightThresholdHour = 1
        var isLateStart = false
        var startHourValue: Int = 0
        if let start = sleepStart {
            let components = input.calendar.dateComponents([.hour, .minute], from: start)
            let hour = components.hour ?? 0
            let minute = components.minute ?? 0
            startHourValue = hour
            // 0:00-5:59 算凌晨入睡
            if hour >= 0 && hour < 6 {
                let totalMinutes = hour * 60 + minute
                isLateStart = totalMinutes >= lateNightThresholdHour * 60
            }
        }

        // 睡眠不足判定
        let deficit: Int? = duration.map { max(0, input.sleepGoalMinutes - $0) }
        let isShortSleep = (deficit ?? 0) >= 90 // 不足 1.5 小时算熬夜

        // 晚间咖啡因（16:00 之后的摄入）
        let lateCaffeineMg = totalLateCaffeine(input: input)

        // 压力
        let stress = input.stressLevel

        // 综合判定
        let isLateNight = isLateStart || isShortSleep

        var reasons: [String] = []
        if isLateStart {
            let h = startHourValue
            if h >= 3 {
                reasons.append("凌晨 \(h) 点后才入睡")
            } else if h >= 1 {
                reasons.append("凌晨 1 点后入睡")
            }
        }
        if isShortSleep, let deficit, deficit > 0 {
            let hours = Double(deficit) / 60.0
            reasons.append(String(format: String(localized: "睡眠比目标少 %.1f 小时"), hours))
        }
        if lateCaffeineMg > 50 {
            reasons.append("晚间咖啡因残留约 \(lateCaffeineMg)mg")
        }
        if let stress, stress >= 65 {
            reasons.append("当前压力偏高（\(stress)）")
        }

        // 严重程度
        let severity = severityLevel(
            isLateStart: isLateStart,
            startHour: startHourValue,
            isShortSleep: isShortSleep,
            deficit: deficit ?? 0,
            lateCaffeineMg: lateCaffeineMg,
            stress: stress
        )

        return LateNightDetectionResult(
            isLateNight: isLateNight,
            severity: severity,
            sleepStartTime: sleepStart,
            sleepDurationMinutes: duration,
            sleepDeficitMinutes: deficit,
            lateCaffeineMg: lateCaffeineMg,
            stressLevel: stress,
            reasons: reasons
        )
    }

    private func severityLevel(
        isLateStart: Bool,
        startHour: Int,
        isShortSleep: Bool,
        deficit: Int,
        lateCaffeineMg: Int,
        stress: Int?
    ) -> LateNightSeverity {
        // severe: 凌晨 3 点后 / 睡眠不足 4h / 多重叠加
        if (isLateStart && startHour >= 3) || deficit >= 240 || (deficit >= 150 && lateCaffeineMg > 100) {
            return .severe
        }
        if let stress, stress >= 70, deficit >= 120 {
            return .severe
        }
        // moderate: 凌晨 2 点后 / 睡眠不足 5h / 晚间咖啡因 + 睡眠不足
        if (isLateStart && startHour >= 2) || deficit >= 180 || (deficit >= 90 && lateCaffeineMg > 50) {
            return .moderate
        }
        // mild: 其余熬夜情况
        return .mild
    }

    private func totalLateCaffeine(input: Input) -> Int {
        let sleepStart = input.sleepInterval?.start
            ?? input.sleepData?.start_time.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let referenceStart = lateCaffeineReferenceDayStart(sleepStart: sleepStart, now: input.now, calendar: input.calendar)
        guard let cutoff = input.calendar.date(bySettingHour: 16, minute: 0, second: 0, of: referenceStart) else {
            return 0
        }
        let intervalEnd: Date = sleepStart ?? lateCaffeineFallbackEnd(now: input.now, calendar: input.calendar)
        return input.caffeineEvents
            .filter { $0.consumedAt >= cutoff && $0.consumedAt <= intervalEnd }
            .reduce(0) { $0 + $1.amountMg }
    }

    private func lateCaffeineReferenceDayStart(sleepStart: Date?, now: Date, calendar: Calendar) -> Date {
        guard let sleepStart else {
            let startOfToday = calendar.startOfDay(for: now)
            let hour = calendar.component(.hour, from: now)
            if hour < 12 {
                return calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            }
            return startOfToday
        }

        let startOfSleepDay = calendar.startOfDay(for: sleepStart)
        let hour = calendar.component(.hour, from: sleepStart)
        if hour < 12 {
            return calendar.date(byAdding: .day, value: -1, to: startOfSleepDay) ?? startOfSleepDay
        }
        return startOfSleepDay
    }

    private func lateCaffeineFallbackEnd(now: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: now)
        if hour < 12 {
            return calendar.startOfDay(for: now)
        }
        return now
    }

    // MARK: - 次日恢复计划

    func makePlan(input: Input) -> LateNightRecoveryPlan? {
        let detection = detect(input: input)
        guard detection.isLateNight else { return nil }

        let severity = detection.severity
        let countdown = recoveryDays(for: severity)
        let cutoffHour = caffeineCutoffHour(for: severity)
        let bedtimeOffset = targetBedtimeOffset(for: severity)
        let napWindow = napWindow(for: severity, input: input)

        let morning = morningActions(for: severity)
        let afternoon = afternoonActions(for: severity, cutoffHour: cutoffHour, hasNap: napWindow != nil)
        let evening = eveningActions(for: severity, bedtimeOffset: bedtimeOffset)

        return LateNightRecoveryPlan(
            detection: detection,
            recoveryCountdownDays: countdown,
            morningActions: morning,
            afternoonActions: afternoon,
            eveningActions: evening,
            caffeineCutoffHour: cutoffHour,
            napWindowStart: napWindow?.start,
            napWindowEnd: napWindow?.end,
            targetBedtimeOffsetMinutes: bedtimeOffset,
            headline: headline(for: severity, detection: detection),
            encouragement: encouragement(for: severity),
            watchPrompt: watchPrompt(for: severity)
        )
    }

    // MARK: - 恢复参数

    private func recoveryDays(for severity: LateNightSeverity) -> Int {
        switch severity {
        case .mild: return 1
        case .moderate: return 2
        case .severe: return 3
        }
    }

    private func caffeineCutoffHour(for severity: LateNightSeverity) -> Int {
        switch severity {
        case .mild: return 15
        case .moderate: return 14
        case .severe: return 12
        }
    }

    private func targetBedtimeOffset(for severity: LateNightSeverity) -> Int {
        switch severity {
        case .mild: return 30
        case .moderate: return 45
        case .severe: return 60
        }
    }

    private func napWindow(for severity: LateNightSeverity, input: Input) -> (start: Date, end: Date)? {
        let cal = input.calendar
        let today = cal.startOfDay(for: input.now)

        switch severity {
        case .mild:
            // 13:00-13:20（20 分钟）
            guard let s = cal.date(bySettingHour: 13, minute: 0, second: 0, of: today),
                  let e = cal.date(bySettingHour: 13, minute: 20, second: 0, of: today) else { return nil }
            return (s, e)
        case .moderate:
            // 12:30-13:00（30 分钟）
            guard let s = cal.date(bySettingHour: 12, minute: 30, second: 0, of: today),
                  let e = cal.date(bySettingHour: 13, minute: 0, second: 0, of: today) else { return nil }
            return (s, e)
        case .severe:
            // 12:00-12:30（30 分钟）
            guard let s = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today),
                  let e = cal.date(bySettingHour: 12, minute: 30, second: 0, of: today) else { return nil }
            return (s, e)
        }
    }

    // MARK: - 行动项

    private func morningActions(for severity: LateNightSeverity) -> [RecoveryAction] {
        switch severity {
        case .mild:
            return [
                RecoveryAction(id: "sunlight", title: "晒太阳 10 分钟", detail: "起床后尽快接触自然光，帮助重置生物钟。", symbol: "sun.max.fill", timeWindow: "起床后 30 分钟内"),
                RecoveryAction(id: "hydrate", title: "喝 300ml 水", detail: "熬夜后身体偏脱水，先补水再考虑咖啡。", symbol: "drop.fill", timeWindow: "起床后"),
                RecoveryAction(id: "light_move", title: "轻度活动", detail: "散步或拉伸 10 分钟，不要剧烈运动。", symbol: "figure.walk", timeWindow: "上午")
            ]
        case .moderate:
            return [
                RecoveryAction(id: "sunlight", title: "晒太阳 15 分钟", detail: "自然光是重置节律最强的信号，尽量到户外。", symbol: "sun.max.fill", timeWindow: "起床后 30 分钟内"),
                RecoveryAction(id: "hydrate", title: "喝 500ml 水", detail: "睡眠不足时脱水更明显，先补水。", symbol: "drop.fill", timeWindow: "起床后"),
                RecoveryAction(id: "light_move", title: "轻度活动", detail: "散步 10-15 分钟，避免高强度训练加重负担。", symbol: "figure.walk", timeWindow: "上午"),
                RecoveryAction(id: "protein", title: "吃点蛋白质", detail: "鸡蛋、牛奶或豆制品，避免纯碳水早餐导致犯困。", symbol: "fork.knife", timeWindow: "早餐")
            ]
        case .severe:
            return [
                RecoveryAction(id: "sunlight", title: "晒太阳 20 分钟", detail: "严重熬夜后需要更强的的光照信号，尽量在户外。", symbol: "sun.max.fill", timeWindow: "起床后立即"),
                RecoveryAction(id: "hydrate", title: "喝 500ml 水", detail: "身体处于脱水 + 睡眠债状态，先补水。", symbol: "drop.fill", timeWindow: "起床后"),
                RecoveryAction(id: "light_move", title: "轻度活动", detail: "只做散步或拉伸，今天不要安排高强度训练。", symbol: "figure.walk", timeWindow: "上午"),
                RecoveryAction(id: "protein", title: "吃蛋白质早餐", detail: "补充优质蛋白，避免糖分过多导致血糖波动。", symbol: "fork.knife", timeWindow: "早餐"),
                RecoveryAction(id: "pace", title: "降低今天节奏", detail: "把非必要的高强度任务推迟，给身体恢复空间。", symbol: "tortoise.fill", timeWindow: "全天")
            ]
        }
    }

    private func afternoonActions(for severity: LateNightSeverity, cutoffHour: Int, hasNap: Bool) -> [RecoveryAction] {
        var actions: [RecoveryAction] = [
            RecoveryAction(
                id: "caffeine_cutoff",
                title: "咖啡因截止 \(String(format: "%02d:00", cutoffHour))",
                detail: "今天咖啡因代谢更慢，提前截止给今晚留恢复空间。",
                symbol: "cup.and.saucer.fill",
                timeWindow: "下午 \(String(format: "%02d", cutoffHour)):00 前"
            )
        ]

        if hasNap {
            switch severity {
            case .mild:
                actions.append(RecoveryAction(id: "nap", title: "可选小憩 20 分钟", detail: "如果下午犯困，可以闭眼休息 20 分钟，不要超过 30 分钟。", symbol: "bed.double.fill", timeWindow: "13:00-13:20"))
            case .moderate:
                actions.append(RecoveryAction(id: "nap", title: "建议小憩 30 分钟", detail: "午后小憩有助于缓解睡眠债，设好闹钟不要超过 30 分钟。", symbol: "bed.double.fill", timeWindow: "12:30-13:00"))
            case .severe:
                actions.append(RecoveryAction(id: "nap", title: "尽量小憩 30 分钟", detail: "严重熬夜后午后小憩能缓解硬撑感，设好闹钟，不要睡太久。", symbol: "bed.double.fill", timeWindow: "12:00-12:30"))
            }
        }

        actions.append(RecoveryAction(
            id: "daylight_afternoon",
            title: "下午再补一次光照",
            detail: "下午到窗边或户外走 5 分钟，对抗午后犯困。",
            symbol: "sun.haze.fill",
            timeWindow: "14:00-16:00"
        ))

        return actions
    }

    private func eveningActions(for severity: LateNightSeverity, bedtimeOffset: Int) -> [RecoveryAction] {
        let offsetText = "\(bedtimeOffset) 分钟"
        return [
            RecoveryAction(
                id: "early_winddown",
                title: "比平时提前 \(offsetText) 降刺激",
                detail: "今晚提前关掉强光、短视频和咖啡因，给身体降档信号。",
                symbol: "lightbulb.min.fill",
                timeWindow: "睡前 \(bedtimeOffset + 60) 分钟"
            ),
            RecoveryAction(
                id: "warm_shower",
                title: "温水澡或泡脚",
                detail: "体温下降的过程有助于入睡，比平时提前完成。",
                symbol: "shower.fill",
                timeWindow: "睡前 60 分钟"
            ),
            RecoveryAction(
                id: "breathing",
                title: "慢呼吸 5 分钟",
                detail: "4 秒吸 - 7 秒 hold - 8 秒呼，重复 5 轮帮助副交感激活。",
                symbol: "wind",
                timeWindow: "睡前 15 分钟"
            ),
            RecoveryAction(
                id: "monitoring",
                title: "佩戴手表监测",
                detail: "确认 Apple Watch 佩戴稳定，今晚重点看深睡恢复。",
                symbol: "applewatch.watchface",
                timeWindow: "入睡时"
            )
        ]
    }

    // MARK: - 文案

    private func headline(for severity: LateNightSeverity, detection: LateNightDetectionResult) -> String {
        switch severity {
        case .mild:
            return String(localized: "昨晚睡得偏晚，今天温和恢复")
        case .moderate:
            if let deficit = detection.deficitHours, deficit >= 3 {
                return String(format: String(localized: "睡眠债约 %.1f 小时，今天重点恢复"), deficit)
            }
            return String(localized: "昨晚明显熬夜，今天需要主动恢复")
        case .severe:
            return String(localized: "严重熬夜，今天以恢复为主")
        }
    }

    private func encouragement(for severity: LateNightSeverity) -> String {
        switch severity {
        case .mild:
            return String(localized: "一晚熬夜不难补，今天晒太阳 + 提前睡，明天基本能恢复。")
        case .moderate:
            return String(localized: "需要约 2 天恢复，今天关键是控制咖啡因和午后小憩，今晚提前入睡。")
        case .severe:
            return String(localized: "身体负担较重，未来 3 天都应以恢复优先，不要叠加高强度训练或加班。")
        }
    }

    private func watchPrompt(for severity: LateNightSeverity) -> String {
        switch severity {
        case .mild:
            return String(localized: "昨晚偏晚，今天多晒太阳、咖啡因早停。")
        case .moderate:
            return String(localized: "明显熬夜，午后小憩 30 分钟，今晚提前睡。")
        case .severe:
            return String(localized: "严重熬夜，今天只做恢复，不硬撑。")
        }
    }
}

// MARK: - 便捷入口

extension LateNightRecoveryEngine {
    /// 从 SleepViewModel 的数据直接生成摘要
    func makeSummary(
        sleepData: SleepData?,
        sleepInterval: SleepInterval?,
        sleepGoalMinutes: Int = 480,
        caffeineEvents: [CaffeineDoseEvent] = [],
        stressLevel: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LateNightRecoverySummary {
        let input = Input.make(
            sleepData: sleepData,
            sleepInterval: sleepInterval,
            sleepGoalMinutes: sleepGoalMinutes,
            caffeineEvents: caffeineEvents,
            stressLevel: stressLevel,
            now: now,
            calendar: calendar
        )
        let plan = makePlan(input: input)
        let hasNoData = (sleepData?.duration_minutes ?? 0) <= 0 && sleepInterval == nil
        return LateNightRecoverySummary(
            isActive: plan != nil,
            hasNoSleepData: hasNoData,
            plan: plan
        )
    }
}
