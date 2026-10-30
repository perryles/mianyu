/// GoalsView 由 MainTabView 目标 Tab 调用，作为「目标」首页入口。
/// 负责定义目标分类枚举（睡眠/运动/饮水/呼吸/日照/自定义）并展示目标列表与打卡入口。

import SwiftUI
import SwiftData
import UIKit

enum GoalCategory: String, Codable, CaseIterable, Identifiable {
    case sleep
    case movement
    case hydration
    case recovery
    case sunlight
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return String(localized: "睡眠")
        case .movement: return String(localized: "运动")
        case .hydration: return String(localized: "饮水")
        case .recovery: return String(localized: "呼吸")
        case .sunlight: return String(localized: "日照")
        case .custom: return String(localized: "自定义")
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.stars.fill"
        case .movement: return "figure.walk"
        case .hydration: return "drop.fill"
        case .recovery: return "wind"
        case .sunlight: return "sun.max.fill"
        case .custom: return "sparkles"
        }
    }

    var tintHex: String {
        switch self {
        case .sleep: return "5E7BFF"
        case .movement: return "58CC6A"
        case .hydration: return "32ADE6"
        case .recovery: return "7AB7A8"
        case .sunlight: return "F4B46B"
        case .custom: return "FF8FB8"
        }
    }
}

struct GoalItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var category: GoalCategory
    var symbol: String
    var targetValue: Int
    var unit: String
    var linkedActionKind: DailyWellnessActionKind?
    var isActive: Bool
    var createdAt: Date

    var tintHex: String { category.tintHex }
}

struct GoalProgressRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let goalID: UUID
    let date: Date
    var value: Int
    var isCompleted: Bool
    var updatedAt: Date
}

struct GoalXPGrant: Codable, Identifiable, Equatable {
    let id: UUID
    let goalID: UUID
    let date: Date
    let amount: Int
    let awardedAt: Date
}

enum GoalPetGrowthStage: String, CaseIterable, Identifiable {
    case newcomer
    case sprout
    case companion
    case guardian
    case starlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newcomer: return String(localized: "初见伙伴")
        case .sprout: return String(localized: "活力新芽")
        case .companion: return String(localized: "默契伙伴")
        case .guardian: return String(localized: "节律守护")
        case .starlight: return String(localized: "星光同行")
        }
    }

    var shortTitle: String {
        switch self {
        case .newcomer: return String(localized: "初见")
        case .sprout: return String(localized: "新芽")
        case .companion: return String(localized: "默契")
        case .guardian: return String(localized: "守护")
        case .starlight: return String(localized: "星光")
        }
    }

    var minimumLevel: Int {
        switch self {
        case .newcomer: return 1
        case .sprout: return 4
        case .companion: return 8
        case .guardian: return 13
        case .starlight: return 20
        }
    }

    var symbol: String {
        switch self {
        case .newcomer: return "circle.fill"
        case .sprout: return "leaf.fill"
        case .companion: return "heart.fill"
        case .guardian: return "shield.fill"
        case .starlight: return "sparkles"
        }
    }

    var tintHex: String {
        switch self {
        case .newcomer: return "7AA9C7"
        case .sprout: return "58B88A"
        case .companion: return "5E7BFF"
        case .guardian: return "F4A259"
        case .starlight: return "D36FB2"
        }
    }

    var next: GoalPetGrowthStage? {
        guard let index = Self.allCases.firstIndex(of: self), index < Self.allCases.count - 1 else { return nil }
        return Self.allCases[index + 1]
    }

    static func stage(for level: Int) -> GoalPetGrowthStage {
        Self.allCases.last { level >= $0.minimumLevel } ?? .newcomer
    }
}

struct GoalPetReward: Identifiable, Equatable {
    let id = UUID()
    let xpGained: Int
    let previousLevel: Int
    let currentLevel: Int

    var didLevelUp: Bool { currentLevel > previousLevel }
}

nonisolated struct GoalPetState: Codable, Equatable {
    var name: String
    var level: Int
    var xp: Int
    var rewardCount: Int
    var createdAt: Date
    var lastXPDate: Date?
    var nameUpdatedAt: Date?

    static let empty = GoalPetState(
        name: "TATA",
        level: 1,
        xp: 0,
        rewardCount: 0,
        createdAt: Date(),
        lastXPDate: nil,
        nameUpdatedAt: nil
    )
}

enum GoalMascotCloudSyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case unavailable

    var title: String {
        switch self {
        case .idle:
            return String(localized: "等待 iCloud 同步")
        case .syncing:
            return String(localized: "正在同步到 iCloud")
        case .synced:
            return String(localized: "已保存到 iCloud")
        case .unavailable:
            return String(localized: "本地保存，iCloud 暂不可用")
        }
    }

    var systemImage: String {
        switch self {
        case .idle, .unavailable:
            return "icloud.slash"
        case .syncing:
            return "icloud.and.arrow.up"
        case .synced:
            return "checkmark.icloud"
        }
    }
}

struct GoalPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let category: GoalCategory
    let symbol: String
    let targetValue: Int
    let unit: String
    let linkedActionKind: DailyWellnessActionKind?
    let detail: String

    static let defaults: [GoalPreset] = [
        GoalPreset(id: "water", title: "喝一杯水", category: .hydration, symbol: "drop.fill", targetValue: 250, unit: "ml", linkedActionKind: .water, detail: "补水记录会自动计入目标。"),
        GoalPreset(id: "sunlight", title: "晒 5 分钟太阳", category: .sunlight, symbol: "sun.max.fill", targetValue: 5, unit: "分钟", linkedActionKind: .sunlight, detail: "日照轻动作完成后同步达成。"),
        GoalPreset(id: "breathing", title: "呼吸放松", category: .recovery, symbol: "wind", targetValue: 3, unit: "分钟", linkedActionKind: .breathing, detail: "完成呼吸放松即可获得进度。"),
        GoalPreset(id: "move", title: "起身活动", category: .movement, symbol: "figure.walk", targetValue: 1, unit: "次", linkedActionKind: .move, detail: "起身一次就算完成。"),
        GoalPreset(id: "windDown", title: "睡前收尾", category: .sleep, symbol: "moon.stars.fill", targetValue: 1, unit: "次", linkedActionKind: .bedtimeWindDown, detail: "晚上开始收尾后点一下。")
    ]
}

@MainActor
@Observable
final class GoalsStore {
    static let maxActiveGoals = 4
    static let xpPerGoal = 18
    static let shared = GoalsStore()

    private(set) var goals: [GoalItem] = []
    private(set) var records: [GoalProgressRecord] = []
    private(set) var petState: GoalPetState = .empty
    private(set) var xpGrants: [GoalXPGrant] = []
    private(set) var mascotCloudSyncStatus: GoalMascotCloudSyncStatus = .idle

    private let payloadKey = "goals.store.payload.v1"
    private let cloudAccountKey = CloudKitDataPolicy.AccountBindingKey.goalMascot
    private let defaults: UserDefaults
    private let recordStore: SwiftDataRecordStore
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cloudRepository: GoalMascotCloudRepository?
    private var cloudSyncTask: Task<Void, Never>?
    /// 云同步代际：同步期间本地发生新写入（新增 XP/等级）时，丢弃本次过期快照，等待下一次调度。
    private var mascotSyncGeneration = 0
    private let storageDomain = "goals"
    private let goalKind = "goal"
    private let progressKind = "progress"
    private let petKind = "pet"
    private let grantKind = "xp-grant"

    private struct Payload: Codable {
        var goals: [GoalItem]
        var records: [GoalProgressRecord]
        var petState: GoalPetState
        var xpGrants: [GoalXPGrant]?
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        cloudRepository: GoalMascotCloudRepository? = GoalMascotCloudRepository(),
        container: ModelContainer? = nil
    ) {
        self.defaults = defaults
        recordStore = SwiftDataRecordStore(container: container ?? MianyuModelContainer.shared)
        self.calendar = calendar
        self.cloudRepository = cloudRepository
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
        load()
        scheduleMascotCloudSync(delayNanoseconds: 0)
    }

    var activeGoals: [GoalItem] {
        goals.filter(\.isActive).sorted { $0.createdAt < $1.createdAt }
    }

    var pausedGoals: [GoalItem] {
        goals.filter { !$0.isActive }.sorted { $0.createdAt > $1.createdAt }
    }

    func addPreset(_ preset: GoalPreset) {
        guard activeGoals.count < Self.maxActiveGoals, !hasActivePreset(preset) else { return }
        let goal = GoalItem(
            id: UUID(),
            title: preset.title,
            category: preset.category,
            symbol: preset.symbol,
            targetValue: preset.targetValue,
            unit: preset.unit,
            linkedActionKind: preset.linkedActionKind,
            isActive: true,
            createdAt: Date()
        )
        goals.append(goal)
        save()
    }

    func hasActivePreset(_ preset: GoalPreset) -> Bool {
        goals.contains { goal in
            if let linked = preset.linkedActionKind {
                return goal.linkedActionKind == linked
            }
            return goal.title == preset.title
        }
    }

    func addCustom(title: String, category: GoalCategory, targetValue: Int, unit: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, activeGoals.count < Self.maxActiveGoals else { return }
        let goal = GoalItem(
            id: UUID(),
            title: trimmedTitle,
            category: category,
            symbol: category.symbol,
            targetValue: max(targetValue, 1),
            unit: trimmedUnit.isEmpty ? "次" : trimmedUnit,
            linkedActionKind: nil,
            isActive: true,
            createdAt: Date()
        )
        goals.append(goal)
        save()
    }

