/// Period Store 负责经期相关数据的存储与读取，用于支撑周期记录、分析和界面展示。
import Foundation
import SwiftData

struct PeriodCycleStartResult: Equatable, Sendable {
    let cycleID: Int64
    let didCreate: Bool
}

/// 周期存储器 作为生理周期能力层里的数据读写与状态保存入口。
/// 负责经期数据存储与读取。
final class PeriodStore {
    static let shared = PeriodStore()
    static let healthPredictionSource = "APPLE_HEALTH_RECORDS"
    static let localPredictionSource = "LOCAL_RECORDS"

    private let key = "periodStore.v1"
    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let domain = "period"
    private let kind = "state"

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        migrateLegacyDataIfNeeded()
        migrateLegacyEventNotesIfNeeded()
    }

    func summary(days: Int = 90, referenceDate: Date = Date()) -> PeriodSummary {
        let windowDays = max(1, days)
        let today = Self.normalizeDate(referenceDate)
        let windowStart = Calendar.current.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        let state = loadState()
        let cycles = resolvedCycles(from: state).sorted { $0.startDate > $1.startDate }
        let dayLogs = resolvedDayLogs(from: state).filter { $0.date >= windowStart && $0.date <= today }.sorted { $0.date < $1.date }

        let cycleLength = resolveCycleLength(cycles: cycles)
        let periodLength = resolvePeriodLength(cycles: cycles)

        var currentCycleId: Int64?
        var currentStart = cycles.first?.startDate ?? today
        var currentEnd: Date?
        var isPredicted = true

        for cycle in cycles {
            let start = cycle.startDate
            let end = cycle.endDate
            if let end, today >= start && today <= end {
                currentCycleId = cycle.id
                currentStart = start
                currentEnd = end
                isPredicted = false
                break
            }
            if end == nil, today >= start {
                currentCycleId = cycle.id
                currentStart = start
                currentEnd = nil
                isPredicted = false
                break
            }
        }

        if today >= currentStart {
            let diff = Self.daysBetween(currentStart, today)
            if diff >= cycleLength {
                let k = diff / cycleLength
                currentStart = Self.addDays(currentStart, k * cycleLength)
                currentEnd = nil
                currentCycleId = nil
                isPredicted = true
            }
        } else {
            currentStart = today
            currentEnd = nil
            currentCycleId = nil
            isPredicted = true
        }

        let dayIndex = Self.daysBetween(currentStart, today) + 1
        let ovulationIndex = max(1, cycleLength - 14)
        let fertileStartIndex = max(1, ovulationIndex - 5)
        let fertileEndIndex = min(cycleLength, ovulationIndex + 1)

        let phase: String
        if dayIndex <= periodLength {
            phase = "MENSTRUATION"
        } else if dayIndex == ovulationIndex {
            phase = "OVULATION"
        } else if dayIndex < ovulationIndex {
            phase = "FOLLICULAR"
        } else {
            phase = "LUTEAL"
        }
        let isFertile = dayIndex >= fertileStartIndex && dayIndex <= fertileEndIndex

        let current = PeriodCurrent(
            cycleId: currentCycleId,
            startDate: Self.dayFormatter.string(from: currentStart),
            endDate: currentEnd.map(Self.dayFormatter.string(from:)),
            phase: phase,
            dayIndex: dayIndex,
            isFertile: isFertile,
            isPredicted: isPredicted
        )

        let ovulationDate = Self.addDays(currentStart, ovulationIndex - 1)
        let fertileStart = Self.addDays(currentStart, fertileStartIndex - 1)
        let fertileEnd = Self.addDays(currentStart, fertileEndIndex - 1)
        let nextStart = Self.addDays(currentStart, cycleLength)
        let nextEnd = Self.addDays(nextStart, periodLength - 1)

        let predictions = PeriodPredictions(
            cycleLength: cycleLength,
            periodLength: periodLength,
            ovulationDate: Self.dayFormatter.string(from: ovulationDate),
            fertileStart: Self.dayFormatter.string(from: fertileStart),
            fertileEnd: Self.dayFormatter.string(from: fertileEnd),
            nextPeriodStart: Self.dayFormatter.string(from: nextStart),
            nextPeriodEnd: Self.dayFormatter.string(from: nextEnd),
            source: predictionSource(for: state)
        )

        var overlayRanges: [PeriodOverlayRange] = []
        for cycle in cycles {
            let start = cycle.startDate
            let end = cycle.endDate ?? today
            if end < windowStart || start > today {
                continue
            }
            overlayRanges.append(
                PeriodOverlayRange(
                    startDate: Self.dayFormatter.string(from: max(start, windowStart)),
                    endDate: Self.dayFormatter.string(from: min(end, today)),
                    type: "PERIOD"
                )
            )
        }
        overlayRanges.append(PeriodOverlayRange(startDate: Self.dayFormatter.string(from: fertileStart), endDate: Self.dayFormatter.string(from: fertileEnd), type: "FERTILE_WINDOW"))
        overlayRanges.append(PeriodOverlayRange(startDate: Self.dayFormatter.string(from: ovulationDate), endDate: Self.dayFormatter.string(from: ovulationDate), type: "OVULATION"))
        overlayRanges.append(PeriodOverlayRange(startDate: Self.dayFormatter.string(from: nextStart), endDate: Self.dayFormatter.string(from: nextEnd), type: "PREDICTED_PERIOD"))

        let summaryLogs: [PeriodDayLog] = dayLogs.map { log in
            PeriodDayLog(
                idValue: log.id,
                date: Self.dayFormatter.string(from: log.date),
                flowLevel: log.flowLevel,
                painLevel: log.painLevel,
                moodLevel: log.moodLevel,
                hasSexualActivity: log.hasSexualActivity,
                hasIntermenstrualBleeding: log.hasIntermenstrualBleeding,
                pregnancyTestResult: log.pregnancyTestResult,
                ovulationTestResult: log.ovulationTestResult,
                cervicalMucusQuality: log.cervicalMucusQuality,
                note: log.note
            )
        }

        let summaryCycles: [PeriodCycle] = cycles.sorted { $0.startDate < $1.startDate }.map { cycle in
            PeriodCycle(idValue: cycle.id, startDate: Self.dayFormatter.string(from: cycle.startDate), endDate: cycle.endDate.map(Self.dayFormatter.string(from:)))
        }

        return PeriodSummary(
            current: current,
            predictions: predictions,
            overlayRanges: overlayRanges,
            dayLogs: summaryLogs,
            cycles: summaryCycles
        )
    }

    @discardableResult
    func startCycle(startDate: Date = Date()) -> Int64 {
        let normalized = Self.normalizeDate(startDate)
        var state = loadState()
        if let openIndex = state.cycles.firstIndex(where: { $0.endDate == nil }) {
            state.cycles[openIndex].startDate = normalized
            state.updatedAt = Date()
            saveState(state)
            return state.cycles[openIndex].id
        }

        let newId = state.nextCycleId
        state.nextCycleId += 1
        state.cycles.append(LocalCycle(id: newId, startDate: normalized, endDate: nil))
        state.updatedAt = Date()
        saveState(state)
        return newId
    }

    @discardableResult
    func ensureCycleStarted(on date: Date = Date()) -> PeriodCycleStartResult {
        let normalized = Self.normalizeDate(date)
        var state = loadState()
        var didMutateState = false

        let openIndices = state.cycles.indices.filter { state.cycles[$0].endDate == nil }
        if let activeIndex = openIndices
            .filter({ state.cycles[$0].startDate <= normalized })
            .max(by: { state.cycles[$0].startDate < state.cycles[$1].startDate }) {
            let start = state.cycles[activeIndex].startDate
            let age = Self.daysBetween(start, normalized)
            if age < 45 {
                return PeriodCycleStartResult(
                    cycleID: state.cycles[activeIndex].id,
                    didCreate: false
                )
            }

            let dayBeforeNewCycle = Self.addDays(normalized, -1)
            let defaultEnd = Self.addDays(start, 4)
            state.cycles[activeIndex].endDate = max(start, min(defaultEnd, dayBeforeNewCycle))
            didMutateState = true
        }

        if let healthCycle = state.healthCycles
            .filter({ cycle in
                guard cycle.startDate <= normalized else { return false }
                if let endDate = cycle.endDate {
                    return normalized <= endDate
                }
                return Self.daysBetween(cycle.startDate, normalized) < 45
            })
            .max(by: { $0.startDate < $1.startDate }) {
            if didMutateState {
                state.updatedAt = Date()
                saveState(state)
            }
            return PeriodCycleStartResult(
                cycleID: -max(1, abs(healthCycle.id)),
                didCreate: false
            )
        }

        let newId = state.nextCycleId
        state.nextCycleId += 1
        state.cycles.append(LocalCycle(id: newId, startDate: normalized, endDate: nil))
        state.updatedAt = Date()
        saveState(state)
        return PeriodCycleStartResult(cycleID: newId, didCreate: true)
    }

    @discardableResult
    func endCycle(endDate: Date = Date()) -> Int64 {
        let normalized = Self.normalizeDate(endDate)
        var state = loadState()
        if let openIndex = state.cycles.firstIndex(where: { $0.endDate == nil }) {
            let start = state.cycles[openIndex].startDate
            state.cycles[openIndex].endDate = max(start, normalized)
            state.updatedAt = Date()
            saveState(state)
            return state.cycles[openIndex].id
        }

        let newId = state.nextCycleId
        state.nextCycleId += 1
        state.cycles.append(LocalCycle(id: newId, startDate: normalized, endDate: normalized))
        state.updatedAt = Date()
        saveState(state)
        return newId
    }

    @discardableResult
    func updateCycle(cycleId: Int64, startDate: Date, endDate: Date?) -> Int64 {
        let start = Self.normalizeDate(startDate)
        let end = endDate.map(Self.normalizeDate)
        var state = loadState()
        guard let index = state.cycles.firstIndex(where: { $0.id == cycleId }) else {
            return cycleId
        }
        state.cycles[index].startDate = start
        if let end {
            state.cycles[index].endDate = max(start, end)
        } else {
            state.cycles[index].endDate = nil
        }
        state.updatedAt = Date()
        saveState(state)
        return cycleId
    }

    @discardableResult
    func upsertDayLog(
        date: Date,
        flowLevel: Int?,
        painLevel: Int?,
        moodLevel: Int?,
        hasSexualActivity: Bool? = nil,
        hasIntermenstrualBleeding: Bool? = nil,
        pregnancyTestResult: String? = nil,
        ovulationTestResult: String? = nil,
        cervicalMucusQuality: String? = nil,
        note: String? = nil
    ) -> Int64 {
        let normalized = Self.normalizeDate(date)
        var state = loadState()
        if let index = state.dayLogs.firstIndex(where: { Self.normalizeDate($0.date) == normalized }) {
            state.dayLogs[index].flowLevel = flowLevel
            state.dayLogs[index].painLevel = painLevel
            state.dayLogs[index].moodLevel = moodLevel
            state.dayLogs[index].hasSexualActivity = hasSexualActivity
            state.dayLogs[index].hasIntermenstrualBleeding = hasIntermenstrualBleeding
            state.dayLogs[index].pregnancyTestResult = pregnancyTestResult
            state.dayLogs[index].ovulationTestResult = ovulationTestResult
            state.dayLogs[index].cervicalMucusQuality = cervicalMucusQuality
            state.dayLogs[index].note = note
            state.updatedAt = Date()
            saveState(state)
            return state.dayLogs[index].id
        }
        let newId = state.nextDayLogId
        state.nextDayLogId += 1
        state.dayLogs.append(
            LocalDayLog(
                id: newId,
                date: normalized,
                flowLevel: flowLevel,
                painLevel: painLevel,
                moodLevel: moodLevel,
                hasSexualActivity: hasSexualActivity,
                hasIntermenstrualBleeding: hasIntermenstrualBleeding,
                pregnancyTestResult: pregnancyTestResult,
                ovulationTestResult: ovulationTestResult,
                cervicalMucusQuality: cervicalMucusQuality,
                note: note
            )
        )
        state.updatedAt = Date()
        saveState(state)
        return newId
    }

    func saveRemoteSnapshot(_ summary: PeriodSummary) {
        var state = loadState()
        if let cycles = summary.cycles {
            var cyclesByStart: [Date: LocalCycle] = [:]
            for cycle in state.cycles {
                let start = Self.normalizeDate(cycle.startDate)
                cyclesByStart[start] = LocalCycle(
                    id: cycle.id,
                    startDate: start,
                    endDate: cycle.endDate.map(Self.normalizeDate)
                )
            }

            for item in cycles {
                guard let startString = item.startDate,
                      let parsedStart = Self.dayFormatter.date(from: startString) else {
                    continue
                }
                let start = Self.normalizeDate(parsedStart)
                let existing = cyclesByStart[start]
                let id: Int64
                if item.id > 0 {
                    id = item.id
                    state.nextCycleId = max(state.nextCycleId, id + 1)
                } else if let existing {
                    id = existing.id
                } else {
                    id = state.nextCycleId
                    state.nextCycleId += 1
                }
                cyclesByStart[start] = LocalCycle(
                    id: id,
                    startDate: start,
                    endDate: item.endDate
                        .flatMap(Self.dayFormatter.date(from:))
                        .map(Self.normalizeDate)
                )
            }
            state.cycles = cyclesByStart.values.sorted { $0.startDate < $1.startDate }
        }
        if let logs = summary.dayLogs {
            var logsByDay: [Date: LocalDayLog] = [:]
            for log in state.dayLogs {
                let day = Self.normalizeDate(log.date)
                var normalizedLog = log
                normalizedLog.date = day
                logsByDay[day] = normalizedLog
            }

            for item in logs {
                guard let dateString = item.date,
                      let parsedDate = Self.dayFormatter.date(from: dateString) else {
                    continue
                }
                let day = Self.normalizeDate(parsedDate)
                let existing = logsByDay[day]
                let id: Int64
                if item.id > 0 {
                    id = item.id
                    state.nextDayLogId = max(state.nextDayLogId, id + 1)
                } else if let existing {
                    id = existing.id
                } else {
                    id = state.nextDayLogId
                    state.nextDayLogId += 1
                }
                logsByDay[day] = LocalDayLog(
                    id: id,
                    date: day,
                    flowLevel: item.flowLevel ?? existing?.flowLevel,
                    painLevel: item.painLevel ?? existing?.painLevel,
                    moodLevel: item.moodLevel ?? existing?.moodLevel,
                    hasSexualActivity: item.hasSexualActivity ?? existing?.hasSexualActivity,
                    hasIntermenstrualBleeding: item.hasIntermenstrualBleeding ?? existing?.hasIntermenstrualBleeding,
                    pregnancyTestResult: item.pregnancyTestResult ?? existing?.pregnancyTestResult,
                    ovulationTestResult: item.ovulationTestResult ?? existing?.ovulationTestResult,
                    cervicalMucusQuality: item.cervicalMucusQuality ?? existing?.cervicalMucusQuality,
                    note: item.note ?? existing?.note
                )
            }
            state.dayLogs = logsByDay.values.sorted { $0.date < $1.date }
        }
        state.updatedAt = Date()
        saveState(state)
    }

    func saveHealthKitSnapshot(cycles: [HealthImportCycle], dayLogs: [HealthImportDayLog]) {
        var state = loadState()

        state.healthCycles = cycles.enumerated().map { index, cycle in
            LocalCycle(id: Int64(index + 1), startDate: Self.normalizeDate(cycle.startDate), endDate: cycle.endDate.map(Self.normalizeDate))
        }

        var importedLogsByDay: [Date: LocalDayLog] = [:]
        for item in dayLogs {
            let day = Self.normalizeDate(item.date)
            let existing = importedLogsByDay[day]
            let mergedFlow = max(existing?.flowLevel ?? 0, item.flowLevel ?? 0)
            importedLogsByDay[day] = LocalDayLog(
                id: Int64(importedLogsByDay.count + 1),
                date: day,
                flowLevel: mergedFlow > 0 ? mergedFlow : nil,
                painLevel: max(existing?.painLevel ?? 0, item.painLevel ?? 0) > 0 ? max(existing?.painLevel ?? 0, item.painLevel ?? 0) : nil,
                moodLevel: max(existing?.moodLevel ?? 0, item.moodLevel ?? 0) > 0 ? max(existing?.moodLevel ?? 0, item.moodLevel ?? 0) : nil,
                hasSexualActivity: (existing?.hasSexualActivity == true || item.hasSexualActivity == true) ? true : nil,
                hasIntermenstrualBleeding: (existing?.hasIntermenstrualBleeding == true || item.hasIntermenstrualBleeding == true) ? true : nil,
                pregnancyTestResult: existing?.pregnancyTestResult ?? item.pregnancyTestResult,
                ovulationTestResult: existing?.ovulationTestResult ?? item.ovulationTestResult,
                cervicalMucusQuality: existing?.cervicalMucusQuality ?? item.cervicalMucusQuality,
                note: Self.mergeNotes(existing?.note, item.note)
            )
        }
        state.healthDayLogs = importedLogsByDay.values.sorted { $0.date < $1.date }
        state.updatedAt = Date()
        saveState(state)
    }

    private func resolvedCycles(from state: LocalState) -> [LocalCycle] {
        var cyclesByStart: [Date: LocalCycle] = [:]

        for cycle in state.healthCycles {
            let key = Self.normalizeDate(cycle.startDate)
            cyclesByStart[key] = LocalCycle(
                id: -max(1, abs(cycle.id)),
                startDate: key,
                endDate: cycle.endDate.map(Self.normalizeDate)
            )
        }

        for cycle in state.cycles {
            let start = Self.normalizeDate(cycle.startDate)
            cyclesByStart[start] = LocalCycle(
                id: cycle.id,
                startDate: start,
                endDate: cycle.endDate.map(Self.normalizeDate)
            )
        }

        return cyclesByStart.values.sorted { $0.startDate < $1.startDate }
    }

    private func resolvedDayLogs(from state: LocalState) -> [LocalDayLog] {
        var merged: [Date: LocalDayLog] = [:]

        for log in state.healthDayLogs {
            let day = Self.normalizeDate(log.date)
            merged[day] = LocalDayLog(
                id: log.id,
                date: day,
                flowLevel: log.flowLevel,
                painLevel: log.painLevel,
                moodLevel: log.moodLevel,
                hasSexualActivity: log.hasSexualActivity,
                hasIntermenstrualBleeding: log.hasIntermenstrualBleeding,
                pregnancyTestResult: log.pregnancyTestResult,
                ovulationTestResult: log.ovulationTestResult,
                cervicalMucusQuality: log.cervicalMucusQuality,
                note: log.note
            )
        }

        for log in state.dayLogs {
            let day = Self.normalizeDate(log.date)
            if var existing = merged[day] {
                existing.id = log.id
                existing.flowLevel = log.flowLevel ?? existing.flowLevel
                existing.painLevel = log.painLevel
                existing.moodLevel = log.moodLevel
                existing.hasSexualActivity = log.hasSexualActivity ?? existing.hasSexualActivity
                existing.hasIntermenstrualBleeding = log.hasIntermenstrualBleeding ?? existing.hasIntermenstrualBleeding
                existing.pregnancyTestResult = log.pregnancyTestResult ?? existing.pregnancyTestResult
                existing.ovulationTestResult = log.ovulationTestResult ?? existing.ovulationTestResult
                existing.cervicalMucusQuality = log.cervicalMucusQuality ?? existing.cervicalMucusQuality
                existing.note = log.note
                merged[day] = existing
            } else {
                merged[day] = log
            }
        }

        return merged.values.sorted { $0.date < $1.date }
    }

    private func predictionSource(for state: LocalState) -> String {
        (!state.healthCycles.isEmpty || !state.healthDayLogs.isEmpty) ? Self.healthPredictionSource : Self.localPredictionSource
    }

    private func loadState() -> LocalState {
        if let row = records.records(domain: domain, kind: kind)?.first,
           let state = try? decoder.decode(LocalState.self, from: row.payload) {
            return state
        }
        guard let data = defaults.data(forKey: key) else { return LocalState() }
        return (try? decoder.decode(LocalState.self, from: data)) ?? LocalState()
    }

    @discardableResult
    private func saveState(_ state: LocalState) -> Bool {
        var normalized = state
        normalizeLegacyEventNotes(in: &normalized.dayLogs)
        normalizeLegacyEventNotes(in: &normalized.healthDayLogs)
        guard let data = try? encoder.encode(normalized) else { return false }
        return records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: "current",
                kind: kind,
                occurredAt: normalized.updatedAt,
                updatedAt: normalized.updatedAt,
                payload: data
            )
        )
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "periodStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: key)
            return
        }
        let legacyData = defaults.data(forKey: key)
        let seeds: [LocalDataRecordSeed]
        if let legacyData {
            guard let state = try? decoder.decode(LocalState.self, from: legacyData),
                  let normalizedData = try? encoder.encode(state) else { return }
            seeds = [
                LocalDataRecordSeed(
                    domain: domain,
                    recordID: "current",
                    kind: kind,
                    occurredAt: state.updatedAt,
                    updatedAt: state.updatedAt,
                    payload: normalizedData
                )
            ]
        } else {
            seeds = []
        }
        guard records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: key)
    }

    private func migrateLegacyEventNotesIfNeeded() {
        let migrationID = "periodStore.legacy-event-notes-to-structured.v1"
        guard !records.isMigrationComplete(migrationID) else { return }
        var state = loadState()
        let originalDayLogs = state.dayLogs
        let originalHealthLogs = state.healthDayLogs
        normalizeLegacyEventNotes(in: &state.dayLogs)
        normalizeLegacyEventNotes(in: &state.healthDayLogs)
        if state.dayLogs != originalDayLogs || state.healthDayLogs != originalHealthLogs {
            state.updatedAt = Date()
            guard saveState(state) else { return }
        }
        _ = records.migrate(migrationID, seeds: [])
    }

    private func normalizeLegacyEventNotes(in logs: inout [LocalDayLog]) {
        for index in logs.indices {
            let payload = Self.legacyEventPayload(from: logs[index].note)
            if logs[index].hasSexualActivity == nil { logs[index].hasSexualActivity = payload.hasSexualActivity }
            if logs[index].hasIntermenstrualBleeding == nil { logs[index].hasIntermenstrualBleeding = payload.hasIntermenstrualBleeding }
            if logs[index].pregnancyTestResult == nil { logs[index].pregnancyTestResult = payload.pregnancyTestResult }
            if logs[index].ovulationTestResult == nil { logs[index].ovulationTestResult = payload.ovulationTestResult }
            if logs[index].cervicalMucusQuality == nil { logs[index].cervicalMucusQuality = payload.cervicalMucusQuality }
            logs[index].note = Self.removingLegacyEventText(from: logs[index].note)
        }
    }

    private struct LegacyEventPayload {
        var hasSexualActivity: Bool?
        var hasIntermenstrualBleeding: Bool?
        var pregnancyTestResult: String?
        var ovulationTestResult: String?
        var cervicalMucusQuality: String?
    }

    private static func legacyEventPayload(from note: String?) -> LegacyEventPayload {
        var payload = LegacyEventPayload()
        for part in noteParts(note) {
            switch part {
            case "性行为": payload.hasSexualActivity = true
            case "点滴出血": payload.hasIntermenstrualBleeding = true
            case "妊娠测试阴性": payload.pregnancyTestResult = "negative"
            case "妊娠测试阳性": payload.pregnancyTestResult = "positive"
            case "妊娠测试待确认": payload.pregnancyTestResult = "inconclusive"
            case "排卵测试阴性", "排卵试纸阴性": payload.ovulationTestResult = "negative"
            case "排卵测试阳性", "雌激素上升提示": payload.ovulationTestResult = "positive"
            case "排卵峰值提示": payload.ovulationTestResult = "peak"
            case "排卵测试待确认", "排卵试纸待确认": payload.ovulationTestResult = "inconclusive"
            case "宫颈黏液偏干": payload.cervicalMucusQuality = "dry"
            case "宫颈黏液黏稠": payload.cervicalMucusQuality = "sticky"
            case "宫颈黏液乳霜样": payload.cervicalMucusQuality = "creamy"
            case "宫颈黏液水样": payload.cervicalMucusQuality = "watery"
            case "宫颈黏液蛋清样": payload.cervicalMucusQuality = "eggWhite"
            default: break
            }
        }
        return payload
    }

    private static func removingLegacyEventText(from note: String?) -> String? {
        let remaining = noteParts(note).filter { !isLegacyEventText($0) }
        return remaining.isEmpty ? nil : remaining.joined(separator: " · ")
    }

    private static func noteParts(_ note: String?) -> [String] {
        note?.split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func isLegacyEventText(_ text: String) -> Bool {
        switch text {
        case "性行为", "点滴出血",
             "妊娠测试阴性", "妊娠测试阳性", "妊娠测试待确认",
             "排卵测试阴性", "排卵试纸阴性", "排卵测试阳性", "雌激素上升提示",
             "排卵峰值提示", "排卵测试待确认", "排卵试纸待确认",
             "宫颈黏液偏干", "宫颈黏液黏稠", "宫颈黏液乳霜样", "宫颈黏液水样", "宫颈黏液蛋清样":
            return true
        default:
            return false
        }
    }

    private func resolveCycleLength(cycles: [LocalCycle]) -> Int {
        guard cycles.count >= 2 else { return 28 }
        var values: [Int] = []
        for i in 0..<(cycles.count - 1) {
            let a = cycles[i].startDate
            let b = cycles[i + 1].startDate
            let len = Self.daysBetween(b, a)
            if (20...45).contains(len) {
                values.append(len)
            }
        }
        guard !values.isEmpty else { return 28 }
        let sum = values.reduce(0, +)
        return Int((Double(sum) / Double(values.count)).rounded())
    }

    private func resolvePeriodLength(cycles: [LocalCycle]) -> Int {
        var values: [Int] = []
        for cycle in cycles {
            guard let end = cycle.endDate else { continue }
            let len = Self.daysBetween(cycle.startDate, end) + 1
            if (2...10).contains(len) {
                values.append(len)
            }
        }
        guard !values.isEmpty else { return 5 }
        let sum = values.reduce(0, +)
        return Int((Double(sum) / Double(values.count)).rounded())
    }

    nonisolated private static func daysBetween(_ start: Date, _ end: Date) -> Int {
        let diff = Self.normalizeDate(end).timeIntervalSince(Self.normalizeDate(start))
        return Int(diff / 86_400.0)
    }

    nonisolated private static func addDays(_ date: Date, _ days: Int) -> Date {
        let cal = Calendar.current
        let result = cal.date(byAdding: .day, value: days, to: date) ?? date
        return Self.normalizeDate(result)
    }

    nonisolated private static func normalizeDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func mergeNotes(_ existing: String?, _ incoming: String?) -> String? {
        let left = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = incoming?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (left?.isEmpty == false ? left : nil, right?.isEmpty == false ? right : nil) {
        case let (.some(a), .some(b)):
            if a == b { return a }
            return [a, b].joined(separator: " · ")
        case let (.some(a), nil):
            return a
        case let (nil, .some(b)):
            return b
        default:
            return nil
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct LocalState: Codable {
        var nextCycleId: Int64 = 1
        var nextDayLogId: Int64 = 1
        var cycles: [LocalCycle] = []
        var dayLogs: [LocalDayLog] = []
        var healthCycles: [LocalCycle] = []
        var healthDayLogs: [LocalDayLog] = []
        var updatedAt: Date = Date()

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nextCycleId = try container.decodeIfPresent(Int64.self, forKey: .nextCycleId) ?? 1
            nextDayLogId = try container.decodeIfPresent(Int64.self, forKey: .nextDayLogId) ?? 1
            cycles = try container.decodeIfPresent([LocalCycle].self, forKey: .cycles) ?? []
            dayLogs = try container.decodeIfPresent([LocalDayLog].self, forKey: .dayLogs) ?? []
            healthCycles = try container.decodeIfPresent([LocalCycle].self, forKey: .healthCycles) ?? []
            healthDayLogs = try container.decodeIfPresent([LocalDayLog].self, forKey: .healthDayLogs) ?? []
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        }
    }

    private struct LocalCycle: Codable {
        var id: Int64
        var startDate: Date
        var endDate: Date?
    }

    private struct LocalDayLog: Codable, Equatable {
        var id: Int64
        var date: Date
        var flowLevel: Int?
        var painLevel: Int?
        var moodLevel: Int?
        var hasSexualActivity: Bool?
        var hasIntermenstrualBleeding: Bool?
        var pregnancyTestResult: String?
        var ovulationTestResult: String?
        var cervicalMucusQuality: String?
        var note: String?
    }

    /// Health Import Cycle 结构体，作为内部辅助类型，用于配合外层经期数据存储与读取。
    struct HealthImportCycle {
        let startDate: Date
        let endDate: Date?
    }

    /// Health Import Day Log 结构体，作为内部辅助类型，用于配合外层经期数据存储与读取。
    struct HealthImportDayLog {
        let date: Date
        let flowLevel: Int?
        let painLevel: Int?
        let moodLevel: Int?
        let hasSexualActivity: Bool?
        let hasIntermenstrualBleeding: Bool?
        let pregnancyTestResult: String?
        let ovulationTestResult: String?
        let cervicalMucusQuality: String?
        let note: String?

        init(
            date: Date,
            flowLevel: Int? = nil,
            painLevel: Int? = nil,
            moodLevel: Int? = nil,
            hasSexualActivity: Bool? = nil,
            hasIntermenstrualBleeding: Bool? = nil,
            pregnancyTestResult: String? = nil,
            ovulationTestResult: String? = nil,
            cervicalMucusQuality: String? = nil,
            note: String? = nil
        ) {
            self.date = date
            self.flowLevel = flowLevel
            self.painLevel = painLevel
            self.moodLevel = moodLevel
            self.hasSexualActivity = hasSexualActivity
            self.hasIntermenstrualBleeding = hasIntermenstrualBleeding
            self.pregnancyTestResult = pregnancyTestResult
            self.ovulationTestResult = ovulationTestResult
            self.cervicalMucusQuality = cervicalMucusQuality
            self.note = note
        }
    }
}
