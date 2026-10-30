import Foundation
import SwiftData

nonisolated struct DrinkStampRecord: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Status: String, Codable, Sendable {
        case pending
        case confirmed
        case locationUnavailable
    }

    let id: String
    var storeName: String
    var cityName: String?
    var drinkName: String
    var capturedAt: Date
    var photoFileID: Int64?
    var photoURL: String?
    var cutoutFileID: Int64?
    var cutoutURL: String?
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?
    var status: Status
    var isGeneratedFromRecognition: Bool
    var aiProviderID: String? = nil
    var aiModel: String? = nil
    var aiConfidence: Double? = nil
    /// 用于私有库跨设备合并；旧版本记录缺少该字段时回退到 `capturedAt`。
    var updatedAt: Date? = nil

    var aiSourceLabel: String? {
        formattedAIRecordSource(providerID: aiProviderID, model: aiModel)
    }
}

nonisolated struct DrinkCalendarDay: Codable, Hashable, Sendable, Identifiable {
    var id: String { dateKey }
    let dateKey: String
    let dayNumber: Int
    let weekdayIndex: Int
    let hasRecord: Bool
    let thumbnailURL: String?
    let recordCount: Int
    let inCurrentMonth: Bool
}

nonisolated struct DrinkMonthSummary: Codable, Hashable, Sendable {
    let monthKey: String
    let displayTitle: String
    let cupCount: Int
    let storeCount: Int
    let cityCount: Int
    let calendarDays: [DrinkCalendarDay]
    let stamps: [DrinkStampRecord]
}

nonisolated enum MealSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast:
            return String(localized: "早餐")
        case .lunch:
            return String(localized: "午餐")
        case .dinner:
            return String(localized: "晚餐")
        case .snack:
            return String(localized: "加餐")
        }
    }
}

nonisolated enum MealNutritionSource: String, Codable, CaseIterable, Sendable {
    case aiEstimate
    case userEntered
    case foodDatabase
    case healthKit

    var title: String {
        switch self {
        case .aiEstimate: String(localized: "AI 估算")
        case .userEntered: String(localized: "用户输入")
        case .foodDatabase: String(localized: "食品数据库")
        case .healthKit: String(localized: "Apple 健康")
        }
    }
}

nonisolated struct MealFoodItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var name: String
    var calories: Int
    /// 宏量营养素按份量估算的克数；旧记录与未提供估算的来源解码为 nil。
    var proteinGrams: Double? = nil
    var carbohydrateGrams: Double? = nil
    var fatGrams: Double? = nil
    var fiberGrams: Double? = nil
    var servingAmount: Double? = nil
    var servingUnit: String? = nil
    var confidence: Double? = nil
    var nutritionSource: MealNutritionSource? = nil
    var wasEditedByUser: Bool = false

    var normalizedSource: MealNutritionSource { nutritionSource ?? .aiEstimate }

    func scaled(to newAmount: Double) -> MealFoodItem {
        guard let servingAmount, servingAmount > 0, newAmount >= 0 else { return self }
        let ratio = newAmount / servingAmount
        var copy = self
        copy.servingAmount = newAmount
        copy.calories = Int((Double(calories) * ratio).rounded())
        copy.proteinGrams = proteinGrams.map { $0 * ratio }
        copy.carbohydrateGrams = carbohydrateGrams.map { $0 * ratio }
        copy.fatGrams = fatGrams.map { $0 * ratio }
        copy.fiberGrams = fiberGrams.map { $0 * ratio }
        copy.wasEditedByUser = true
        return copy
    }
}

nonisolated struct MealNutritionSummary: Equatable, Sendable {
    let calories: Int
    let proteinGrams: Double
    let carbohydrateGrams: Double
    let fatGrams: Double
    let fiberGrams: Double

    static func calculate(from foods: [MealFoodItem]) -> Self {
        foods.reduce(Self(calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fiberGrams: 0)) { value, food in
            Self(
                calories: value.calories + max(0, food.calories),
                proteinGrams: value.proteinGrams + max(0, food.proteinGrams ?? 0),
                carbohydrateGrams: value.carbohydrateGrams + max(0, food.carbohydrateGrams ?? 0),
                fatGrams: value.fatGrams + max(0, food.fatGrams ?? 0),
                fiberGrams: value.fiberGrams + max(0, food.fiberGrams ?? 0)
            )
        }
    }
}