    @discardableResult
    func toggleGoal(_ goal: GoalItem, on date: Date, wellnessRecord: DailyWellnessDayRecord) -> GoalPetReward? {
        if let linkedActionKind = goal.linkedActionKind,
           wellnessRecord.completedAction(linkedActionKind) != nil {
            return nil
        }
        let progress = progress(for: goal, on: date, wellnessRecord: wellnessRecord)
        let targetCompleted = !progress.isCompleted
        updateRecord(goalID: goal.id, on: date) { record in
            record.value = targetCompleted ? goal.targetValue : 0
            record.isCompleted = targetCompleted
        }
        let reward = targetCompleted ? awardXPIfNeeded(for: goal.id, on: date) : nil
        save()
        return reward
    }

    @discardableResult
    func syncLinkedGoalRewards(on date: Date, wellnessRecord: DailyWellnessDayRecord) -> GoalPetReward? {
        let previousLevel = petState.level
        var gainedXP = 0
        for goal in activeGoals where goal.linkedActionKind != nil {
            guard progress(for: goal, on: date, wellnessRecord: wellnessRecord).isCompleted else { continue }
            if let reward = awardXPIfNeeded(for: goal.id, on: date) {
                gainedXP += reward.xpGained
            }
        }
        guard gainedXP > 0 else { return nil }
        save()
        return GoalPetReward(
            xpGained: gainedXP,
            previousLevel: previousLevel,
            currentLevel: petState.level
        )
    }

    func deactivate(_ goal: GoalItem) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].isActive = false
        save()
    }

    func activate(_ goal: GoalItem) {
        guard activeGoals.count < Self.maxActiveGoals,
              let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index].isActive = true
        save()
    }

    func delete(_ goal: GoalItem) {
        goals.removeAll { $0.id == goal.id }
        records.removeAll { $0.goalID == goal.id }
        save()
    }

    @discardableResult
    func adjustProgress(
        for goal: GoalItem,
        by delta: Int,
        on date: Date,
        wellnessRecord: DailyWellnessDayRecord
    ) -> GoalPetReward? {
        guard goal.linkedActionKind == nil, delta != 0 else { return nil }
        let current = progress(for: goal, on: date, wellnessRecord: wellnessRecord)
        let newValue = min(goal.targetValue, max(0, current.value + delta))
        guard newValue != current.value else { return nil }

        updateRecord(goalID: goal.id, on: date) { record in
            record.value = newValue
            record.isCompleted = newValue >= goal.targetValue
        }
        let reward = !current.isCompleted && newValue >= goal.targetValue
            ? awardXPIfNeeded(for: goal.id, on: date)
            : nil
        save()
        return reward
    }

    func renamePet(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        petState.name = String(trimmed.prefix(12))
        petState.nameUpdatedAt = Date()
        save()
    }

    func refreshMascotFromCloud() {
        scheduleMascotCloudSync(delayNanoseconds: 0)
    }

    func progress(for goal: GoalItem, on date: Date, wellnessRecord: DailyWellnessDayRecord) -> GoalProgressRecord {
        let day = calendar.startOfDay(for: date)
        if let linked = goal.linkedActionKind,
           let completed = wellnessRecord.completedAction(linked) {
            return GoalProgressRecord(
                id: goal.id,
                goalID: goal.id,
                date: day,
                value: max(completed.value, goal.targetValue),
                isCompleted: true,
                updatedAt: completed.completedAt
            )
        }
        return records.first {
            $0.goalID == goal.id && calendar.isDate($0.date, inSameDayAs: day)
        } ?? GoalProgressRecord(id: goal.id, goalID: goal.id, date: day, value: 0, isCompleted: false, updatedAt: day)
    }

    func completionRate(on date: Date, wellnessRecord: DailyWellnessDayRecord) -> Double {
        let goals = activeGoals
        guard !goals.isEmpty else { return 0 }
        let total = goals.reduce(0.0) { partial, goal in
            partial + progressRate(for: goal, on: date, wellnessRecord: wellnessRecord)
        }
        return total / Double(goals.count)
    }

    func progressRate(for goal: GoalItem, on date: Date, wellnessRecord: DailyWellnessDayRecord) -> Double {
        let progress = progress(for: goal, on: date, wellnessRecord: wellnessRecord)
        guard goal.targetValue > 0 else { return progress.isCompleted ? 1 : 0 }
        return progress.isCompleted ? 1 : min(1, Double(progress.value) / Double(goal.targetValue))
    }

    func completedCount(on date: Date, wellnessRecord: DailyWellnessDayRecord) -> Int {
        activeGoals.filter { progress(for: $0, on: date, wellnessRecord: wellnessRecord).isCompleted }.count
    }

    func hasAwardedXP(for goalID: UUID, on date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return xpGrants.contains {
            $0.goalID == goalID && calendar.isDate($0.date, inSameDayAs: day)
        }
    }

    func earnedXP(on date: Date) -> Int {
        let day = calendar.startOfDay(for: date)
        return xpGrants.reduce(into: 0) { total, grant in
            guard calendar.isDate(grant.date, inSameDayAs: day) else { return }
            total += max(grant.amount, 0)
        }
    }

    func reviewDays(endingAt date: Date, wellnessSummary: DailyWellnessSummary, count: Int = 14) -> [GoalReviewDay] {
        let endDay = calendar.startOfDay(for: date)
        return (0..<count).compactMap { offset -> GoalReviewDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { return nil }
            let wellnessRecord = calendar.isDate(day, inSameDayAs: wellnessSummary.todayRecord.date)
                ? wellnessSummary.todayRecord
                : DailyWellnessStore.shared.record(on: day)
            let rate = completionRate(on: day, wellnessRecord: wellnessRecord)
            return GoalReviewDay(
                date: day,
                score: Int((rate * 100).rounded()),
                completed: completedCount(on: day, wellnessRecord: wellnessRecord),
                total: activeGoals.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func updateRecord(goalID: UUID, on date: Date, mutate: (inout GoalProgressRecord) -> Void) {
        let day = calendar.startOfDay(for: date)
        let index = records.firstIndex { $0.goalID == goalID && calendar.isDate($0.date, inSameDayAs: day) }
        var record = index.map { records[$0] } ?? GoalProgressRecord(id: UUID(), goalID: goalID, date: day, value: 0, isCompleted: false, updatedAt: Date())
        mutate(&record)
        record.updatedAt = Date()
        if let index {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    private func awardXPIfNeeded(for goalID: UUID, on date: Date) -> GoalPetReward? {
        let day = calendar.startOfDay(for: date)
        guard !xpGrants.contains(where: { $0.goalID == goalID && calendar.isDate($0.date, inSameDayAs: day) }) else {
            return nil
        }

        let isFirstRewardOfDay = !xpGrants.contains { calendar.isDate($0.date, inSameDayAs: day) }
        xpGrants.append(
            GoalXPGrant(
                id: UUID(),
                goalID: goalID,
                date: day,
                amount: Self.xpPerGoal,
                awardedAt: Date()
            )
        )

        let previousLevel = petState.level
        petState.xp += Self.xpPerGoal
        if isFirstRewardOfDay {
            petState.rewardCount += 1
        }
        if petState.lastXPDate.map({ day > $0 }) ?? true {
            petState.lastXPDate = day
        }
        while petState.xp >= xpNeeded(for: petState.level) {
            petState.xp -= xpNeeded(for: petState.level)
            petState.level += 1
            petState.rewardCount += 1
        }
        return GoalPetReward(
            xpGained: Self.xpPerGoal,
            previousLevel: previousLevel,
            currentLevel: petState.level
        )
    }

    func xpNeeded(for level: Int) -> Int {
        80 + max(level - 1, 0) * 24
    }

    func totalEarnedXP() -> Int {
        let completedLevelsXP = (1..<max(petState.level, 1)).reduce(0) { $0 + xpNeeded(for: $1) }
        return completedLevelsXP + petState.xp
    }

    func stageProgress(for level: Int) -> Double {
        let stage = GoalPetGrowthStage.stage(for: level)
        guard let next = stage.next else { return 1 }
        let span = max(next.minimumLevel - stage.minimumLevel, 1)
        return min(1, max(0, Double(level - stage.minimumLevel) / Double(span)))
    }

    private func load() {
        guard let rows = recordStore.records(domain: storageDomain) else {
            loadLegacyPayload()
            return
        }
        goals = rows.filter { $0.kind == goalKind }.compactMap { try? decoder.decode(GoalItem.self, from: $0.payload) }
        records = rows.filter { $0.kind == progressKind }.compactMap { try? decoder.decode(GoalProgressRecord.self, from: $0.payload) }
        petState = rows.first(where: { $0.kind == petKind }).flatMap { try? decoder.decode(GoalPetState.self, from: $0.payload) } ?? .empty
        let savedGrants = rows.filter { $0.kind == grantKind }.compactMap { try? decoder.decode(GoalXPGrant.self, from: $0.payload) }
        if !savedGrants.isEmpty {
            xpGrants = savedGrants
        } else {
            xpGrants = records.filter(\.isCompleted).map {
                GoalXPGrant(id: UUID(), goalID: $0.goalID, date: calendar.startOfDay(for: $0.date), amount: 0, awardedAt: $0.updatedAt)
            }
        }
    }

    private func loadLegacyPayload() {
        guard let data = defaults.data(forKey: payloadKey),
              let payload = try? decoder.decode(Payload.self, from: data) else { return }
        goals = payload.goals
        records = payload.records
        petState = payload.petState
        xpGrants = payload.xpGrants ?? records.filter(\.isCompleted).map {
            GoalXPGrant(id: UUID(), goalID: $0.goalID, date: calendar.startOfDay(for: $0.date), amount: 0, awardedAt: $0.updatedAt)
        }
    }

    private func save() {
        guard persistCurrentState() else { return }
        scheduleMascotCloudSync()
    }

    private func saveWithoutCloudSync() {
        _ = persistCurrentState()
    }

    private func persistCurrentState() -> Bool {
        var seeds: [LocalDataRecordSeed] = []
        for goal in goals {
            guard let data = try? encoder.encode(goal) else { return false }
            seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: goal.id.uuidString, kind: goalKind, occurredAt: goal.createdAt, updatedAt: goal.createdAt, payload: data))
        }
        for progress in records {
            guard let data = try? encoder.encode(progress) else { return false }
            seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: progress.id.uuidString, kind: progressKind, occurredAt: progress.date, updatedAt: progress.updatedAt, payload: data))
        }
        guard let petData = try? encoder.encode(petState) else { return false }
        seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: "current", kind: petKind, occurredAt: petState.createdAt, updatedAt: petState.nameUpdatedAt ?? petState.lastXPDate ?? petState.createdAt, payload: petData))
        for grant in xpGrants {
            guard let data = try? encoder.encode(grant) else { return false }
            seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: grant.id.uuidString, kind: grantKind, occurredAt: grant.date, updatedAt: grant.awardedAt, payload: data))
        }
        return recordStore.replace(domain: storageDomain, with: seeds)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "goals.store.payload.v1-to-swiftdata.v1"
        if recordStore.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: payloadKey)
            return
        }
        guard let legacyData = defaults.data(forKey: payloadKey) else {
            guard recordStore.migrate(migrationID, seeds: []) else { return }
            return
        }
        guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
        var seeds: [LocalDataRecordSeed] = []
        for goal in payload.goals {
            guard let data = try? encoder.encode(goal) else { return }
            seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: goal.id.uuidString, kind: goalKind, occurredAt: goal.createdAt, updatedAt: goal.createdAt, payload: data))
        }
        for progress in payload.records {
            guard let data = try? encoder.encode(progress) else { return }
            seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: progress.id.uuidString, kind: progressKind, occurredAt: progress.date, updatedAt: progress.updatedAt, payload: data))
        }
        guard let petData = try? encoder.encode(payload.petState) else { return }
        seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: "current", kind: petKind, occurredAt: payload.petState.createdAt, updatedAt: payload.petState.nameUpdatedAt ?? payload.petState.lastXPDate ?? payload.petState.createdAt, payload: petData))
        for grant in payload.xpGrants ?? [] {
            guard let data = try? encoder.encode(grant) else { return }
            seeds.append(LocalDataRecordSeed(domain: storageDomain, recordID: grant.id.uuidString, kind: grantKind, occurredAt: grant.date, updatedAt: grant.awardedAt, payload: data))
        }
        guard recordStore.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: payloadKey)
    }

    private func scheduleMascotCloudSync(delayNanoseconds: UInt64 = 900_000_000) {
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.goalMascotSyncEnabled),
              cloudRepository != nil else {
            cloudSyncTask?.cancel()
            mascotCloudSyncStatus = .idle
            return
        }
        cloudSyncTask?.cancel()
        mascotSyncGeneration += 1
        let generation = mascotSyncGeneration
        cloudSyncTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.performMascotCloudSync(generation: generation)
        }
    }

    private func performMascotCloudSync(generation: Int) async {
        guard let cloudRepository else { return }
        mascotCloudSyncStatus = .syncing

        // 同步期间本地发生新写入时，本次快照已过期：不覆盖本地数据，交给下一次调度。
        func isCurrent() -> Bool {
            !Task.isCancelled && generation == mascotSyncGeneration
        }

        do {
            let previousAccountIdentifier = defaults.string(forKey: cloudAccountKey)
            let fetched = try await cloudRepository.fetch()
            guard isCurrent() else { return }

            if let previousAccountIdentifier,
               previousAccountIdentifier != fetched.accountIdentifier {
                applyCloudSnapshot(fetched.snapshot ?? .empty())
                defaults.set(fetched.accountIdentifier, forKey: cloudAccountKey)
                saveWithoutCloudSync()
                mascotCloudSyncStatus = .synced(Date())
                return
            }

            let synchronized = try await cloudRepository.synchronize(local: makeCloudSnapshot())
            guard isCurrent() else { return }
            if let snapshot = synchronized.snapshot {
                applyCloudSnapshot(snapshot)
                saveWithoutCloudSync()
            }
            defaults.set(synchronized.accountIdentifier, forKey: cloudAccountKey)
            mascotCloudSyncStatus = .synced(Date())
        } catch {
            // 任务已被取代时，不覆盖新任务的同步状态。
            guard isCurrent() else { return }
            mascotCloudSyncStatus = .unavailable
        }
    }

    private func makeCloudSnapshot() -> GoalMascotCloudSnapshot {
        let grantedXP = xpGrants.reduce(0) { $0 + max($1.amount, 0) }
        return GoalMascotCloudSnapshot(
            name: petState.name,
            nameUpdatedAt: petState.nameUpdatedAt,
            createdAt: petState.createdAt,
            baselineXP: max(0, totalEarnedXP() - grantedXP),
            rewardCount: petState.rewardCount,
            lastXPDate: petState.lastXPDate,
            grants: xpGrants
        )
    }

    private func applyCloudSnapshot(_ snapshot: GoalMascotCloudSnapshot) {
        xpGrants = snapshot.grants
        let totalXP = max(0, snapshot.baselineXP + snapshot.grants.reduce(0) { $0 + max($1.amount, 0) })
        let progression = progression(forTotalXP: totalXP)
        let distinctRewardDays = Set(snapshot.grants.map {
            calendar.startOfDay(for: $0.date).timeIntervalSinceReferenceDate
        }).count

        petState = GoalPetState(
            name: snapshot.name,
            level: progression.level,
            xp: progression.xp,
            rewardCount: max(snapshot.rewardCount, distinctRewardDays + max(progression.level - 1, 0)),
            createdAt: snapshot.createdAt,
            lastXPDate: snapshot.lastXPDate ?? snapshot.grants.map(\.date).max(),
            nameUpdatedAt: snapshot.nameUpdatedAt
        )
    }

    private func progression(forTotalXP totalXP: Int) -> (level: Int, xp: Int) {
        var level = 1
        var remainingXP = max(0, totalXP)
        while remainingXP >= xpNeeded(for: level) {
            remainingXP -= xpNeeded(for: level)
            level += 1
        }
        return (level, remainingXP)
    }
}

