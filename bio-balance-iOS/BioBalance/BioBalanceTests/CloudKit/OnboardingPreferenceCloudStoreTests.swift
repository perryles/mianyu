import CloudKit
import Foundation
import XCTest
@testable import BioBalance

nonisolated final class OnboardingPreferenceCloudStoreTests: XCTestCase {
    private enum Field {
        static let focusAreas = "focusAreas"
        static let healthGoals = "healthGoals"
        static let age = "age"
        static let weightKg = "weightKg"
        static let gender = "gender"
        static let fitnessLevel = "fitnessLevel"

        static let all = [focusAreas, healthGoals, age, weightKg, gender, fitnessLevel]
    }

    @MainActor private var suiteName: String!
    @MainActor private var defaults: UserDefaults!
    @MainActor private var store: OnboardingPreferenceCloudStore!

    @MainActor override func setUp() async throws {
        try await super.setUp()
        suiteName = "OnboardingPreferenceCloudStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = OnboardingPreferenceCloudStore(defaults: defaults)
    }

    @MainActor override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    @MainActor func testEncodeLocalRemovesSkippedFieldsFromExistingRecord() {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(updatedAt, forKey: OnboardingPreferenceCloudStore.LocalKey.updatedAt)
        let record = makeRecord()
        record[Field.focusAreas] = ["sleep"] as CKRecordValue
        record[Field.healthGoals] = ["sleep_better"] as CKRecordValue
        record[Field.age] = Int64(25) as CKRecordValue
        record[Field.weightKg] = 60.0 as CKRecordValue
        record[Field.gender] = "女性" as CKRecordValue
        record[Field.fitnessLevel] = Int64(3) as CKRecordValue

        store.encodeLocal(into: record)

        for field in Field.all {
            XCTAssertNil(record[field], "Skipped field \(field) must be removed from CloudKit")
        }
        XCTAssertEqual(record[CloudKitDataPolicy.MetadataField.updatedAt] as? Date, updatedAt)
    }

    @MainActor func testEncodeLocalDistinguishesConfirmedEmptyCollectionsFromSkippedFields() {
        defaults.set("", forKey: OnboardingPreferenceCloudStore.LocalKey.focusAreas)
        defaults.set(
            "sleep_better,unknown,sleep_better",
            forKey: OnboardingPreferenceCloudStore.LocalKey.healthGoals
        )
        defaults.set(28, forKey: OnboardingPreferenceCloudStore.LocalKey.age)
        defaults.set(67.5, forKey: OnboardingPreferenceCloudStore.LocalKey.weightKg)
        defaults.set("其他", forKey: OnboardingPreferenceCloudStore.LocalKey.gender)
        defaults.set(4, forKey: OnboardingPreferenceCloudStore.LocalKey.fitnessLevel)
        defaults.set(Date(), forKey: OnboardingPreferenceCloudStore.LocalKey.updatedAt)
        let record = makeRecord()

        store.encodeLocal(into: record)

        XCTAssertEqual(record[Field.focusAreas] as? [String], [])
        XCTAssertEqual(record[Field.healthGoals] as? [String], ["sleep_better"])
        XCTAssertEqual(record[Field.age] as? Int64, 28)
        XCTAssertEqual(record[Field.weightKg] as? Double, 67.5)
        XCTAssertEqual(record[Field.gender] as? String, "其他")
        XCTAssertEqual(record[Field.fitnessLevel] as? Int64, 4)
    }

    @MainActor func testApplyRemoteClearsLocalValuesWhenFieldsAreMissingOrLegacyPlaceholders() {
        seedEveryLocalPreference()
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let record = makeRecord()
        record[Field.age] = Int64(0) as CKRecordValue
        record[Field.weightKg] = 0.0 as CKRecordValue
        record[Field.gender] = "" as CKRecordValue
        record[Field.fitnessLevel] = Int64(0) as CKRecordValue
        record[CloudKitDataPolicy.MetadataField.updatedAt] = updatedAt as CKRecordValue

        store.applyRemote(record)

        for key in localPreferenceKeys {
            XCTAssertNil(defaults.object(forKey: key), "Missing remote field must clear local key \(key)")
        }
        XCTAssertEqual(
            defaults.object(forKey: OnboardingPreferenceCloudStore.LocalKey.updatedAt) as? Date,
            updatedAt
        )
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedFirstLaunchOnboarding"))
    }

    @MainActor func testApplyRemotePreservesConfirmedEmptyCollectionsAndValidScalars() {
        let record = makeRecord()
        record[Field.focusAreas] = [] as CKRecordValue
        record[Field.healthGoals] = ["move_more", "unknown"] as CKRecordValue
        record[Field.age] = Int64(42) as CKRecordValue
        record[Field.weightKg] = 72.5 as CKRecordValue
        record[Field.gender] = "男性" as CKRecordValue
        record[Field.fitnessLevel] = Int64(5) as CKRecordValue

        store.applyRemote(record)

        XCTAssertEqual(defaults.string(forKey: OnboardingPreferenceCloudStore.LocalKey.focusAreas), "")
        XCTAssertEqual(defaults.string(forKey: OnboardingPreferenceCloudStore.LocalKey.healthGoals), "move_more")
        XCTAssertEqual(defaults.integer(forKey: OnboardingPreferenceCloudStore.LocalKey.age), 42)
        XCTAssertEqual(defaults.double(forKey: OnboardingPreferenceCloudStore.LocalKey.weightKg), 72.5)
        XCTAssertEqual(defaults.string(forKey: OnboardingPreferenceCloudStore.LocalKey.gender), "男性")
        XCTAssertEqual(defaults.integer(forKey: OnboardingPreferenceCloudStore.LocalKey.fitnessLevel), 5)
    }

    @MainActor private var localPreferenceKeys: [String] {
        [
            OnboardingPreferenceCloudStore.LocalKey.focusAreas,
            OnboardingPreferenceCloudStore.LocalKey.healthGoals,
            OnboardingPreferenceCloudStore.LocalKey.age,
            OnboardingPreferenceCloudStore.LocalKey.weightKg,
            OnboardingPreferenceCloudStore.LocalKey.gender,
            OnboardingPreferenceCloudStore.LocalKey.fitnessLevel
        ]
    }

    @MainActor private func seedEveryLocalPreference() {
        defaults.set("sleep", forKey: OnboardingPreferenceCloudStore.LocalKey.focusAreas)
        defaults.set("sleep_better", forKey: OnboardingPreferenceCloudStore.LocalKey.healthGoals)
        defaults.set(25, forKey: OnboardingPreferenceCloudStore.LocalKey.age)
        defaults.set(60.0, forKey: OnboardingPreferenceCloudStore.LocalKey.weightKg)
        defaults.set("女性", forKey: OnboardingPreferenceCloudStore.LocalKey.gender)
        defaults.set(3, forKey: OnboardingPreferenceCloudStore.LocalKey.fitnessLevel)
    }

    @MainActor private func makeRecord() -> CKRecord {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudKitDataPolicy.Zone.onboardingPreference,
            ownerName: CKCurrentUserDefaultName
        )
        return CKRecord(
            recordType: CloudKitDataPolicy.RecordType.onboardingPreference,
            recordID: CKRecord.ID(recordName: "current-onboarding-preference", zoneID: zoneID)
        )
    }
}
