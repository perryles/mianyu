import CloudKit
import Foundation

/// 首次引导偏好的本地优先私有云同步。
/// CloudKit 只保存用户主动确认的少量结构化字段，不保存 HealthKit 样本或自由文本。
@MainActor
final class OnboardingPreferenceCloudStore {
    static let shared = OnboardingPreferenceCloudStore()

    enum LocalKey {
        static let focusAreas = "onboarding_focus_areas"
        static let healthGoals = "onboarding_health_goals"
        static let age = "onboarding_age"
        static let weightKg = "onboarding_weight_kg"
        static let gender = "onboarding_gender"
        static let fitnessLevel = "onboarding_fitness_level"
        static let updatedAt = "onboarding_preferences_updated_at"
    }

    private enum Field {
        static let focusAreas = "focusAreas"
        static let healthGoals = "healthGoals"
        static let age = "age"
        static let weightKg = "weightKg"
        static let gender = "gender"
        static let fitnessLevel = "fitnessLevel"
    }

    private static let recordName = "current-onboarding-preference"
    private static let schemaVersion: Int64 = 1
    private static let allowedFocusAreas: Set<String> = [
        "sleep", "stress", "activity", "heart", "nutrition", "body"
    ]
    private static let allowedHealthGoals: Set<String> = [
        "sleep_better", "recover_better", "move_more", "build_habits"
    ]
    private static let allowedGenders: Set<String> = ["女性", "男性", "其他"]

    private let defaults: UserDefaults
    private let container: CKContainer

    init(
        defaults: UserDefaults = .standard,
        container: CKContainer = CloudKitDataPolicy.makeContainer()
    ) {
        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        self.defaults = defaults
        self.container = container
    }

    /// 合并远端与本机单例记录。较新的 `updatedAt` 胜出；无本地资料时只恢复远端。
    /// 返回 false 只代表云同步未完成，本机资料始终保留。
    func synchronize() async -> Bool {
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.onboardingPreferenceSyncEnabled) else {
            return true
        }

        do {
            guard !Task.isCancelled else { return false }
            guard try await container.accountStatus() == .available else { return false }
            let accountName = try await container.userRecordID().recordName
            guard validateAccountBinding(accountName) else { return false }

            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: CloudKitDataPolicy.Zone.onboardingPreference,
                ownerName: CKCurrentUserDefaultName
            )
            let recordID = CKRecord.ID(recordName: Self.recordName, zoneID: zoneID)
            let remoteRecord: CKRecord?
            do {
                remoteRecord = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                remoteRecord = nil
            }
            guard !Task.isCancelled else { return false }

            if let remoteRecord,
               remoteUpdatedAt(remoteRecord) > localUpdatedAt {
                applyRemote(remoteRecord)
                defaults.set(accountName, forKey: CloudKitDataPolicy.AccountBindingKey.onboardingPreference)
                return true
            }

            guard localUpdatedAt != .distantPast else {
                // 仅打开应用不创建空 zone，也不建立账户绑定；有远端记录或本机资料时才落云。
                return true
            }

            guard try await container.userRecordID().recordName == accountName else { return false }
            guard !Task.isCancelled else { return false }
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            let record = remoteRecord ?? CKRecord(
                recordType: CloudKitDataPolicy.RecordType.onboardingPreference,
                recordID: recordID
            )
            encodeLocal(into: record)
            _ = try await database.save(record)