struct GoalReviewDay: Identifiable, Equatable {
    let date: Date
    let score: Int
    let completed: Int
    let total: Int

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct GoalsView: View {
    let refreshToken: Int
    let onOpenLinkedAction: (DailyWellnessActionKind, Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wellnessSummary = DailyWellnessSummary.empty()
    @State private var store = GoalsStore.shared
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedGoalID: UUID?
    @State private var selectedReviewDate = Calendar.current.startOfDay(for: Date())
    @State private var showingCreateGoal = false
    @State private var showingReview = false
    @State private var showingPetEditor = false
    @State private var recoveryOrchestrationPlan: DailyRecoveryOrchestrationPlan?
    @State private var rewardFeedback: GoalPetReward?
    @State private var showingLinkedReport = false
    @State private var mascotAction: GoalMascotAction = .planning
    @State private var mascotActionTrigger = 0
    @State private var knownCompletedGoalIDs: Set<UUID> = []
    @State private var hasPrimedCompletionSnapshot = false
    private let calendar = Calendar.current

    private var pageRefreshID: String {
        "\(refreshToken)-\(selectedDate.timeIntervalSinceReferenceDate)"
    }

    init(
        refreshToken: Int = 0,
        onOpenLinkedAction: @escaping (DailyWellnessActionKind, Date) -> Void = { _, _ in }
    ) {
        self.refreshToken = refreshToken
        self.onOpenLinkedAction = onOpenLinkedAction
    }

    var body: some View {
        observedContent
    }

    private var goalsContent: some View {
        ZStack {
            goalsBackground

            AdaptivePageScrollView(topPadding: Theme.Spacing.compact, bottomPadding: 132, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    goalPageHeader
                    todayGoalBoard
                    petHeroCard
                    recoveryPriorityCard
                    reviewStrip
                    weeklyInsightCard
                    petGrowthCard
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let rewardFeedback {
                rewardFeedbackBanner(rewardFeedback)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.top, Theme.Spacing.compact)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    private var observedContent: some View {
        presentedContent
        .task(id: pageRefreshID) {
            // 先让首屏完成一次布局，再读取本地摘要；任务按 token 自动合并与取消。
            await Task.yield()
            guard !Task.isCancelled else { return }
            handleRefresh()
            await refreshLinkedWellnessFromHealthData(for: selectedDate)
        }
        .onChange(of: store.goals) { _, _ in
            handleGoalsChange()
        }
        .onChange(of: selectedDate) { _, date in
            handleSelectedDateChange(date)
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileVitalityRecordsDidChange)) { _ in
            handleRefresh()
        }
        .onChange(of: selectedGoalID) { _, _ in
            handleSelectedGoalChange()
        }
    }

    private var presentedContent: some View {
        goalsContent
        .sheet(isPresented: $showingCreateGoal) {
            CreateGoalSheet(store: store)
                .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.72), .large], dragIndicator: .visible)
        }
        .sheet(isPresented: $showingReview) {
            GoalReviewSheet(
                store: store,
                wellnessSummary: wellnessSummary,
                selectedDate: $selectedReviewDate
            )
            .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.7), .large], dragIndicator: .visible)
        }
        .sheet(isPresented: $showingPetEditor) {
            PetNameSheet(store: store)
                .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.38), .medium], dragIndicator: .visible)
        }
        .sheet(isPresented: $showingLinkedReport) {
            NavigationStack {
                ReportDetailView(reportDate: selectedDate, initialSummary: nil)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }

    private func handleWellnessSummaryChange(_ summary: DailyWellnessSummary) {
        guard calendar.isDate(summary.todayRecord.date, inSameDayAs: selectedDate) else { return }
        if let reward = store.syncLinkedGoalRewards(on: selectedDate, wellnessRecord: summary.todayRecord) {
            presentRewardFeedback(reward)
        }
        detectNewGoalCompletions(in: summary.todayRecord)
    }

    private func handleGoalsChange() {
        if let reward = store.syncLinkedGoalRewards(
            on: selectedDate,
            wellnessRecord: wellnessSummary.todayRecord
        ) {
            presentRewardFeedback(reward)
        }
        syncSelections()
    }

    private func handleSelectedDateChange(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        if day != date {
            selectedDate = day
            return
        }
        syncSelections()
        hasPrimedCompletionSnapshot = false
        replayMascotAction()
    }

    private func handleRefresh() {
        reloadLocalPageData(for: selectedDate)
        syncSelections()
        replayMascotAction()
    }

    private func reloadLocalPageData(for date: Date) {
        let summary = DailyWellnessStore.shared.summary(endingAt: date, days: 7)
        wellnessSummary = summary
        recoveryOrchestrationPlan = DailyRecoveryOrchestrationStore.shared.load(for: date, calendar: calendar)
        handleWellnessSummaryChange(summary)
    }

    private func refreshLinkedWellnessFromHealthData(for date: Date) async {
        let linkedKinds = activeGoals.compactMap(\.linkedActionKind)
        let needsWater = linkedKinds.contains(.water)
        let needsSunlight = linkedKinds.contains(.sunlight)
        let needsMindfulness = linkedKinds.contains(.breathing)
        let needsStand = linkedKinds.contains(.move)
        guard needsWater || needsSunlight || needsMindfulness || needsStand else { return }

        async let waterAmount: Int = needsWater
            ? ((try? await HealthKitManager.shared.fetchDietaryWaterIntake(on: date)) ?? 0)
            : 0
        async let sunlightMinutes: Int = needsSunlight
            ? ((try? await HealthKitManager.shared.fetchTimeInDaylightMinutes(on: date)) ?? 0)
            : 0
        async let mindfulnessMinutes: Int = needsMindfulness
            ? ((try? await HealthKitManager.shared.fetchMindfulnessMinutes(on: date)) ?? 0)
            : 0
        async let standHours: Int = needsStand
            ? ((try? await HealthKitManager.shared.fetchStandHours(on: date)) ?? 0)
            : 0

        let healthValues = await (waterAmount, sunlightMinutes, mindfulnessMinutes, standHours)
        guard !Task.isCancelled,
              calendar.isDate(selectedDate, inSameDayAs: date) else {
            return
        }

        let actionRecord = ActionRecordStore.shared.record(for: date)
        let context = DailyWellnessEvaluationContext(
            waterMl: healthValues.0,
            sunlightMinutes: healthValues.1,
            mindfulnessMinutes: healthValues.2,
            standHours: healthValues.3,
            actionRecord: actionRecord,
            now: Date()
        )
        _ = DailyWellnessStore.shared.refreshFromHealthData(on: date, context: context)
        reloadLocalPageData(for: date)
    }

    private func handleSelectedGoalChange() {
        guard !mascotAction.isCelebration, rewardFeedback == nil else { return }
        replayMascotAction()
    }

    @ViewBuilder
    private var recoveryPriorityCard: some View {
        if let plan = recoveryOrchestrationPlan {
            DailyRecoveryPlanCard(title: "今日优先", plan: plan)
        }
    }

    private var todayScore: Int {
        Int((store.completionRate(on: selectedDate, wellnessRecord: wellnessSummary.todayRecord) * 100).rounded())
    }

    private var activeGoals: [GoalItem] {
        store.activeGoals
    }

    private var selectedGoal: GoalItem? {
        if let selectedGoalID,
           let goal = activeGoals.first(where: { $0.id == selectedGoalID }) {
            return goal
        }
        return activeGoals.first
    }

    private var nextIncompleteGoal: GoalItem? {
        activeGoals.first {
            !store.progress(for: $0, on: selectedDate, wellnessRecord: wellnessSummary.todayRecord).isCompleted
        }
    }

    private var selectedDateTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return String(localized: "今天")
        }
        if calendar.isDateInYesterday(selectedDate) {
            return String(localized: "昨天")
        }
        return ChineseDateText.compactMonthDay(selectedDate)
    }

    private var selectedDateSubtitle: String {
        let completed = store.completedCount(on: selectedDate, wellnessRecord: wellnessSummary.todayRecord)
        if activeGoals.isEmpty {
            return String(localized: "等待设置目标")
        }
        return String(localized: "\(completed)/\(activeGoals.count) 完成 · \(todayScore) 分")
    }

    private var canMoveToNextDate: Bool {
        calendar.startOfDay(for: selectedDate) < calendar.startOfDay(for: Date())
    }

    private var goalsBackground: some View {
        Theme.Colors.pageBackground.ignoresSafeArea()
    }

    private var incompleteGoalCount: Int {
        max(
            activeGoals.count - store.completedCount(
                on: selectedDate,
                wellnessRecord: wellnessSummary.todayRecord
            ),
            0
        )
    }

    private var goalPageHeader: some View {
        BBPageHeader(title: "目标", subtitle: "把今天能完成的一小步，变成连续的节奏") {
            HStack(spacing: Theme.Spacing.compact) {
                Button {
                    showingReview = true
                } label: {
                    Image(systemName: "calendar")
                        .font(Theme.Typography.cardTitle)
                        .foregroundColor(Color(hex: "205A75"))
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.surface.opacity(0.82), in: Circle())
                        .overlay(Circle().stroke(Theme.Colors.surface, lineWidth: Theme.Stroke.standardWidth))
                        .shadow(color: Theme.Shadow.raised.color, radius: Theme.Shadow.raised.radius, x: 0, y: Theme.Shadow.raised.y)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("回顾目标")

                Button {
                    showingCreateGoal = true
                } label: {
                    Image(systemName: "plus")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "20D2BD"), Theme.Colors.mintGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: Theme.Stroke.standardWidth))
                        .shadow(color: Theme.Colors.mintGreen.opacity(0.24), radius: 12, x: 0, y: 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加目标")
            }
        }
        .padding(.horizontal, Theme.Spacing.hairline)
    }

    private var petHeroCard: some View {
        let stageTint = Color(hex: petGrowthStage.tintHex)

        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(activeGoals.isEmpty ? "等待完成" : mascotAction.title, systemImage: "target")
                        .font(Theme.Typography.label)
                        .foregroundColor(Color(hex: "176C78"))

                    Button {
                        showingPetEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.petState.name)
                                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Image(systemName: "pencil")
                                .font(.appSystem(size: 10, weight: .black))
                        }
                        .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Text("\(petGrowthStage.shortTitle) · \(companionDays) 天")
                        Text(verbatim: "·")
                        Text("\(incompleteGoalCount)") + Text(" ") + Text("待完成")
                    }
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "55746C"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 6)

                GoalMascotRoomStage(
                    action: mascotAction,
                    trigger: mascotActionTrigger,
                    growthStage: petGrowthStage,
                    level: store.petState.level,
                    size: 112,
                    onReplay: { triggerMascotAction(mascotAction, returnsToBaseline: mascotAction.isCelebration) }
                )
                .frame(width: 116, height: 104)
                .clipped()
            }

            HStack(spacing: 9) {
                Text("Lv.\(store.petState.level)")
                    .font(Theme.Typography.label)
                    .foregroundColor(stageTint)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.72))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.mintGreen, Color(hex: "91E7DC")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(petXPProgress))
                    }
                }
                .frame(height: 8)

                Text("\(store.petState.xp)/\(store.xpNeeded(for: store.petState.level)) XP")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)

                Label("\(store.petState.rewardCount)", systemImage: "gift.fill")
                    .font(Theme.Typography.label)
                    .foregroundColor(Color(hex: "FF914D"))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "DDF5EC"), Color(hex: "E9F1FF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.90), lineWidth: 1)
        )
        .shadow(color: Color(hex: "2B7184").opacity(0.08), radius: 18, x: 0, y: 9)
    }

    private var petGrowthCard: some View {
        let stage = petGrowthStage
        let tint = Color(hex: stage.tintHex)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stage.symbol)
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("成长等级")
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(petStageProgressText)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Lv.\(store.petState.level)")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                    Text("累计 \(store.totalEarnedXP()) XP")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            HStack(spacing: 5) {
                ForEach(GoalPetGrowthStage.allCases) { item in
                    petStageNode(item, currentStage: stage)
                }
            }

            if stage.next != nil {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "DFE8EF"))
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * CGFloat(store.stageProgress(for: store.petState.level)))
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 8) {
                Label("每日每项 +\(GoalsStore.xpPerGoal) XP", systemImage: "bolt.fill")
                Spacer(minLength: 8)
                Label("\(store.petState.rewardCount) 份奖励", systemImage: "gift.fill")
            }
            .font(Theme.Typography.label)
            .foregroundColor(Theme.Colors.textSecondary)

            Label(store.mascotCloudSyncStatus.title, systemImage: store.mascotCloudSyncStatus.systemImage)
                .font(Theme.Typography.label)
                .foregroundColor(
                    store.mascotCloudSyncStatus == .unavailable
                        ? Theme.Colors.textTertiary
                        : Theme.Colors.accentBlue
                )
                .accessibilityLabel(store.mascotCloudSyncStatus.title)
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private func petStageNode(_ stage: GoalPetGrowthStage, currentStage: GoalPetGrowthStage) -> some View {
        let reached = store.petState.level >= stage.minimumLevel
        let selected = stage == currentStage
        let tint = Color(hex: stage.tintHex)

        return VStack(spacing: 6) {
            Image(systemName: stage.symbol)
                .font(.appSystem(size: 11, weight: .black))
                .foregroundColor(reached ? .white : Theme.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(reached ? tint : Color(hex: "E7EDF1"), in: Circle())
                .overlay(Circle().stroke(selected ? tint.opacity(0.28) : .clear, lineWidth: 4))

            Text(stage.shortTitle)
                .font(.appSystem(size: 9, weight: .black, design: .rounded))
                .foregroundColor(selected ? tint : Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.title)，\(reached ? "已到达" : "\(stage.minimumLevel) 级解锁")")
    }

    private func rewardFeedbackBanner(_ reward: GoalPetReward) -> some View {
        let stage = GoalPetGrowthStage.stage(for: reward.currentLevel)
        let tint = Color(hex: stage.tintHex)

        return HStack(spacing: 12) {
            Image(systemName: reward.didLevelUp ? "sparkles" : "bolt.fill")
                .font(.appSystem(size: 16, weight: .black))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(reward.didLevelUp ? "升级到 Lv.\(reward.currentLevel)" : "+\(reward.xpGained) XP")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(reward.didLevelUp ? "\(store.petState.name) 进入新的成长节奏" : "今日这项目标经验已结算")
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func shiftSelectedDate(by value: Int) {
        guard let date = calendar.date(byAdding: .day, value: value, to: selectedDate) else { return }
        let normalized = calendar.startOfDay(for: date)
        guard normalized <= calendar.startOfDay(for: Date()) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            selectedDate = normalized
            selectedReviewDate = normalized
        }
    }

    private var dateNavigationCard: some View {
        HStack(spacing: 12) {
            Button {
                shiftSelectedDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 16, weight: .black))
                    .foregroundColor(Color(hex: "176B88"))
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.surface.opacity(0.96), in: Circle())
                    .shadow(color: Color(hex: "2A6980").opacity(0.09), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("前一天")

            HStack(spacing: 4) {
                Text(selectedDateTitle)
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                if canMoveToNextDate {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            let today = calendar.startOfDay(for: Date())
                            selectedDate = today
                            selectedReviewDate = today
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                            .font(.appSystem(size: 16, weight: .black))
                            .foregroundColor(Theme.Colors.mintGreen)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回到今天")
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                shiftSelectedDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 16, weight: .black))
                    .foregroundColor(canMoveToNextDate ? Color(hex: "176B88") : Color(hex: "83C6D3"))
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.surface.opacity(0.96), in: Circle())
                    .shadow(color: Color(hex: "2A6980").opacity(0.09), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveToNextDate)
            .accessibilityLabel("后一天")
            .accessibilityHint(canMoveToNextDate ? "" : "已经是今天")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var goalStatusStrip: some View {
        HStack(spacing: 10) {
            goalStatusTile(
                title: "目标槽位",
                value: "\(activeGoals.count)/\(GoalsStore.maxActiveGoals)",
                note: activeGoals.count >= GoalsStore.maxActiveGoals ? "已满" : "可继续添加",
                symbol: "square.grid.2x2.fill",
                tint: Color(hex: "5E7BFF")
            )

            goalStatusTile(
                title: "今日完成",
                value: "\(store.completedCount(on: selectedDate, wellnessRecord: wellnessSummary.todayRecord))",
                note: activeGoals.isEmpty ? "等待目标" : "个目标",
                symbol: "checkmark.seal.fill",
                tint: Theme.Colors.mintGreen
            )

            goalStatusTile(
                title: "下一奖励",
                value: "\(nextMilestoneScore)",
                note: todayScore >= 100 ? "已达成" : "目标分",
                symbol: "gift.fill",
                tint: Color(hex: "F4A259")
            )
        }
    }

    private func goalStatusTile(title: String, value: String, note: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(value)
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text(note)
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var todaySuggestionCard: some View {
        let goal = nextIncompleteGoal
        let tint = goal.map { Color(hex: $0.tintHex) } ?? Theme.Colors.mintGreen

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: goal?.symbol ?? "checkmark.seal.fill")
                .font(.appSystem(size: 17, weight: .black))
                .foregroundColor(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(goal.map { "下一步：\($0.title)" } ?? "今天目标已收满")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(todaySuggestionText)
                    .font(Theme.Typography.supporting)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let goal {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selectedGoalID = goal.id
                        if goal.linkedActionKind != nil {
                            openLinkedAction(for: goal)
                        } else {
                            performGoalToggle(goal)
                        }
                    }
                } label: {
                    Text(goal.linkedActionKind == nil ? "完成" : "去记录")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var todayGoalBoard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标看板")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("\(store.completedCount(on: selectedDate, wellnessRecord: wellnessSummary.todayRecord))/\(activeGoals.count) 已完成 · 目标分 \(todayScore)")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 6)

            dateNavigationCard

            Divider()
                .overlay(Theme.Colors.surfaceBorder)
                .padding(.horizontal, 18)

            if !activeGoals.isEmpty {
                goalBoardRewardRail
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                Divider()
                    .overlay(Theme.Colors.surfaceBorder)
                    .padding(.horizontal, 18)
            }

            if activeGoals.isEmpty {
                emptyGoalCard
                    .padding(18)
            } else {
                VStack(spacing: 0) {
                    ForEach(activeGoals) { goal in
                        goalRow(goal)
                        if goal.id != activeGoals.last?.id {
                            Divider()
                                .overlay(Theme.Colors.surfaceBorder)
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)

                if let selectedGoal {
                    selectedGoalDetail(selectedGoal)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                }
            }
        }
        .bbTintedSurface(
            tint: Theme.Colors.mintGreen,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous),
            tintStrength: 0.035,
            shadow: true
        )
    }

    private var goalBoardRewardRail: some View {
        Group {
            if activeGoals.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.appSystem(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "F4A259"))
                        .frame(width: 38, height: 38)
                        .background(Color(hex: "F4A259").opacity(0.12), in: Circle())
                    Text("添加目标后，每完成一项都会获得 \(GoalsStore.xpPerGoal) XP。")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            } else {
                HStack(alignment: .top, spacing: 5) {
                    ForEach(activeGoals) { goal in
                        let awarded = store.hasAwardedXP(for: goal.id, on: selectedDate)
                        let tint = Color(hex: goal.tintHex)

                        VStack(spacing: 6) {
                            Image(systemName: awarded ? "checkmark" : goal.symbol)
                                .font(.appSystem(size: 11, weight: .black))
                                .foregroundColor(awarded ? .white : tint)
                                .frame(width: 32, height: 32)
                                .background(awarded ? tint : tint.opacity(0.11), in: Circle())
                                .overlay(Circle().stroke(tint.opacity(awarded ? 0 : 0.18), lineWidth: 1))

                            Text(awarded ? "已领 \(GoalsStore.xpPerGoal)" : "+\(GoalsStore.xpPerGoal) XP")
                                .font(.appSystem(size: 9, weight: .black, design: .rounded))
                                .foregroundColor(awarded ? tint : Theme.Colors.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(goal.title)，\(awarded ? "已领取" : "可领取") \(GoalsStore.xpPerGoal) 经验")
                    }
                }
            }
        }
    }

    private var emptyGoalCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.appSystem(size: 22, weight: .black))
                .foregroundColor(Theme.Colors.mintGreen)
                .frame(width: 52, height: 52)
                .background(Theme.Colors.mintGreen.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(Theme.Colors.mintGreen.opacity(0.08), lineWidth: 5))

            Text("先设一个目标，今天的成长就从这里开始。")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Button {
                showingCreateGoal = true
            } label: {
                Label("添加目标", systemImage: "plus")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "1ED3BD"), Theme.Colors.mintGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Theme.Colors.mintGreen.opacity(0.18), radius: 9, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [Color(hex: "F7FBFD"), Color(hex: "F2F9FB")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func goalRow(_ goal: GoalItem) -> some View {
        let progress = store.progress(for: goal, on: selectedDate, wellnessRecord: wellnessSummary.todayRecord)
        let rate = store.progressRate(for: goal, on: selectedDate, wellnessRecord: wellnessSummary.todayRecord)
        let tint = Color(hex: goal.tintHex)
        let isSelected = selectedGoal?.id == goal.id
        let isLinked = goal.linkedActionKind != nil
        let isSyncedCompletion = goal.linkedActionKind.map {
            wellnessSummary.todayRecord.completedAction($0) != nil
        } ?? false

        return HStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    selectedGoalID = goal.id
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: goal.symbol)
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundColor(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(goal.title)
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Spacer(minLength: 8)

                            Text(progress.isCompleted ? "完成" : localizedPercentRatio(rate))
                                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(tint)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(hex: "DFE8EF"))
                                Capsule()
                                    .fill(tint)
                                    .frame(width: proxy.size.width * CGFloat(rate))
                            }
                        }
                        .frame(height: 8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedGoalID = goal.id
                    if isLinked {
                        openLinkedAction(for: goal)
                    } else {
                        performGoalToggle(goal)
                    }
                }
            } label: {
                Image(systemName: progress.isCompleted ? "checkmark.circle.fill" : isLinked ? "arrow.up.right.circle.fill" : "circle")
                    .font(.appSystem(size: 24, weight: .black))
                    .foregroundColor(progress.isCompleted || isLinked ? tint : Color(hex: "AAB8C8"))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSyncedCompletion)
            .opacity(isSyncedCompletion ? 0.82 : 1)
            .accessibilityLabel(progress.isCompleted ? "\(goal.title)已完成" : isLinked ? "前往记录\(goal.title)" : "完成\(goal.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(isSelected ? tint.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.20) : Color.clear, lineWidth: 1)
        )
    }

    private func selectedGoalDetail(_ goal: GoalItem) -> some View {
        let progress = store.progress(for: goal, on: selectedDate, wellnessRecord: wellnessSummary.todayRecord)
        let tint = Color(hex: goal.tintHex)
        let isLinked = goal.linkedActionKind != nil
        let isSyncedCompletion = goal.linkedActionKind.map {
            wellnessSummary.todayRecord.completedAction($0) != nil
        } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: goal.symbol)
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(goal.title) · \(progress.value)/\(goal.targetValue) \(goal.unit)")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(isSyncedCompletion ? "已由轻动作自动同步，目标分和伙伴经验已经更新。" : isLinked ? "前往行动页完成真实记录，目标进度和伙伴经验会自动同步。" : progress.isCompleted ? "今天已经喂到这一项，宠物经验和目标分都会更新。" : "可以直接完成，也可以用加减按钮逐步更新进度。")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if goal.linkedActionKind == nil, goal.targetValue > 1 {
                goalProgressControls(goal, progress: progress, tint: tint)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        if isLinked {
                            openLinkedAction(for: goal)
                        } else {
                            performGoalToggle(goal)
                        }
                    }
                } label: {
                    Text(isSyncedCompletion ? "已自动同步" : isLinked ? "去行动页记录" : progress.isCompleted ? "取消完成" : "完成目标")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSyncedCompletion)
                .opacity(isSyncedCompletion ? 0.68 : 1)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        store.deactivate(goal)
                        selectedGoalID = activeGoals.first?.id
                    }
                } label: {
                    Text("暂停")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tint.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Divider()
                .overlay(Theme.Colors.surfaceBorder)
        }
    }

    private func goalProgressControls(
        _ goal: GoalItem,
        progress: GoalProgressRecord,
        tint: Color
    ) -> some View {
        let step = goalProgressStep(for: goal)

        return HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    performGoalAdjustment(goal, by: -step)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundColor(progress.value > 0 ? tint : Theme.Colors.textTertiary)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(progress.value > 0 ? 0.12 : 0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(progress.value <= 0)
            .accessibilityLabel("减少\(goal.title)进度")

            VStack(spacing: 3) {
                Text("\(progress.value) / \(goal.targetValue)")
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("每次 \(step) \(goal.unit)")
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    performGoalAdjustment(goal, by: step)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundColor(progress.value < goal.targetValue ? .white : Theme.Colors.textTertiary)
                    .frame(width: 38, height: 38)
                    .background(progress.value < goal.targetValue ? tint : Color(hex: "E7EDF1"), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(progress.value >= goal.targetValue)
            .accessibilityLabel("增加\(goal.title)进度")
        }
        .padding(.horizontal, 4)
    }

    private var rewardMilestonesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("奖励节点")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(rewardMilestoneText)
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "sparkles")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(Color(hex: "F4A259"))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "F4A259").opacity(0.12), in: Circle())
            }

            HStack(spacing: 8) {
                ForEach([25, 50, 75, 100], id: \.self) { milestone in
                    rewardMilestoneNode(milestone)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "DFE8EF"))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.mintGreen, Color(hex: "F4A259")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, Double(todayScore) / 100))))
                }
            }
            .frame(height: 10)
        }
        .padding(18)
        .bbTintedSurface(
            tint: Color(hex: "F4A259"),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous),
            tintStrength: 0.07,
            shadow: true
        )
    }

    private func rewardMilestoneNode(_ milestone: Int) -> some View {
        let reached = todayScore >= milestone
        return VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(reached ? Theme.Colors.mintGreen : Color.white.opacity(0.76))
                    .frame(width: 38, height: 38)
                Image(systemName: reached ? "checkmark" : "gift")
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundColor(reached ? .white : Color(hex: "F4A259"))
            }
            Text("\(milestone)")
                .font(Theme.Typography.label)
                .foregroundColor(reached ? Theme.Colors.mintGreen : Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background((reached ? Theme.Colors.mintGreen : Color(hex: "F4A259")).opacity(reached ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reviewStrip: some View {
        let days = store.reviewDays(endingAt: selectedDate, wellnessSummary: wellnessSummary, count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("回顾")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Button("查看全部") {
                    showingReview = true
                }
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.mintGreen)
            }

            HStack(spacing: 8) {
                ForEach(days) { day in
                    Button {
                        selectedReviewDate = day.date
                        selectedDate = day.date
                    } label: {
                        VStack(spacing: 7) {
                            Text(ChineseDateText.compactMonthDay(day.date))
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            Text("\(day.score)")
                                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            Text("\(day.completed)/\(max(day.total, 1))")
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(calendar.isDate(day.date, inSameDayAs: selectedDate) ? .white : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(calendar.isDate(day.date, inSameDayAs: selectedDate) ? Theme.Colors.mintGreen : Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .bbTintedSurface(
            tint: Theme.Colors.mintGreen,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous),
            tintStrength: 0.07,
            shadow: true
        )
    }

    private var weeklyInsightCard: some View {
        let days = store.reviewDays(endingAt: selectedDate, wellnessSummary: wellnessSummary, count: 7)
        let average = days.isEmpty ? 0 : Int((Double(days.reduce(0) { $0 + $1.score }) / Double(days.count)).rounded())
        let best = days.max { $0.score < $1.score }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7 天洞察")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(weeklyInsightText(average: average, best: best))
                        .font(Theme.Typography.supporting)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(average)")
                        .font(.appSystem(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.mintGreen)
                    Text("均分")
                        .font(Theme.Typography.label)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        GeometryReader { proxy in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: "DFE8EF"))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(day.score >= 80 ? Theme.Colors.mintGreen : day.score >= 40 ? Color(hex: "F4A259") : Color(hex: "AAB8C8"))
                                    .frame(height: max(8, proxy.size.height * CGFloat(Double(day.score) / 100)))
                            }
                        }
                        .frame(height: 56)

                        Text(ChineseDateText.compactMonthDay(day.date))
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Button {
                showingLinkedReport = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("查看\(selectedDateTitle)报告")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.accentBlue)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Theme.Colors.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .bbTintedSurface(
            tint: Theme.Colors.accentBlue,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous),
            tintStrength: 0.07,
            shadow: true
        )
    }

    private var companionDays: Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: store.petState.createdAt),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return max(1, days + 1)
    }

    private var petGrowthStage: GoalPetGrowthStage {
        GoalPetGrowthStage.stage(for: store.petState.level)
    }

    private var petStageProgressText: String {
        guard let next = petGrowthStage.next else {
            return String(localized: "\(petGrowthStage.title) · 已到达最高成长阶段")
        }
        return String(localized: "\(petGrowthStage.title) · 距 \(next.title) 还差 \(max(0, next.minimumLevel - store.petState.level)) 级")
    }

    private var petXPProgress: Double {
        Double(store.petState.xp) / Double(max(store.xpNeeded(for: store.petState.level), 1))
    }

    private var todaySuggestionText: String {
        guard let goal = nextIncompleteGoal else {
            return activeGoals.isEmpty ? "先创建一个目标，宠物会从第一个完成开始成长。" : "今日目标已经完成，可以去回顾里看看最近 7 天节奏。"
        }
        if goal.linkedActionKind != nil {
            return String(localized: "这个目标已关联轻动作，完成后会同步更新目标分和宠物经验。")
        }
        return String(localized: "这是手动目标，点完成后会更新今日目标分、奖励节点和宠物经验。")
    }

    private var petMoodTitle: String {
        switch todayScore {
        case 80...:
            return String(localized: "状态很好")
        case 40..<80:
            return String(localized: "等你投喂")
        default:
            return activeGoals.isEmpty ? "等待目标" : "有点饿"
        }
    }

    private var petMoodSymbol: String {
        switch todayScore {
        case 80...:
            return "face.smiling"
        case 40..<80:
            return "pawprint.fill"
        default:
            return "bell.fill"
        }
    }

    private var petMoodTint: Color {
        switch todayScore {
        case 80...:
            return Theme.Colors.mintGreen
        case 40..<80:
            return Color(hex: "F4A259")
        default:
            return Color(hex: "FF7A59")
        }
    }

    private var nextMilestoneScore: Int {
        [25, 50, 75, 100].first { todayScore < $0 } ?? 100
    }

    private var nextRewardText: String {
        if activeGoals.isEmpty {
            return String(localized: "先创建一个目标")
        }
        if todayScore >= 100 {
            return String(localized: "今日奖励已收满")
        }
        return String(localized: "距奖励还差 \(max(0, nextMilestoneScore - todayScore)) 分")
    }

    private var rewardMilestoneText: String {
        if activeGoals.isEmpty {
            return String(localized: "设定目标后，完成度会点亮奖励节点。")
        }
        if todayScore >= 100 {
            return String(localized: "今天 4 个奖励节点已全部点亮。")
        }
        return String(localized: "下一个奖励节点：\(nextMilestoneScore) 分。")
    }

    private func weeklyInsightText(average: Int, best: GoalReviewDay?) -> String {
        if activeGoals.isEmpty {
            return String(localized: "先创建目标，7 天洞察会在这里生成。")
        }
        if average >= 80 {
            return String(localized: "最近 7 天平均 \(average) 分，目标节奏很稳。")
        }
        if let best, best.score > average {
            return String(localized: "最好的一天是 \(ChineseDateText.compactMonthDay(best.date))，拿到 \(best.score) 分，可以复用那天的节奏。")
        }
        return String(localized: "最近 7 天平均 \(average) 分，先保住一个最容易完成的目标。")
    }

    private func performGoalToggle(_ goal: GoalItem) {
        let reward = store.toggleGoal(
            goal,
            on: selectedDate,
            wellnessRecord: wellnessSummary.todayRecord
        )
        syncKnownCompletionSnapshot()
        guard let reward else { return }
        presentRewardFeedback(reward)
    }

    private func openLinkedAction(for goal: GoalItem) {
        guard let linkedActionKind = goal.linkedActionKind else { return }
        onOpenLinkedAction(linkedActionKind, selectedDate)
    }

    private func performGoalAdjustment(_ goal: GoalItem, by delta: Int) {
        let reward = store.adjustProgress(
            for: goal,
            by: delta,
            on: selectedDate,
            wellnessRecord: wellnessSummary.todayRecord
        )
        syncKnownCompletionSnapshot()
        guard let reward else { return }
        presentRewardFeedback(reward)
    }

    private func goalProgressStep(for goal: GoalItem) -> Int {
        switch goal.targetValue {
        case 100...:
            return max(10, goal.targetValue / 10)
        case 20..<100:
            return 5
        default:
            return 1
        }
    }

    private func presentRewardFeedback(_ reward: GoalPetReward) {
        triggerMascotAction(reward.didLevelUp ? .levelUp : .celebrate, returnsToBaseline: true)
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)) {
            rewardFeedback = reward
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: reward.didLevelUp
                ? "目标伙伴升级到 \(reward.currentLevel) 级"
                : "获得 \(reward.xpGained) 经验"
        )
        let feedbackID = reward.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard rewardFeedback?.id == feedbackID else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                rewardFeedback = nil
            }
        }
    }

    private func detectNewGoalCompletions(in wellnessRecord: DailyWellnessDayRecord) {
        let completedIDs = Set(
            activeGoals.compactMap { goal in
                store.progress(for: goal, on: selectedDate, wellnessRecord: wellnessRecord).isCompleted
                    ? goal.id
                    : nil
            }
        )

        guard hasPrimedCompletionSnapshot else {
            knownCompletedGoalIDs = completedIDs
            hasPrimedCompletionSnapshot = true
            return
        }

        let newlyCompleted = completedIDs.subtracting(knownCompletedGoalIDs)
        knownCompletedGoalIDs = completedIDs
        guard !newlyCompleted.isEmpty, rewardFeedback == nil else { return }
        triggerMascotAction(.celebrate, returnsToBaseline: true)
    }

    private func syncKnownCompletionSnapshot() {
        knownCompletedGoalIDs = Set(
            activeGoals.compactMap { goal in
                store.progress(
                    for: goal,
                    on: selectedDate,
                    wellnessRecord: wellnessSummary.todayRecord
                ).isCompleted ? goal.id : nil
            }
        )
        hasPrimedCompletionSnapshot = true
    }

    private func replayMascotAction() {
        triggerMascotAction(GoalMascotAction.baseline(for: selectedGoal), returnsToBaseline: false)
    }

    private func triggerMascotAction(_ action: GoalMascotAction, returnsToBaseline: Bool) {
        mascotAction = action
        mascotActionTrigger += 1

        guard returnsToBaseline else { return }
        let trigger = mascotActionTrigger
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == .levelUp ? 2.3 : 1.8)) {
            guard mascotActionTrigger == trigger else { return }
            mascotAction = GoalMascotAction.baseline(for: selectedGoal)
            mascotActionTrigger += 1
        }
    }

    private func syncSelections() {
        let currentSelectionIsActive = selectedGoalID.map { selectedID in
            activeGoals.contains { $0.id == selectedID }
        } ?? false
        guard !currentSelectionIsActive else { return }
        selectedGoalID = activeGoals.first?.id
    }
}