nonisolated struct MealRecognitionRecord: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var mealSlot: MealSlot
    var recognizedFoods: [MealFoodItem]
    var estimatedCalories: Int
    var photoFileID: Int64?
    var photoURL: String?
    var capturedAt: Date
    var locationSummary: String?
    var aiProviderID: String? = nil
    var aiModel: String? = nil
    var aiConfidence: Double? = nil
    var photoLocalFilename: String? = nil
    var thumbnailLocalFilename: String? = nil
    var wasEditedByUser: Bool = false
    /// 用于私有库跨设备合并；旧版本记录缺少该字段时回退到 `capturedAt`。
    var updatedAt: Date? = nil

    var aiSourceLabel: String? {
        formattedAIRecordSource(providerID: aiProviderID, model: aiModel)
    }

    var nutritionSummary: MealNutritionSummary { .calculate(from: recognizedFoods) }
}

nonisolated private func formattedAIRecordSource(providerID: String?, model: String?) -> String? {
    let providerID = providerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !providerID.isEmpty else { return nil }
    let providerName = providerID == AIProviderID.qwen.rawValue ? "阿里云千问" : providerID
    let model = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return model.isEmpty ? providerName : "\(providerName) · \(model)"
}

final class DrinkExperienceStore {
    static let shared = DrinkExperienceStore(cloudRepository: .shared)

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let calendar = Calendar.current
    private let cloudRepository: DrinkExperienceCloudRepository?
    private var isSynchronizingPrivateCloud = false
    private let drinkKey = "drinkExperienceStore.v1"
    private let mealKey = "mealRecognitionStore.v1"
    private let domain = "drink-experience"
    private let drinkKind = "drink"
    private let mealKind = "meal"
    private let cloudAccountKey = CloudKitDataPolicy.AccountBindingKey.drinkExperience

    private struct DrinkPayload: Codable {
        var stamps: [DrinkStampRecord]
    }

    private struct MealPayload: Codable {
        var records: [MealRecognitionRecord]
    }

    init(
        defaults: UserDefaults = .standard,
        cloudRepository: DrinkExperienceCloudRepository? = nil,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        self.cloudRepository = cloudRepository
        records = SwiftDataRecordStore(container: container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func saveStamp(_ record: DrinkStampRecord) {
        var record = record
        record.updatedAt = Date()
        guard let payload = try? encoder.encode(record) else { return }
        let didSave = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: drinkKind,
                occurredAt: record.capturedAt,
                updatedAt: record.updatedAt ?? record.capturedAt,
                payload: payload
            ),
            keepingNewest: 365
        )
        guard didSave else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
        schedulePrivateCloudSynchronization()
    }

    func allStamps() -> [DrinkStampRecord] {
        loadDrinkPayload().stamps.sorted { $0.capturedAt > $1.capturedAt }
    }

    func summary(for month: Date) -> DrinkMonthSummary {
        let monthInterval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 31 * 86_400)
        let monthRecords = allStamps().filter { monthInterval.contains($0.capturedAt) }
        let grouped = Dictionary(grouping: monthRecords, by: { dayKey(for: $0.capturedAt) })
        let stores = Set(monthRecords.map(\.storeName).filter { !$0.isEmpty })
        let cities = Set(monthRecords.compactMap(\.cityName).filter { !$0.isEmpty })
        let calendarDays = makeCalendarDays(for: month, groupedRecords: grouped)

