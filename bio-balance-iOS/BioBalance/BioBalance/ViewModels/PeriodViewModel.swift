import Foundation
import SwiftUI
import HealthKit

/// PeriodEvent标签结构体 作为视图模型层里的辅助类型。
/// 负责连接界面与底层数据源，处理状态管理、业务计算和用户操作响应。
struct PeriodEventTag: Identifiable, Hashable {
    enum Style: Hashable {
        case alert
        case neutral
        case positive
        case fertile
    }

    let title: String
    let style: Style

    var id: String { title }
}

enum FemaleWellnessState: String, CaseIterable, Identifiable {
    case steady
    case lowEnergy
    case stressed
    case bloated
    case sensitive
    case dischargeChange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steady: return String(localized: "状态平稳")
        case .lowEnergy: return String(localized: "精力偏低")
        case .stressed: return String(localized: "压力偏高")
        case .bloated: return String(localized: "腹胀明显")
        case .sensitive: return String(localized: "身体敏感")
        case .dischargeChange: return String(localized: "分泌物变化")
        }
    }

    var systemImage: String {
        switch self {
        case .steady: return "checkmark.circle.fill"
        case .lowEnergy: return "battery.25percent"
        case .stressed: return "brain.head.profile"
        case .bloated: return "circle.grid.2x2.fill"
        case .sensitive: return "waveform.path.ecg"
        case .dischargeChange: return "drop.fill"
        }
    }
}

enum FemaleSymptom: String, CaseIterable, Identifiable {
    case cramps
    case bloating
    case acne
    case nausea
    case chills
    case hotFlash
    case constipation
    case headache
    case breastTenderness
    case fatigue
    case insomnia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cramps: return String(localized: "痉挛")
        case .bloating: return String(localized: "胀气")
        case .acne: return String(localized: "痤疮")
        case .nausea: return String(localized: "恶心")
        case .chills: return String(localized: "发冷")
        case .hotFlash: return String(localized: "潮热")
        case .constipation: return String(localized: "便秘")
        case .headache: return String(localized: "头痛")
        case .breastTenderness: return String(localized: "乳房胀痛")
        case .fatigue: return String(localized: "疲劳")
        case .insomnia: return String(localized: "入睡困难")
        }
    }

    var systemImage: String {
        switch self {
        case .cramps: return "waveform.path.ecg"
        case .bloating: return "circle.grid.2x2.fill"
        case .acne: return "sparkles"
        case .nausea: return "cross.case.fill"
        case .chills: return "snowflake"
        case .hotFlash: return "flame.fill"
        case .constipation: return "figure.walk"
        case .headache: return "brain.head.profile"
        case .breastTenderness: return "heart.fill"
        case .fatigue: return "battery.25percent"
        case .insomnia: return "moon.zzz.fill"
        }
    }
}

struct FemaleDailyRhythmSuggestion: Identifiable {
    let id: String
    let title: String
    let detail: String
}

/// 周期健康Syncing协议 作为视图模型层里的能力约束定义。
/// 负责约束界面状态管理与业务编排相关能力的统一接口。
protocol PeriodHealthSyncing {
    func syncCycle(startDate: Date, endDate: Date?) async
    func syncFlow(date: Date, flowLevel: Int, isCycleStart: Bool) async
    func syncSymptoms(date: Date, painLevel: Int, moodLevel: Int) async
    func syncReproductiveEvents(
        date: Date,
        hasSexualActivity: Bool,
        hasIntermenstrualBleeding: Bool,
        pregnancyTestResult: String?,
        ovulationTestResult: String?,
        cervicalMucusQuality: String?
    ) async
    func refreshPeriodData(days: Int) async -> Bool
}

/// 周期视图模型 作为视图模型层里的界面状态管理入口。
/// 负责界面状态管理与业务编排。
@MainActor
@Observable
final class PeriodViewModel {
    enum StructuredEventGroup: String, CaseIterable, Identifiable {
        case testResults
        case bodySignals

        var id: String { rawValue }

        var title: String {
            switch self {
            case .testResults: return "检测结果"
            case .bodySignals: return "身体与行为"
            }
        }
    }

    struct StructuredEventSummaryItem: Identifiable {
        let id: String
        let title: String
        let value: String
        let dateText: String
        let tint: Color
    }

    private struct DayLogPayload: Sendable {
        let date: Date
        let flowLevel: Int
        let painLevel: Int
        let moodLevel: Int
        let hasSexualActivity: Bool?
        let hasIntermenstrualBleeding: Bool?
        let pregnancyTestResult: String?
        let ovulationTestResult: String?
        let cervicalMucusQuality: String?
        let note: String?
    }

    var summary: PeriodSummary?
    var isLoading: Bool = false
    var isSubmitting: Bool = false
    var errorMessage: String?
    var selectedLogDate: Date = Date()
    var flowLevel: Int = 0
    var painLevel: Int = 0
    var moodLevel: Int = 0
    var hasSexualActivity: Bool = false
    var hasIntermenstrualBleeding: Bool = false
    var pregnancyTestResult: String = ""
    var ovulationTestResult: String = ""
    var cervicalMucusQuality: String = ""
    var note: String = ""
    var femaleWellnessState: FemaleWellnessState = .steady
    var selectedSymptoms: Set<FemaleSymptom> = []
    var basalBodyTemperatureText: String = ""
    var cycleStartDate: Date = Date()
    var cycleEndDate: Date = Date()
    var hasCycleEndDate: Bool = false
    var cycleTrainingRhythmPlan: CycleTrainingRhythmPlan?