private enum GoalMascotAction: String, Equatable {
    case waiting
    case planning
    case hydration
    case movement
    case breathing
    case sunlight
    case windDown
    case celebrate
    case levelUp

    static func baseline(for goal: GoalItem?) -> GoalMascotAction {
        guard let goal else { return .waiting }
        switch goal.category {
        case .sleep: return .windDown
        case .movement: return .movement
        case .hydration: return .hydration
        case .recovery: return .breathing
        case .sunlight: return .sunlight
        case .custom: return .planning
        }
    }

    var isCelebration: Bool {
        self == .celebrate || self == .levelUp
    }

    var imageName: String {
        switch self {
        case .waiting, .planning: return "ActionHeaderMascot"
        case .hydration, .levelUp: return "VitalityHeaderMascot"
        case .movement: return "ActionFitnessMascot"
        case .breathing, .windDown: return "TodayPressureRelaxed"
        case .sunlight: return "ActionFeelingMascot"
        case .celebrate: return "ActionPeriodMascot"
        }
    }

    var title: String {
        switch self {
        case .waiting: return String(localized: "等你定目标")
        case .planning: return String(localized: "正在规划")
        case .hydration: return String(localized: "补充水分")
        case .movement: return String(localized: "活力运动")
        case .breathing: return String(localized: "深呼吸")
        case .sunlight: return String(localized: "晒晒太阳")
        case .windDown: return String(localized: "准备休息")
        case .celebrate: return String(localized: "完成啦")
        case .levelUp: return String(localized: "升级啦")
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "target"
        case .planning: return "pencil.and.list.clipboard"
        case .hydration: return "drop.fill"
        case .movement: return "figure.run"
        case .breathing: return "wind"
        case .sunlight: return "sun.max.fill"
        case .windDown: return "moon.stars.fill"
        case .celebrate: return "heart.fill"
        case .levelUp: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: return Color(hex: "7AA9C7")
        case .planning: return Color(hex: "5E7BFF")
        case .hydration: return Color(hex: "32ADE6")
        case .movement: return Color(hex: "58B88A")
        case .breathing: return Color(hex: "7AB7A8")
        case .sunlight: return Color(hex: "E6A345")
        case .windDown: return Color(hex: "737BD8")
        case .celebrate: return Color(hex: "D96A9E")
        case .levelUp: return Color(hex: "F4A259")
        }
    }