            guard !Task.isCancelled else { return false }
            guard try await container.userRecordID().recordName == accountName else { return false }
            defaults.set(accountName, forKey: CloudKitDataPolicy.AccountBindingKey.onboardingPreference)
            return true
        } catch {
            return false
        }
    }

    private var localUpdatedAt: Date {
        defaults.object(forKey: LocalKey.updatedAt) as? Date ?? .distantPast
    }

    private func validateAccountBinding(_ accountName: String) -> Bool {
        guard let boundAccount = defaults.string(
            forKey: CloudKitDataPolicy.AccountBindingKey.onboardingPreference
        ) else {
            return true
        }
        guard boundAccount == accountName else {
            defaults.removeObject(forKey: CloudKitDataPolicy.AccountBindingKey.onboardingPreference)
            defaults.set(false, forKey: CloudKitDataPolicy.PreferenceKey.onboardingPreferenceSyncEnabled)
            return false
        }
        return true
    }

    private func remoteUpdatedAt(_ record: CKRecord) -> Date {
        record[CloudKitDataPolicy.MetadataField.updatedAt] as? Date ?? .distantPast
    }

    func encodeLocal(into record: CKRecord) {
        encodePreferenceArray(
            forKey: LocalKey.focusAreas,
            field: Field.focusAreas,
            allowed: Self.allowedFocusAreas,
            into: record
        )
        encodePreferenceArray(
            forKey: LocalKey.healthGoals,
            field: Field.healthGoals,
            allowed: Self.allowedHealthGoals,
            into: record
        )
        encodeInteger(
            forKey: LocalKey.age,
            field: Field.age,
            validRange: 13...100,
            into: record
        )
        encodeDouble(
            forKey: LocalKey.weightKg,
            field: Field.weightKg,
            validRange: 30...200,
            into: record
        )

        if let gender = defaults.string(forKey: LocalKey.gender),
           Self.allowedGenders.contains(gender) {
            record[Field.gender] = gender as CKRecordValue
        } else {
            record[Field.gender] = nil
        }

        encodeInteger(
            forKey: LocalKey.fitnessLevel,
            field: Field.fitnessLevel,
            validRange: 1...5,
            into: record
        )
        record[CloudKitDataPolicy.MetadataField.updatedAt] = localUpdatedAt as CKRecordValue
        record[CloudKitDataPolicy.MetadataField.schemaVersion] = Self.schemaVersion as CKRecordValue
        if record[CloudKitDataPolicy.MetadataField.createdAt] == nil {
            record[CloudKitDataPolicy.MetadataField.createdAt] = localUpdatedAt as CKRecordValue
        }
    }

    func applyRemote(_ record: CKRecord) {
        applyRemotePreferenceArray(
            record[Field.focusAreas] as? [String],
            forKey: LocalKey.focusAreas,
            allowed: Self.allowedFocusAreas
        )
        applyRemotePreferenceArray(
            record[Field.healthGoals] as? [String],
            forKey: LocalKey.healthGoals,
            allowed: Self.allowedHealthGoals
        )

        if let age = record[Field.age] as? Int64, (13...100).contains(age) {
            defaults.set(Int(age), forKey: LocalKey.age)
        } else {
            defaults.removeObject(forKey: LocalKey.age)
        }
        if let weight = record[Field.weightKg] as? Double, (30...200).contains(weight) {
            defaults.set(weight, forKey: LocalKey.weightKg)
        } else {
            defaults.removeObject(forKey: LocalKey.weightKg)
        }
        if let gender = record[Field.gender] as? String,
           Self.allowedGenders.contains(gender) {
            defaults.set(gender, forKey: LocalKey.gender)
        } else {
            defaults.removeObject(forKey: LocalKey.gender)
        }
        if let level = record[Field.fitnessLevel] as? Int64, (1...5).contains(level) {
            defaults.set(Int(level), forKey: LocalKey.fitnessLevel)
        } else {
            defaults.removeObject(forKey: LocalKey.fitnessLevel)
        }
        defaults.set(remoteUpdatedAt(record), forKey: LocalKey.updatedAt)
        // 云端存在有效偏好记录即代表用户已完成引导，避免新设备重复采集。
        defaults.set(true, forKey: "hasCompletedFirstLaunchOnboarding")
    }

    private func encodePreferenceArray(
        forKey key: String,
        field: String,
        allowed: Set<String>,
        into record: CKRecord
    ) {
        guard defaults.object(forKey: key) != nil else {
            record[field] = nil
            return
        }

        record[field] = preferenceArray(forKey: key, allowed: allowed) as CKRecordValue
    }

    private func encodeInteger(
        forKey key: String,
        field: String,
        validRange: ClosedRange<Int>,
        into record: CKRecord
    ) {
        guard defaults.object(forKey: key) != nil else {
            record[field] = nil
            return
        }

        let value = defaults.integer(forKey: key)
        guard validRange.contains(value) else {
            record[field] = nil
            return
        }
        record[field] = Int64(value) as CKRecordValue
    }

    private func encodeDouble(
        forKey key: String,
        field: String,
        validRange: ClosedRange<Double>,
        into record: CKRecord
    ) {
        guard defaults.object(forKey: key) != nil else {
            record[field] = nil
            return
        }

        let value = defaults.double(forKey: key)
        guard value.isFinite, validRange.contains(value) else {
            record[field] = nil
            return
        }
        record[field] = value as CKRecordValue
    }

    private func applyRemotePreferenceArray(
        _ values: [String]?,
        forKey key: String,
        allowed: Set<String>
    ) {
        guard let values else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(
            sanitizedValues(values, allowed: allowed).joined(separator: ","),
            forKey: key
        )
    }

    private func preferenceArray(forKey key: String, allowed: Set<String>) -> [String] {
        let values = (defaults.string(forKey: key) ?? "")
            .split(separator: ",")
            .map(String.init)
        return sanitizedValues(values, allowed: allowed)
    }

    private func sanitizedValues(_ values: [String], allowed: Set<String>) -> [String] {
        Array(Set(values).intersection(allowed)).sorted()
    }
}