        return DrinkMonthSummary(
            monthKey: monthKey(for: month),
            displayTitle: monthDisplayTitle(for: month),
            cupCount: monthRecords.count,
            storeCount: stores.count,
            cityCount: cities.count,
            calendarDays: calendarDays,
            stamps: monthRecords
        )
    }

    func saveMealRecord(_ record: MealRecognitionRecord) {
        var record = record
        record.updatedAt = Date()
        guard let payload = try? encoder.encode(record) else { return }
        let didSave = records.upsert(
            LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: mealKind,
                occurredAt: record.capturedAt,
                updatedAt: record.updatedAt ?? record.capturedAt,
                payload: payload
            ),
            keepingNewest: 365
        )
        guard didSave else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
        schedulePrivateCloudSynchronization()
    }

    func allMealRecords() -> [MealRecognitionRecord] {
        loadMealPayload().records.sorted { $0.capturedAt > $1.capturedAt }
    }

    func mealRecords(from start: Date, to end: Date, slot: MealSlot? = nil) -> [MealRecognitionRecord] {
        allMealRecords().filter { record in
            record.capturedAt >= start && record.capturedAt < end && (slot == nil || record.mealSlot == slot)
        }
    }

    @discardableResult
    func deleteMealRecord(id: String) -> Bool {
        var payload = loadMealPayload()
        let oldCount = payload.records.count
        payload.records.removeAll { $0.id == id }
        guard payload.records.count != oldCount else { return false }
        saveMealPayload(payload)
        MealPhotoStore.shared.removeFiles(forRecordID: id)
        schedulePrivateCloudSynchronization()
        return true
    }

    func meals(on date: Date) -> [MealRecognitionRecord] {
        allMealRecords().filter { calendar.isDate($0.capturedAt, inSameDayAs: date) }
    }

    func todayMealSummary(on date: Date = Date()) -> (totalCalories: Int, slots: [MealSlot: MealRecognitionRecord]) {
        let daily = meals(on: date)
        var slots: [MealSlot: MealRecognitionRecord] = [:]
        for record in daily.sorted(by: { $0.capturedAt > $1.capturedAt }) {
            if slots[record.mealSlot] == nil {
                slots[record.mealSlot] = record
            }
        }
        let total = daily.reduce(0) { $0 + max(0, $1.estimatedCalories) }
        return (total, slots)
    }

    func defaultMealSlot(for date: Date = Date()) -> MealSlot {
        let hour = calendar.component(.hour, from: date)
        if hour >= 5 && hour < 11 {
            return .breakfast
        }
        if hour < 15 {
            return .lunch
        }
        if hour < 17 { return .snack }
        if hour < 22 { return .dinner }
        return .snack
    }

    /// 合并当前 iCloud 用户私有库中的结构化记录；网络或账号不可用时保留本地数据。
    @discardableResult
    func synchronizePrivateCloud() async -> Bool {
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled),
              let cloudRepository,
              !isSynchronizingPrivateCloud else { return false }
        isSynchronizingPrivateCloud = true
        defer { isSynchronizingPrivateCloud = false }
        do {
            let currentAccountIdentifier = try await cloudRepository.currentAccountIdentifier()
            if let previousAccountIdentifier = defaults.string(forKey: cloudAccountKey),
               previousAccountIdentifier != currentAccountIdentifier {
                // 换 Apple ID 时保留本地真值并撤销自动同步。用户再次开启开关后，
                // 才把本机记录视为允许同步到新账号的数据。
                defaults.set(false, forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled)
                defaults.removeObject(forKey: cloudAccountKey)
                return false
            }

            let snapshot = try await cloudRepository.synchronize(
                localDrinks: allStamps(),
                localMeals: allMealRecords()
            )
            saveDrinkPayload(DrinkPayload(stamps: snapshot.drinks))
            saveMealPayload(MealPayload(records: snapshot.meals))
            defaults.set(currentAccountIdentifier, forKey: cloudAccountKey)
            return true
        } catch {
            return false
        }
    }

    private func schedulePrivateCloudSynchronization() {
        guard cloudRepository != nil,
              defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled) else { return }
        Task { @MainActor in
            await synchronizePrivateCloud()
        }
    }

    private func makeCalendarDays(
        for month: Date,
        groupedRecords: [String: [DrinkStampRecord]]
    ) -> [DrinkCalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay) else {
            return []
        }

        let start = firstWeekInterval.start
        let end = lastWeekInterval.end
        var days: [DrinkCalendarDay] = []
        var cursor = start
        while cursor < end {
            let weekday = calendar.component(.weekday, from: cursor)
            let dayNumber = calendar.component(.day, from: cursor)
            let inMonth = calendar.isDate(cursor, equalTo: month, toGranularity: .month)
            let records = groupedRecords[dayKey(for: cursor)] ?? []
            days.append(
                DrinkCalendarDay(
                    dateKey: dayKey(for: cursor),
                    dayNumber: dayNumber,
                    weekdayIndex: weekday,
                    hasRecord: !records.isEmpty,
                    thumbnailURL: records.first?.cutoutURL ?? records.first?.photoURL,
                    recordCount: records.count,
                    inCurrentMonth: inMonth
                )
            )
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return days
    }

    private func monthDisplayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private func monthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func loadDrinkPayload() -> DrinkPayload {
        guard let rows = records.records(domain: domain, kind: drinkKind) else {
            guard let data = defaults.data(forKey: drinkKey),
                  let payload = try? decoder.decode(DrinkPayload.self, from: data) else {
                return DrinkPayload(stamps: [])
            }
            return payload
        }
        return DrinkPayload(
            stamps: rows.compactMap { try? decoder.decode(DrinkStampRecord.self, from: $0.payload) }
        )
    }

    private func saveDrinkPayload(_ payload: DrinkPayload) {
        let seeds = payload.stamps.compactMap(makeDrinkSeed)
        guard seeds.count == payload.stamps.count,
              records.replace(domain: domain, kind: drinkKind, with: seeds) else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
    }

    private func loadMealPayload() -> MealPayload {
        guard let rows = records.records(domain: domain, kind: mealKind) else {
            guard let data = defaults.data(forKey: mealKey),
                  let payload = try? decoder.decode(MealPayload.self, from: data) else {
                return MealPayload(records: [])
            }
            return payload
        }
        return MealPayload(
            records: rows.compactMap { try? decoder.decode(MealRecognitionRecord.self, from: $0.payload) }
        )
    }

    private func saveMealPayload(_ payload: MealPayload) {
        let seeds = payload.records.compactMap(makeMealSeed)
        guard seeds.count == payload.records.count,
              records.replace(domain: domain, kind: mealKind, with: seeds) else { return }
        NotificationCenter.default.post(name: .profileVitalityRecordsDidChange, object: self)
    }

    private func migrateLegacyDataIfNeeded() {
        migrateLegacyDrinksIfNeeded()
        migrateLegacyMealsIfNeeded()
    }

    private func migrateLegacyDrinksIfNeeded() {
        let migrationID = "drinkExperienceStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: drinkKey)
            return
        }
        let legacyData = defaults.data(forKey: drinkKey)
        let legacy: [DrinkStampRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(DrinkPayload.self, from: legacyData) else { return }
            legacy = payload.stamps
        } else {
            legacy = []
        }
        let seeds = legacy.compactMap(makeDrinkSeed)
        guard seeds.count == legacy.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: drinkKey)
    }

    private func migrateLegacyMealsIfNeeded() {
        let migrationID = "mealRecognitionStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: mealKey)
            return
        }
        let legacyData = defaults.data(forKey: mealKey)
        let legacy: [MealRecognitionRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(MealPayload.self, from: legacyData) else { return }
            legacy = payload.records
        } else {
            legacy = []
        }
        let seeds = legacy.compactMap(makeMealSeed)
        guard seeds.count == legacy.count,
              records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: mealKey)
    }

    private func makeDrinkSeed(_ record: DrinkStampRecord) -> LocalDataRecordSeed? {
        guard let data = try? encoder.encode(record) else { return nil }
        return LocalDataRecordSeed(
            domain: domain,
            recordID: record.id,
            kind: drinkKind,
            occurredAt: record.capturedAt,
            updatedAt: record.updatedAt ?? record.capturedAt,
            payload: data
        )
    }

    private func makeMealSeed(_ record: MealRecognitionRecord) -> LocalDataRecordSeed? {
        guard let data = try? encoder.encode(record) else { return nil }
        return LocalDataRecordSeed(
            domain: domain,
            recordID: record.id,
            kind: mealKind,
            occurredAt: record.capturedAt,
            updatedAt: record.updatedAt ?? record.capturedAt,
            payload: data
        )
    }
}