    var motion: GoalMascotMotion {
        switch self {
        case .waiting:
            return GoalMascotMotion(x: 0, y: 5, scale: 1.02, rotation: 1.2, duration: 2.2)
        case .planning:
            return GoalMascotMotion(x: 2, y: 5, scale: 1.025, rotation: -1.4, duration: 1.8)
        case .hydration:
            return GoalMascotMotion(x: 3, y: 7, scale: 1.035, rotation: -2.4, duration: 1.25)
        case .movement:
            return GoalMascotMotion(x: 17, y: 8, scale: 1.04, rotation: 3.2, duration: 0.64)
        case .breathing:
            return GoalMascotMotion(x: 0, y: 3, scale: 1.055, rotation: 0, duration: 2.35)
        case .sunlight:
            return GoalMascotMotion(x: 3, y: 6, scale: 1.04, rotation: 2.6, duration: 1.55)
        case .windDown:
            return GoalMascotMotion(x: 0, y: 2, scale: 1.02, rotation: -1.2, duration: 2.7)
        case .celebrate:
            return GoalMascotMotion(x: 5, y: 17, scale: 1.09, rotation: 7, duration: 0.58)
        case .levelUp:
            return GoalMascotMotion(x: 7, y: 20, scale: 1.12, rotation: -8, duration: 0.52)
        }
    }
}