    private let healthSync: PeriodHealthSyncing
    private let rhythmEngine = CycleStressTrainingEngine()

    init(healthSync: PeriodHealthSyncing? = nil) {
        self.healthSync = healthSync ?? HealthKitManager.shared
    }

    func reload(days: Int = 90) {
        isLoading = true
        errorMessage = nil
        applyLocalSummary(days: days)

        Task { [weak self] in
            guard let self else { return }
            // 页面加载只读取已授权的数据，不主动触发系统健康权限弹窗。
            // 首次授权必须由用户在健康权限入口中手动点击发起。
            _ = await healthSync.refreshPeriodData(days: max(days, 365))
            await MainActor.run {
                self.applyLocalSummary(days: days)
                self.isLoading = false
            }
        }
    }

    func startCycle() {
        guard !isSubmitting else { return }
        isSubmitting = true
        PeriodStore.shared.startCycle(startDate: cycleStartDate)
        applyLocalSummary(days: 90)
        let syncStartDate = cycleStartDate
        let logs = summary?.dayLogs ?? []
        Task {
            await healthSync.syncCycle(startDate: syncStartDate, endDate: nil)
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: syncStartDate)
            let endDay = calendar.startOfDay(for: Date())
            for log in logs {
                guard let dateStr = log.date,
                      let date = Self.dayFormatter.date(from: dateStr),
                      date >= startDay,
                      date <= endDay else {
                    continue
                }
                let flow = log.flowLevel ?? 0
                if flow > 0 {
                    await healthSync.syncFlow(
                        date: date,
                        flowLevel: flow,
                        isCycleStart: calendar.isDate(date, inSameDayAs: syncStartDate)
                    )
                }
            }
        }
        // 本地优先：无自建后端，本地保存 + HealthKit 同步后即完成。
        isSubmitting = false
        reload()
    }

    func endCycle() {
        guard !isSubmitting else { return }
        isSubmitting = true
        PeriodStore.shared.endCycle(endDate: cycleEndDate)
        applyLocalSummary(days: 90)
        let syncStartDate = cycleStartDate
        let syncEndDate = cycleEndDate
        let logs = summary?.dayLogs ?? []
        Task {
            await healthSync.syncCycle(startDate: syncStartDate, endDate: syncEndDate)
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: syncStartDate)
            let endDay = calendar.startOfDay(for: syncEndDate)
            for log in logs {
                guard let dateStr = log.date,
                      let date = Self.dayFormatter.date(from: dateStr),
                      date >= startDay,
                      date <= endDay else {
                    continue
                }
                let flow = log.flowLevel ?? 0
                if flow > 0 {
                    await healthSync.syncFlow(
                        date: date,
                        flowLevel: flow,
                        isCycleStart: calendar.isDate(date, inSameDayAs: syncStartDate)
                    )
                }
            }
        }
        // 本地优先：无自建后端，本地保存 + HealthKit 同步后即完成。
        isSubmitting = false
        reload()
    }

    func updateCycle() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let existingCycleId = summary?.current?.cycleId
        let localCycleId: Int64 = existingCycleId ?? PeriodStore.shared.startCycle(startDate: cycleStartDate)
        PeriodStore.shared.updateCycle(
            cycleId: localCycleId,
            startDate: cycleStartDate,
            endDate: hasCycleEndDate ? cycleEndDate : nil
        )
        applyLocalSummary(days: 90)
        let syncStartDate = cycleStartDate
        let syncEndDate = hasCycleEndDate ? cycleEndDate : nil
        let logs = summary?.dayLogs ?? []
        Task {
            await healthSync.syncCycle(startDate: syncStartDate, endDate: syncEndDate)
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: syncStartDate)
            let endDay = calendar.startOfDay(for: syncEndDate ?? Date())
            for log in logs {
                guard let dateStr = log.date,
                      let date = Self.dayFormatter.date(from: dateStr),
                      date >= startDay,
                      date <= endDay else {
                    continue
                }
                let flow = log.flowLevel ?? 0
                if flow > 0 {
                    await healthSync.syncFlow(
                        date: date,
                        flowLevel: flow,
                        isCycleStart: calendar.isDate(date, inSameDayAs: syncStartDate)
                    )
                }
            }
        }
        // 本地优先：无自建后端，本地保存 + HealthKit 同步后即完成。
        isSubmitting = false
        reload()
    }

    func saveDayLog() {
        guard !isSubmitting else { return }
        let payload = makeDayLogPayloadFromForm()
        isSubmitting = true
        persistDayLogLocally(payload)
        syncDayLogToHealth(
            payload,
            shouldSyncCycle: false,
            isCycleStart: isCycleStartDate(payload.date)
        )
        // 本地优先：无自建后端，本地保存 + HealthKit 同步后即完成。
        isSubmitting = false
        reload()
    }

    /// 记录今天最常见的经期状态，同时不改变时间线中选中的历史日期。
    @discardableResult
    func quickRecordToday(_ preset: PeriodQuickRecordPreset) -> Bool {
        guard !isSubmitting else { return false }

        let today = Calendar.current.startOfDay(for: Date())
        let dateString = Self.dayFormatter.string(from: today)
        let existingLog = PeriodStore.shared
            .summary(days: 30)
            .dayLogs?
            .first(where: { $0.date == dateString })
        let values = preset.resolvedValues(
            existingFlowLevel: existingLog?.flowLevel ?? 0,
            existingPainLevel: existingLog?.painLevel ?? 0,
            existingMoodLevel: existingLog?.moodLevel ?? 0,
            hasExistingLog: existingLog != nil
        )
        let cycleResult = preset.isMenstruating
            ? PeriodStore.shared.ensureCycleStarted(on: today)
            : nil
        let payload = DayLogPayload(
            date: today,
            flowLevel: values.flowLevel,
            painLevel: values.painLevel,
            moodLevel: values.moodLevel,
            hasSexualActivity: existingLog?.hasSexualActivity,
            hasIntermenstrualBleeding: existingLog?.hasIntermenstrualBleeding,
            pregnancyTestResult: existingLog?.pregnancyTestResult,
            ovulationTestResult: existingLog?.ovulationTestResult,
            cervicalMucusQuality: existingLog?.cervicalMucusQuality,
            note: existingLog?.note
        )

        isSubmitting = true
        errorMessage = nil
        persistDayLogLocally(payload)
        syncDayLogToHealth(
            payload,
            shouldSyncCycle: cycleResult?.didCreate == true,
            isCycleStart: preset.isMenstruating && isCycleStartDate(today)
        )

        // 本地优先：无自建后端，本地保存 + HealthKit 同步后即完成。
        isSubmitting = false
        reload()
        return true
    }

    private func makeDayLogPayloadFromForm() -> DayLogPayload {
        DayLogPayload(
            date: selectedLogDate,
            flowLevel: flowLevel,
            painLevel: painLevel,
            moodLevel: moodLevel,
            hasSexualActivity: hasSexualActivity ? true : nil,
            hasIntermenstrualBleeding: hasIntermenstrualBleeding ? true : nil,
            pregnancyTestResult: pregnancyTestResult.isEmpty ? nil : pregnancyTestResult,
            ovulationTestResult: ovulationTestResult.isEmpty ? nil : ovulationTestResult,
            cervicalMucusQuality: cervicalMucusQuality.isEmpty ? nil : cervicalMucusQuality,
            note: composeStructuredNote()
        )
    }

    private func persistDayLogLocally(_ payload: DayLogPayload) {
        PeriodStore.shared.upsertDayLog(
            date: payload.date,
            flowLevel: payload.flowLevel,
            painLevel: payload.painLevel,
            moodLevel: payload.moodLevel,
            hasSexualActivity: payload.hasSexualActivity,
            hasIntermenstrualBleeding: payload.hasIntermenstrualBleeding,
            pregnancyTestResult: payload.pregnancyTestResult,
            ovulationTestResult: payload.ovulationTestResult,
            cervicalMucusQuality: payload.cervicalMucusQuality,
            note: payload.note
        )
        applyLocalSummary(days: 90)
    }

    private func syncDayLogToHealth(
        _ payload: DayLogPayload,
        shouldSyncCycle: Bool,
        isCycleStart: Bool
    ) {
        Task {
            if shouldSyncCycle {
                await healthSync.syncCycle(startDate: payload.date, endDate: nil)
            }
            await healthSync.syncFlow(
                date: payload.date,
                flowLevel: payload.flowLevel,
                isCycleStart: isCycleStart
            )
            await healthSync.syncSymptoms(
                date: payload.date,
                painLevel: payload.painLevel,
                moodLevel: payload.moodLevel
            )
            await healthSync.syncReproductiveEvents(
                date: payload.date,
                hasSexualActivity: payload.hasSexualActivity == true,
                hasIntermenstrualBleeding: payload.hasIntermenstrualBleeding == true,
                pregnancyTestResult: payload.pregnancyTestResult,
                ovulationTestResult: payload.ovulationTestResult,
                cervicalMucusQuality: payload.cervicalMucusQuality
            )
        }
    }

    private func isCycleStartDate(_ date: Date) -> Bool {
        let dateString = Self.dayFormatter.string(from: date)
        if summary?.current?.startDate == dateString {
            return true
        }
        return summary?.cycles?.contains(where: { $0.startDate == dateString }) == true
    }

    func selectLog(date: Date) {
        selectedLogDate = date
        let dateString = Self.dayFormatter.string(from: date)
        if let log = summary?.dayLogs?.first(where: { $0.date == dateString }) {
            flowLevel = log.flowLevel ?? 0
            painLevel = log.painLevel ?? 0
            moodLevel = log.moodLevel ?? 0
            let structuredPayload = structuredPayload(from: log.note)
            hasSexualActivity = log.hasSexualActivity ?? false
            hasIntermenstrualBleeding = log.hasIntermenstrualBleeding ?? false
            pregnancyTestResult = log.pregnancyTestResult ?? ""
            ovulationTestResult = log.ovulationTestResult ?? ""
            cervicalMucusQuality = log.cervicalMucusQuality ?? ""
            femaleWellnessState = structuredPayload.femaleWellnessState ?? .steady
            selectedSymptoms = Set(structuredPayload.symptoms)
            basalBodyTemperatureText = structuredPayload.basalBodyTemperature ?? ""
            note = structuredPayload.residualNote ?? ""
        } else {
            flowLevel = 0
            painLevel = 0
            moodLevel = 0
            hasSexualActivity = false
            hasIntermenstrualBleeding = false
            pregnancyTestResult = ""
            ovulationTestResult = ""
            cervicalMucusQuality = ""
            femaleWellnessState = .steady
            selectedSymptoms = []
            basalBodyTemperatureText = ""
            note = ""
        }
    }

    var phaseTitle: String {
        switch summary?.current?.phase {
        case "MENSTRUATION":
            return "经期"
        case "FOLLICULAR":
            return "卵泡期"
        case "OVULATION":
            return "排卵期"
        case "LUTEAL":
            return "黄体期"
        default:
            return String(localized: "周期")
        }
    }

    var cycleDayText: String {
        if let day = summary?.current?.dayIndex {
            return String(localized: "第\(day)天")
        }
        return "--"
    }

    var clinicalHeadline: String {
        switch phaseTitle {
        case "经期":
            return String(localized: "当前处在经期阶段")
        case "排卵期":
            return String(localized: "当前接近排卵窗口")
        case "黄体期":
            return String(localized: "当前处在黄体期")
        case "卵泡期":
            return String(localized: "当前处在卵泡期")
        default:
            return String(localized: "当前周期节律待进一步确认")
        }
    }

    var clinicalSubheadline: String {
        if shouldShowHealthPredictions, let hint = predictionHint {
            return hint
        }
        if isHealthConnected {
            return String(localized: "近期记录还在积累，继续补充后会更容易判断节律与下一关键时间。")
        }
        return String(localized: "连接健康 App 或继续补充记录后，这里会形成更完整的阶段判断。")
    }

    var predictionHint: String? {
        guard shouldShowHealthPredictions else { return nil }
        guard let p = summary?.predictions else { return nil }
        guard let nextStart = p.nextPeriodStart else { return nil }
        guard let fertileStart = p.fertileStart, let fertileEnd = p.fertileEnd else {
            return String(localized: "下次预计 \(displayDay(nextStart))")
        }
        return String(localized: "易孕期 \(displayDay(fertileStart))-\(displayDay(fertileEnd)) · 下次预计 \(displayDay(nextStart))")
    }

    var predictionSourceNote: String? {
        guard shouldShowHealthPredictions else {
            return String(localized: "连接健康 App 后，这里会补足周期节律、窗口预测和更完整的记录参考。")
        }
        return String(localized: "当前周期判断与预测窗口主要基于健康 App 的周期记录整理得出，可作为日常节律参考。")
    }

    var isHealthConnected: Bool {
        // HealthKit 不公开经期读取权限；整体连接状态由统一授权流程与实际数据管线判断。
        HealthAuthorizationCoordinator.shared.phase.isAuthorizedLike
    }

    private var canWritePeriodData: Bool {
        HealthKitManager.shared.authorizationStatus(for: .menstrualFlow) == .sharingAuthorized
    }

    var healthStatusText: String {
        if isHealthConnected {
            return String(localized: "已连接")
        }
        return String(localized: "待连接")
    }

    var healthStatusDetail: String {
        if isHealthConnected {
            if canWritePeriodData {
                return String(localized: "会优先读取健康 App 中的周期记录，并把你在这里补充的开始日、结束日和当天状态同步回去。")
            }
            return String(localized: "会尝试读取健康 App 中的周期记录；当前未开启写入权限，本地补充的状态不会写回健康 App。")
        }
        return String(localized: "连接健康 App 后，这里会优先同步周期记录，并在你保存当天状态时形成更完整的节律参考。")
    }

    var predictionSourceBadgeText: String {
        isHealthConnected ? "健康 App" : "待同步"
    }

    var cycleLengthText: String {
        guard shouldShowHealthPredictions,
              let value = summary?.predictions?.cycleLength,
              value > 0 else { return "—" }
        return String(localized: "\(value)天")
    }

    var periodLengthText: String {
        guard shouldShowHealthPredictions,
              let value = summary?.predictions?.periodLength,
              value > 0 else { return "—" }
        return String(localized: "\(value)天")
    }

    var latestCycleRangeText: String {
        guard let cycle = recentCycles.first,
              let start = cycle.startDate else { return "暂无周期" }
        let startText = displayDay(start)
        if let end = cycle.endDate {
            return "\(startText) - \(displayDay(end))"
        }
        return String(localized: "\(startText) 开始")
    }

    var femaleStateSummaryText: String {
        if flowLevel > 0 {
            return String(localized: "经期记录中")
        }
        let symptomCount = selectedSymptoms.count
        if symptomCount > 0 {
            return String(localized: "\(femaleWellnessState.title) · \(symptomCount)项症状")
        }
        if !basalBodyTemperatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "\(femaleWellnessState.title) · 体温已记")
        }
        return femaleWellnessState.title
    }

    var symptomSummaryText: String {
        if selectedSymptoms.isEmpty {
            return painLevel > 0 || moodLevel > 0 ? "痛经 \(painLevel) / 情绪 \(moodLevel)" : "添加"
        }
        let titles = selectedSymptoms
            .sorted { $0.title < $1.title }
            .prefix(2)
            .map(\.title)
        let suffix = selectedSymptoms.count > 2 ? " 等\(selectedSymptoms.count)项" : ""
        return titles.joined(separator: "、") + suffix
    }

    var basalBodyTemperatureSummaryText: String {
        let trimmed = basalBodyTemperatureText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "添加" : trimmed
    }

    var cycleLifestyleRhythmSuggestions: [FemaleDailyRhythmSuggestion] {
        let phase = phaseTitle
        let stressHigh = femaleWellnessState == .stressed || moodLevel >= 3
        let lowEnergy = femaleWellnessState == .lowEnergy || selectedSymptoms.contains(.fatigue)
        let sensitive = femaleWellnessState == .bloated || femaleWellnessState == .sensitive

        switch phase {
        case "经期":
            return [
                .init(id: "rest", title: "作息放缓", detail: "把核心安排收敛到 1-2 件，给身体留恢复空档。"),
                .init(id: "warm", title: "保暖补水", detail: "优先温热饮水、规律进食，减少空腹和熬夜。"),
                .init(id: "move", title: "轻量活动", detail: "选择散步、拉伸或低冲击训练，避免硬扛强度。")
            ]
        case "排卵期":
            return [
                .init(id: "output", title: "安排输出日", detail: "把需要表达、社交或训练配合的任务放在白天完成。"),
                .init(id: "hydrate", title: "补水与蛋白", detail: "训练后尽快补水和蛋白，减少晚间透支。"),
                .init(id: "observe", title: "关注信号", detail: "若出现腹痛或分泌物变化，记下来而不是硬撑。")
            ]
        case "黄体期":
            return [
                .init(id: "stable", title: "节奏求稳", detail: "把训练和工作负荷维持在可持续区间，不做突击。"),
                .init(id: "carb", title: "规律进食", detail: "三餐稳定，下午补一点复合碳水可缓解能量下滑。"),
                .init(id: "sleep", title: "提前收尾", detail: "把睡前一小时留给放松，帮助黄体期恢复。")
            ]
        case "卵泡期":
            return [
                .init(id: "plan", title: "安排推进", detail: "适合把本周需要推进的计划和训练节奏提前排好。"),
                .init(id: "build", title: "逐步加量", detail: "如果精力稳定，可把训练强度循序加回来。"),
                .init(id: "track", title: "持续观察", detail: "开始记录状态、体温和睡眠，方便后半周期对照。")
            ]
        default:
            var items = [
                FemaleDailyRhythmSuggestion(id: "record", title: "持续记录", detail: "先把状态、症状和睡眠补齐，系统会更快识别节律。"),
                FemaleDailyRhythmSuggestion(id: "steady", title: "先稳住作息", detail: "优先固定起床、进食和睡眠时间。")
            ]
            if stressHigh || lowEnergy || sensitive {
                items.append(.init(id: "light", title: "降低负荷", detail: "今天更适合轻量安排，先让身体回稳。"))
            }
            return items
        }
    }

    var femaleRecoverySuggestions: [String] {
        var suggestions: [String] = []

        if painLevel >= 3 || selectedSymptoms.contains(.cramps) {
            suggestions.append("今天把恢复重点放在腹部放松和低刺激活动，避免高强度训练。")
        }
        if femaleWellnessState == .bloated || selectedSymptoms.contains(.bloating) || selectedSymptoms.contains(.constipation) {
            suggestions.append("腹胀明显时优先温热饮食、步行和规律补水，减少过咸和过油。")
        }
        if femaleWellnessState == .stressed || moodLevel >= 3 || selectedSymptoms.contains(.insomnia) {
            suggestions.append("压力偏高时把睡前 30 分钟留给降噪放松，减少晚间信息刺激。")
        }
        if femaleWellnessState == .lowEnergy || selectedSymptoms.contains(.fatigue) {
            suggestions.append("精力偏低时把关键任务前置，训练维持恢复型或轻训练即可。")
        }
        if phaseTitle == "黄体期" && suggestions.isEmpty {
            suggestions.append("黄体期更适合稳节奏恢复，今天不必追求强度峰值。")
        }
        if phaseTitle == "排卵期" && suggestions.isEmpty {
            suggestions.append("排卵窗口期状态不错也要留出恢复餐和补水，避免晚间透支。")
        }
        if suggestions.isEmpty {
            suggestions.append("今天整体状态平稳，继续保持规律睡眠、进食和轻度活动。")
        }

        return Array(suggestions.prefix(3))
    }

    var phaseObservationSummary: String {
        let phase = phaseTitle
        switch phase {
        case "经期":
            return String(localized: "这几天更适合观察出血量、腹痛变化和整体恢复感。")
        case "卵泡期":
            return String(localized: "卵泡期适合记录精力、皮肤和训练恢复，观察状态是否逐步抬升。")
        case "排卵期":
            return String(localized: "排卵窗口期重点看分泌物、腹部感受和训练后的恢复速度。")
        case "黄体期":
            return String(localized: "黄体期更值得关注情绪起伏、睡眠质量和腹胀水肿变化。")
        default:
            return String(localized: "继续补充日常状态记录后，这里会形成更明确的阶段观察重点。")
        }
    }

    var recentLogs: [PeriodDayLog] {
        (summary?.dayLogs ?? [])
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
            .prefix(3)
            .map { $0 }
    }

    var recentCycles: [PeriodCycle] {
        (summary?.cycles ?? [])
            .sorted { ($0.startDate ?? "") > ($1.startDate ?? "") }
            .prefix(3)
            .map { $0 }
    }

    func flowText(for value: Int?) -> String {
        switch value ?? 0 {
        case 0: return "未记"
        case 1: return "少量"
        case 2: return "中等"
        case 3: return "偏多"
        case 4...: return "很多"
        default: return "未记"
        }
    }

    var shouldShowHealthPredictions: Bool {
        isHealthConnected && summary?.predictions?.source == PeriodStore.healthPredictionSource
    }

    func displayDay(_ isoDate: String) -> String {
        guard let date = Self.dayFormatter.date(from: isoDate) else { return isoDate }
        return ChineseDateText.writtenMonthDay(date)
    }

    func eventTags(for log: PeriodDayLog) -> [PeriodEventTag] {
        structuredEventTags(for: log)
    }

    func residualNote(for log: PeriodDayLog) -> String? {
        structuredPayload(from: log.note).residualNote
    }

    private func eventTagsAndResidualNote(from note: String?) -> (tags: [PeriodEventTag], residualNote: String?) {
        guard let note else { return ([], nil) }
        let parts = note
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return ([], nil) }

        var tags: [PeriodEventTag] = []
        var residual: [String] = []

        for part in parts {
            if let tag = eventTag(from: part) {
                if !tags.contains(tag) {
                    tags.append(tag)
                }
            } else {
                residual.append(part)
            }
        }

        let residualNote = residual.isEmpty ? nil : residual.joined(separator: " · ")
        return (tags, residualNote)
    }

    private func structuredEventTags(for log: PeriodDayLog) -> [PeriodEventTag] {
        var tags: [PeriodEventTag] = []

        if log.hasSexualActivity == true {
            tags.append(PeriodEventTag(title: "性行为", style: .fertile))
        }
        if log.hasIntermenstrualBleeding == true {
            tags.append(PeriodEventTag(title: "点滴出血", style: .alert))
        }

        let pregnancy = log.pregnancyTestResult
        if let pregnancy {
            let title = pregnancyTestDisplayText(for: pregnancy)
            if !title.isEmpty {
                tags.append(PeriodEventTag(title: title, style: pregnancy == "positive" ? .positive : .neutral))
            }
        }

        let ovulation = log.ovulationTestResult
        if let ovulation {
            let title = ovulationTestDisplayText(for: ovulation)
            if !title.isEmpty {
                let style: PeriodEventTag.Style = ovulation == "negative" || ovulation == "inconclusive" ? .neutral : .fertile
                tags.append(PeriodEventTag(title: title, style: style))
            }
        }

        let mucus = log.cervicalMucusQuality
        if let mucus {
            let title = cervicalMucusDisplayText(for: mucus)
            if !title.isEmpty {
                tags.append(PeriodEventTag(title: title, style: .fertile))
            }
        }

        var unique: [PeriodEventTag] = []
        for tag in tags where !unique.contains(tag) {
            unique.append(tag)
        }
        return unique
    }

    private struct StructuredNotePayload {
        var femaleWellnessState: FemaleWellnessState?
        var symptoms: [FemaleSymptom] = []
        var basalBodyTemperature: String?
        var residualNote: String?
    }

    func toggleSymptom(_ symptom: FemaleSymptom) {
        if selectedSymptoms.contains(symptom) {
            selectedSymptoms.remove(symptom)
        } else {
            selectedSymptoms.insert(symptom)
        }
    }

    private func structuredPayload(from note: String?) -> StructuredNotePayload {
        guard let note else { return StructuredNotePayload() }
        let parts = note
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var payload = StructuredNotePayload()
        var residual: [String] = []

        for part in parts {
            if let stateRaw = part.value(afterPrefix: "BB_STATE="),
               let state = FemaleWellnessState(rawValue: stateRaw) {
                payload.femaleWellnessState = state
                continue
            }
            if let symptomRaw = part.value(afterPrefix: "BB_SYMPTOMS=") {
                payload.symptoms = symptomRaw
                    .split(separator: ",")
                    .compactMap { FemaleSymptom(rawValue: String($0)) }
                continue
            }
            if let temperature = part.value(afterPrefix: "BB_BBT=") {
                payload.basalBodyTemperature = temperature
                continue
            }
            if eventTag(from: part) != nil || isLegacyEventText(part) {
                continue
            }
            residual.append(part)
        }

        payload.residualNote = residual.isEmpty ? nil : residual.joined(separator: " · ")
        return payload
    }

    private func composeStructuredNote() -> String? {
        var components: [String] = []
        components.append("BB_STATE=\(femaleWellnessState.rawValue)")
        if !selectedSymptoms.isEmpty {
            let raw = selectedSymptoms
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
            components.append("BB_SYMPTOMS=\(raw)")
        }

        let trimmedTemperature = basalBodyTemperatureText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTemperature.isEmpty {
            components.append("BB_BBT=\(trimmedTemperature)")
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            components.append(trimmedNote)
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private func isLegacyEventText(_ text: String) -> Bool {
        switch text {
        case "性行为",
             "点滴出血",
             "妊娠测试阴性",
             "妊娠测试阳性",
             "妊娠测试待确认",
             "排卵测试阴性",
             "排卵试纸阴性",
             "排卵测试阳性",
             "雌激素上升提示",
             "排卵峰值提示",
             "排卵测试待确认",
             "排卵试纸待确认",
             "宫颈黏液偏干",
             "宫颈黏液黏稠",
             "宫颈黏液乳霜样",
             "宫颈黏液水样",
             "宫颈黏液蛋清样":
            return true
        default:
            return false
        }
    }

    private func eventTag(from text: String) -> PeriodEventTag? {
        switch text {
        case "性行为":
            return PeriodEventTag(title: text, style: .fertile)
        case "点滴出血":
            return PeriodEventTag(title: text, style: .alert)
        case "妊娠测试阳性":
            return PeriodEventTag(title: text, style: .positive)
        case "妊娠测试阴性", "妊娠测试待确认":
            return PeriodEventTag(title: text, style: .neutral)
        case "排卵峰值提示", "雌激素上升提示":
            return PeriodEventTag(title: text, style: .fertile)
        case "排卵试纸阴性", "排卵试纸待确认":
            return PeriodEventTag(title: text, style: .neutral)
        case "宫颈黏液偏干", "宫颈黏液黏稠", "宫颈黏液乳霜样", "宫颈黏液水样", "宫颈黏液蛋清样":
            return PeriodEventTag(title: text, style: .fertile)
        default:
            return nil
        }
    }

    var currentPhaseDisplayText: String { phaseTitle }
    var currentCycleDayText: String { cycleDayText }
    var currentTrainingRhythmSummaryText: String {
        cycleTrainingRhythmPlan?.todayReason ?? "继续记录周期、睡眠和训练后，这里会更稳定地判断今天适合的节奏。"
    }

    func pregnancyTestDisplayText(for value: String) -> String {
        switch value {
        case "negative": return "妊娠测试阴性"
        case "positive": return "妊娠测试阳性"
        case "inconclusive": return "妊娠测试待确认"
        default: return "未记录"
        }
    }

    func ovulationTestDisplayText(for value: String) -> String {
        switch value {
        case "negative": return "排卵测试阴性"
        case "positive": return "排卵测试阳性"
        case "peak": return "排卵峰值提示"
        case "inconclusive": return "排卵测试待确认"
        default: return "未记录"
        }
    }

    func cervicalMucusDisplayText(for value: String) -> String {
        switch value {
        case "dry": return "宫颈黏液偏干"
        case "sticky": return "宫颈黏液黏稠"
        case "creamy": return "宫颈黏液乳霜样"
        case "watery": return "宫颈黏液水样"
        case "eggWhite": return "宫颈黏液蛋清样"
        default: return "未记录"
        }
    }

    func latestStructuredEventSummary(for group: StructuredEventGroup) -> [StructuredEventSummaryItem] {
        let logs = (summary?.dayLogs ?? []).sorted { ($0.date ?? "") > ($1.date ?? "") }
        switch group {
        case .testResults:
            return [
                latestPregnancyTestItem(from: logs),
                latestOvulationTestItem(from: logs)
            ]
        case .bodySignals:
            return [
                latestSexualActivityItem(from: logs),
                latestSpottingItem(from: logs),
                latestCervicalMucusItem(from: logs)
            ]
        }
    }

    private func latestPregnancyTestItem(from logs: [PeriodDayLog]) -> StructuredEventSummaryItem {
        if let log = logs.first(where: { $0.pregnancyTestResult != nil }) {
            let value = log.pregnancyTestResult ?? ""
            return StructuredEventSummaryItem(
                id: "pregnancy",
                title: "妊娠测试",
                value: pregnancyTestDisplayText(for: value),
                dateText: log.date.map(displayDay) ?? "暂无日期",
                tint: value == "positive" ? Color(hex: "2D8C63") : Color(hex: "6D7486")
            )
        }
        return StructuredEventSummaryItem(id: "pregnancy", title: "妊娠测试", value: "暂无记录", dateText: "等待记录", tint: Color(hex: "6D7486"))
    }

    private func latestOvulationTestItem(from logs: [PeriodDayLog]) -> StructuredEventSummaryItem {
        if let log = logs.first(where: { $0.ovulationTestResult != nil }) {
            let value = log.ovulationTestResult ?? ""
            return StructuredEventSummaryItem(
                id: "ovulation",
                title: "排卵测试",
                value: ovulationTestDisplayText(for: value),
                dateText: log.date.map(displayDay) ?? "暂无日期",
                tint: value == "negative" || value == "inconclusive" ? Color(hex: "6D7486") : Color(hex: "7A8FAE")
            )
        }
        return StructuredEventSummaryItem(id: "ovulation", title: "排卵测试", value: "暂无记录", dateText: "等待记录", tint: Color(hex: "6D7486"))
    }

    private func latestSexualActivityItem(from logs: [PeriodDayLog]) -> StructuredEventSummaryItem {
        if let log = logs.first(where: { $0.hasSexualActivity == true }) {
            return StructuredEventSummaryItem(id: "sexual-activity", title: "性行为", value: "已记录", dateText: log.date.map(displayDay) ?? "暂无日期", tint: Color(hex: "7A8FAE"))
        }
        return StructuredEventSummaryItem(id: "sexual-activity", title: "性行为", value: "暂无记录", dateText: "等待记录", tint: Color(hex: "6D7486"))
    }

    private func latestSpottingItem(from logs: [PeriodDayLog]) -> StructuredEventSummaryItem {
        if let log = logs.first(where: { $0.hasIntermenstrualBleeding == true }) {
            return StructuredEventSummaryItem(id: "spotting", title: "点滴出血", value: "已记录", dateText: log.date.map(displayDay) ?? "暂无日期", tint: Color(hex: "C97C7A"))
        }
        return StructuredEventSummaryItem(id: "spotting", title: "点滴出血", value: "暂无记录", dateText: "等待记录", tint: Color(hex: "6D7486"))
    }

    private func latestCervicalMucusItem(from logs: [PeriodDayLog]) -> StructuredEventSummaryItem {
        if let log = logs.first(where: { $0.cervicalMucusQuality != nil }) {
            let value = log.cervicalMucusQuality ?? ""
            return StructuredEventSummaryItem(
                id: "cervical-mucus",
                title: "宫颈黏液",
                value: cervicalMucusDisplayText(for: value),
                dateText: log.date.map(displayDay) ?? "暂无日期",
                tint: Color(hex: "7A8FAE")
            )
        }
        return StructuredEventSummaryItem(id: "cervical-mucus", title: "宫颈黏液", value: "暂无记录", dateText: "等待记录", tint: Color(hex: "6D7486"))
    }

    private func hydrateFormFromSummary() {
        guard let current = summary?.current else { return }
        if let startStr = current.startDate, let d = Self.dayFormatter.date(from: startStr) {
            cycleStartDate = d
        } else {
            cycleStartDate = Date()
        }
        if let endStr = current.endDate, let d = Self.dayFormatter.date(from: endStr) {
            cycleEndDate = d
            hasCycleEndDate = true
        } else {
            cycleEndDate = Date()
            hasCycleEndDate = false
        }
        selectLog(date: selectedLogDate)
    }

    private func applyLocalSummary(days: Int) {
        let data = PeriodStore.shared.summary(days: days)
        summary = data
        cycleTrainingRhythmPlan = buildCycleTrainingRhythmPlan(from: data)
        persistSummaryToSharedStore(data)
        hydrateFormFromSummary()
    }

    private func buildCycleTrainingRhythmPlan(from summary: PeriodSummary) -> CycleTrainingRhythmPlan? {
        let phase = CyclePhaseKind(phaseRawValue: summary.current?.phase)
        guard phase != .unknown else { return nil }

        let currentLog = summary.dayLogs?
            .sorted(by: { ($0.date ?? "") > ($1.date ?? "") })
            .first
        let actionRecord = ActionRecordStore.shared.record(for: Date())
        let recentAvgHrv = UserDefaults.standard.object(forKey: "dashboard_recent_avg_hrv") as? Double

        return rhythmEngine.makePlan(
            input: .init(
                phase: phase,
                cycleDay: summary.current?.dayIndex,
                cycleLength: summary.predictions?.cycleLength,
                flowLevel: currentLog?.flowLevel,
                painLevel: currentLog?.painLevel,
                moodLevel: currentLog?.moodLevel,
                stressScore: AppGroupManager.shared.getLatestStress().map { Int($0.rounded()) },
                sleepMinutes: AppGroupManager.shared.getSleepDurationMinutes(),
                sleepScore: AppGroupManager.shared.getSleepScore(),
                sleepGoalMinutes: SleepGoalResolver.goalMinutes(),
                hrv: AppGroupManager.shared.getLatestHRV(),
                recentAvgHrv: recentAvgHrv,
                workoutMinutes: actionRecord.manualWorkoutMinutes > 0 ? actionRecord.manualWorkoutMinutes : nil,
                workoutEffort: actionRecord.manualWorkoutEffort,
                vo2Max: AppGroupManager.shared.getVO2MaxValue()
            )
        )
    }

    private func persistSummaryToSharedStore(_ summary: PeriodSummary) {
        AppGroupManager.shared.savePeriodSummary(
            phase: summary.current?.phase,
            cycleDay: summary.current?.dayIndex,
            isFertile: summary.current?.isFertile,
            nextPeriodStart: summary.predictions?.nextPeriodStart,
            fertileStart: summary.predictions?.fertileStart,
            fertileEnd: summary.predictions?.fertileEnd,
            predictionSource: summary.predictions?.source
        )
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private extension String {
    func value(afterPrefix prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