private struct GoalMascotMotion {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double
    let duration: Double
}



private struct GoalMascotRoomStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    let action: GoalMascotAction
    let trigger: Int
    let growthStage: GoalPetGrowthStage
    let level: Int
    let size: CGFloat
    let onReplay: () -> Void

    private var motion: GoalMascotMotion { action.motion }
    private var growthTint: Color { Color(hex: growthStage.tintHex) }

    var body: some View {
        Button(action: onReplay) {
            ZStack {
                actionEffects

                Ellipse()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: size * 0.62, height: size * 0.10)
                    .blur(radius: 4)
                    .offset(y: size * 0.38)
                    .scaleEffect(x: reduceMotion ? 1 : (isAnimating ? 0.84 : 1.08))

                Image(action.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .id("\(action.rawValue)-\(trigger)")
                    .transition(.opacity.combined(with: .scale(scale: 0.90)))
                    .offset(
                        x: reduceMotion ? 0 : (isAnimating ? motion.x : -motion.x * 0.35),
                        y: reduceMotion ? 0 : (isAnimating ? -motion.y : motion.y * 0.30)
                    )
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? motion.scale : 0.985))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? motion.rotation : -motion.rotation * 0.45)))
                    .shadow(color: action.tint.opacity(0.14), radius: 10, x: 0, y: 7)

                Image(systemName: growthStage.symbol)
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(growthTint)
                    .frame(width: 31, height: 31)
                    .background(Theme.Colors.surface.opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(growthTint.opacity(0.18), lineWidth: 1))
                    .offset(x: size * 0.36, y: -size * 0.31)

                Text("Lv.\(level)")
                    .font(.appSystem(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(growthTint, in: Capsule())
                    .offset(x: -size * 0.34, y: size * 0.34)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: animationID) {
            isAnimating = false
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: motion.duration).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("目标伙伴，\(growthStage.title)，\(level) 级，\(action.title)")
        .accessibilityHint(reduceMotion ? "" : "轻点可重播动作")
    }

    private var animationID: String {
        "\(action.rawValue)-\(trigger)-\(reduceMotion)"
    }

    @ViewBuilder
    private var actionEffects: some View {
        switch action {
        case .hydration:
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "drop.fill")
                    .font(.appSystem(size: CGFloat(10 + index * 2), weight: .black))
                    .foregroundColor(action.tint.opacity(0.70))
                    .offset(
                        x: CGFloat(index - 1) * 47,
                        y: CGFloat(22 - index * 18) - (reduceMotion ? 0 : (isAnimating ? 20 : -2))
                    )
                    .opacity(reduceMotion ? 0.55 : (isAnimating ? 0.85 : 0.24))
            }
        case .movement:
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(action.tint.opacity(0.52 - Double(index) * 0.10))
                    .frame(width: CGFloat(30 - index * 5), height: 4)
                    .offset(x: -size * 0.43 - CGFloat(index * 5), y: CGFloat(index * 13 - 15))
                    .scaleEffect(x: reduceMotion ? 1 : (isAnimating ? 1.25 : 0.68), anchor: .trailing)
            }
        case .breathing:
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(action.tint.opacity(0.28 - Double(index) * 0.06), lineWidth: 2)
                    .frame(width: size * (0.62 + CGFloat(index) * 0.16), height: size * (0.62 + CGFloat(index) * 0.16))
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.08 : 0.88))
                    .opacity(reduceMotion ? 0.42 : (isAnimating ? 0.72 : 0.18))
            }
        case .sunlight:
            Image(systemName: "sun.max.fill")
                .font(.appSystem(size: 38, weight: .black))
                .foregroundColor(action.tint.opacity(0.82))
                .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 18 : -12)))
                .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.10 : 0.88))
                .offset(x: -size * 0.35, y: -size * 0.20)
        case .windDown:
            VStack(alignment: .leading, spacing: 1) {
                Text("z")
                Text("z").font(.appSystem(size: 14, weight: .black, design: .rounded))
                Text("z").font(.appSystem(size: 18, weight: .black, design: .rounded))
            }
            .font(.appSystem(size: 11, weight: .black, design: .rounded))
            .foregroundColor(action.tint.opacity(0.72))
            .offset(x: -size * 0.34, y: -size * 0.20 - (reduceMotion ? 0 : (isAnimating ? 8 : -4)))
        case .celebrate, .levelUp:
            ForEach(0..<6, id: \.self) { index in
                Image(systemName: index.isMultiple(of: 2) ? "sparkles" : "star.fill")
                    .font(.appSystem(size: CGFloat(9 + index % 3 * 3), weight: .black))
                    .foregroundColor(index.isMultiple(of: 2) ? action.tint : Color(hex: "F4A259"))
                    .offset(
                        x: CGFloat(cos(Double(index) * .pi / 3)) * size * 0.48,
                        y: CGFloat(sin(Double(index) * .pi / 3)) * size * 0.42
                    )
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.35 : 0.55))
                    .opacity(reduceMotion ? 0.66 : (isAnimating ? 0.95 : 0.20))
            }
        case .waiting, .planning:
            Circle()
                .trim(from: 0.08, to: 0.64)
                .stroke(action.tint.opacity(0.24), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.88, height: size * 0.88)
                .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 28 : -22)))
        }
    }

}

private struct CreateGoalSheet: View {
    var store: GoalsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: GoalCategory = .hydration
    @State private var customTitle = ""
    @State private var customValue = 1
    @State private var customUnit = "次"
    @State private var goalPendingDeletion: GoalItem?

    private var filteredPresets: [GoalPreset] {
        GoalPreset.defaults.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("创建目标")
                        .font(.appSystem(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("最多同时养成 \(GoalsStore.maxActiveGoals) 个目标，先选最容易坚持的一项。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)

                    categoryChips

                    if store.activeGoals.count >= GoalsStore.maxActiveGoals {
                        Text("当前最多同时养成 4 个目标。")
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "F4A259"))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "FFF6E8"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if !filteredPresets.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("推荐目标")
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                            ForEach(filteredPresets) { preset in
                                presetRow(preset)
                            }
                        }
                    }

                    customGoalBox

                    if !store.pausedGoals.isEmpty {
                        pausedGoalsSection
                    }
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                }
            }
            .alert(item: $goalPendingDeletion) { goal in
                Alert(
                    title: Text("删除“\(goal.title)”？"),
                    message: Text("历史目标进度会一并删除，已经获得的伙伴经验会保留。"),
                    primaryButton: .destructive(Text("删除")) {
                        store.delete(goal)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GoalCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Label(category.title, systemImage: category.symbol)
                            .font(.appSystem(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(selectedCategory == category ? .white : Color(hex: category.tintHex))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selectedCategory == category ? Color(hex: category.tintHex) : Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func presetRow(_ preset: GoalPreset) -> some View {
        let alreadyAdded = store.hasActivePreset(preset)
        let disabled = store.activeGoals.count >= GoalsStore.maxActiveGoals || alreadyAdded
        return Button {
            store.addPreset(preset)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.symbol)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: preset.category.tintHex))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: preset.category.tintHex).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("\(preset.targetValue) \(preset.unit) · \(preset.detail)")
                        .font(Theme.Typography.supporting)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                if alreadyAdded {
                    Text("已添加")
                        .font(Theme.Typography.label)
                        .foregroundColor(Color(hex: "B8C4D4"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "EEF2F7"), in: Capsule())
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.appSystem(size: 22, weight: .black))
                        .foregroundColor(disabled ? Color(hex: "B8C4D4") : Color(hex: preset.category.tintHex))
                }
            }
            .padding(14)
            .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(disabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var customGoalBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义目标")
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            TextField("目标名称", text: $customTitle)
                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                .padding(12)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Stepper("目标 \(customValue)", value: $customValue, in: 1...999)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                TextField("单位", text: $customUnit)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 72)
                    .padding(10)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                store.addCustom(title: customTitle, category: selectedCategory == .custom ? .custom : selectedCategory, targetValue: customValue, unit: customUnit)
                customTitle = ""
            } label: {
                Text("添加自定义目标")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Colors.mintGreen, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.activeGoals.count >= GoalsStore.maxActiveGoals)
            .opacity(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.activeGoals.count >= GoalsStore.maxActiveGoals ? 0.55 : 1)
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var pausedGoalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已暂停")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text("\(store.pausedGoals.count)")
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            ForEach(store.pausedGoals) { goal in
                HStack(spacing: 12) {
                    Image(systemName: goal.symbol)
                        .font(.appSystem(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: goal.tintHex))
                        .frame(width: 38, height: 38)
                        .background(Color(hex: goal.tintHex).opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.title)
                            .font(.appSystem(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text("\(goal.targetValue) \(goal.unit)")
                            .font(Theme.Typography.label)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        store.activate(goal)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.appSystem(size: 11, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                store.activeGoals.count < GoalsStore.maxActiveGoals
                                    ? Theme.Colors.mintGreen
                                    : Color(hex: "B8C4D4"),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.activeGoals.count >= GoalsStore.maxActiveGoals)
                    .accessibilityLabel("恢复\(goal.title)")

                    Menu {
                        Button(role: .destructive) {
                            goalPendingDeletion = goal
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.appSystem(size: 14, weight: .black))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("管理\(goal.title)")
                }
                .padding(12)
                .background(Theme.Colors.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct GoalReviewSheet: View {
    var store: GoalsStore
    let wellnessSummary: DailyWellnessSummary
    @Binding var selectedDate: Date
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("回顾")
                        .font(.appSystem(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    dateChips

                    VStack(spacing: 10) {
                        ForEach(store.activeGoals) { goal in
                            reviewRow(goal)
                        }
                    }
                }
                .padding(18)
            }
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
        }
    }

    private var dateChips: some View {
        let days = store.reviewDays(endingAt: Date(), wellnessSummary: wellnessSummary, count: 14)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    Button {
                        selectedDate = day.date
                    } label: {
                        VStack(spacing: 6) {
                            Text(ChineseDateText.compactMonthDay(day.date))
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            Text("\(day.score)")
                                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundColor(calendar.isDate(day.date, inSameDayAs: selectedDate) ? .white : Theme.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(calendar.isDate(day.date, inSameDayAs: selectedDate) ? Theme.Colors.mintGreen : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func reviewRow(_ goal: GoalItem) -> some View {
        let wellnessRecord = DailyWellnessStore.shared.record(on: selectedDate)
        let progress = store.progress(for: goal, on: selectedDate, wellnessRecord: wellnessRecord)
        let rate = store.progressRate(for: goal, on: selectedDate, wellnessRecord: wellnessRecord)
        let tint = Color(hex: goal.tintHex)

        return HStack(spacing: 12) {
            Image(systemName: goal.symbol)
                .font(.appSystem(size: 15, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(goal.title)
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text(progress.isCompleted ? "完成" : localizedPercentRatio(rate))
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "DFE8EF"))
                        Capsule().fill(tint).frame(width: proxy.size.width * CGFloat(rate))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PetNameSheet: View {
    var store: GoalsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("设置伙伴")
                        .font(.appSystem(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("给目标伙伴取个名字，完成目标时它会一起成长。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                HStack(spacing: 14) {
                    Image("ActionHeaderMascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 74, height: 74)
                        .padding(10)
                        .background(Theme.Colors.surface.opacity(0.82), in: Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("伙伴名称", text: $draftName)
                            .font(.appSystem(size: 18, weight: .black, design: .rounded))
                            .padding(13)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text("最多 12 个字符")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                Button {
                    store.renamePet(draftName)
                    dismiss()
                } label: {
                    Text("保存")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.Colors.mintGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
            .onAppear {
                draftName = store.petState.name
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GoalsView()
    }
}
