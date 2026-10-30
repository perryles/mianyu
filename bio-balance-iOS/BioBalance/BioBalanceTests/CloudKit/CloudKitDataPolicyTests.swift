import Foundation
import XCTest
@testable import BioBalance

nonisolated final class CloudKitDataPolicyTests: XCTestCase {
    @MainActor func testEveryCloudFeatureDefaultsOnWithoutOverridingSavedChoices() throws {
        let suiteName = "CloudKitDataPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = [
            CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled,
            CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled,
            CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled,
            CloudKitDataPolicy.PreferenceKey.pregnancySyncEnabled,
            CloudKitDataPolicy.PreferenceKey.goalMascotSyncEnabled,
            CloudKitDataPolicy.PreferenceKey.onboardingPreferenceSyncEnabled,
            CloudKitDataPolicy.PreferenceKey.socialSharingEnabled
        ]

        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        keys.forEach { XCTAssertTrue(defaults.bool(forKey: $0), "\($0) should default to on") }

        keys.forEach { defaults.set(false, forKey: $0) }
        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        keys.forEach { XCTAssertFalse(defaults.bool(forKey: $0), "\($0) must preserve an explicit choice") }
    }

    @MainActor func testGoalMascotSchemaUsesStablePolicyIdentifiers() {
        XCTAssertEqual(CloudKitDataPolicy.Zone.goalMascot, "BioBalanceMascotZone")
        XCTAssertEqual(CloudKitDataPolicy.RecordType.goalMascotProfile, "BBMascotProfile")
        XCTAssertEqual(CloudKitDataPolicy.RecordType.goalMascotXPGrant, "BBMascotXPGrant")

        XCTAssertEqual(GoalMascotCloudSchema.zoneName, CloudKitDataPolicy.Zone.goalMascot)
        XCTAssertEqual(
            GoalMascotCloudSchema.profileRecordType,
            CloudKitDataPolicy.RecordType.goalMascotProfile
        )
        XCTAssertEqual(
            GoalMascotCloudSchema.grantRecordType,
            CloudKitDataPolicy.RecordType.goalMascotXPGrant
        )
    }

    @MainActor func testOnboardingPreferenceSchemaUsesStablePrivateIdentifiers() {
        XCTAssertEqual(
            CloudKitDataPolicy.Zone.onboardingPreference,
            "BioBalanceOnboardingPreferenceZone"
        )
        XCTAssertEqual(
            CloudKitDataPolicy.RecordType.onboardingPreference,
            "BBOnboardingPreference"
        )
    }

    @MainActor func testAccountBindingKeysRemainStable() {
        XCTAssertEqual(
            CloudKitDataPolicy.AccountBindingKey.drinkExperience,
            "drinkExperienceStore.cloud-account.v1"
        )
        XCTAssertEqual(
            CloudKitDataPolicy.AccountBindingKey.sleepSummary,
            "sleep.monitoring.cloud-account.v1"
        )
        XCTAssertEqual(
            CloudKitDataPolicy.AccountBindingKey.medicationHealth,
            "icloud.medication-health-sync.account.v1"
        )
        XCTAssertEqual(
            CloudKitDataPolicy.AccountBindingKey.goalMascot,
            "goals.store.mascot.cloud-account.v1"
        )
        XCTAssertEqual(
            CloudKitDataPolicy.AccountBindingKey.onboardingPreference,
            "onboarding.preference.cloud-account.v1"
        )
        XCTAssertEqual(
            CloudKitDataPolicy.AccountBindingKey.socialSharing,
            "social.sharing.cloud-account.v1"
        )
    }

    @MainActor func testPublicProfileUsesDedicatedBusinessRecordID() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        XCTAssertEqual(
            CloudKitDataPolicy.PublicProfile.recordName(id: id),
            "profile.12345678-1234-1234-1234-1234567890ab"
        )
    }

    @MainActor func testPublicProfileIdentityRequiresRecordOwnerAndCreatorToMatch() {
        XCTAssertEqual(
            CloudKitDataPolicy.PublicProfile.validatedOwnerUserRecordName(
                profileRecordName: "profile.12345678-1234-1234-1234-1234567890ab",
                declaredOwnerUserRecordName: "cloud-user-1",
                creatorUserRecordName: "cloud-user-1"
            ),
            "cloud-user-1"
        )

        let invalidIdentities: [(String, String?, String?)] = [
            ("cloud-user-1", "cloud-user-1", "cloud-user-1"),
            ("profile.cloud-user-1", "cloud-user-1", "cloud-user-1"),
            ("profile.12345678-1234-1234-1234-1234567890ab", "cloud-user-2", "cloud-user-1"),
            ("profile.12345678-1234-1234-1234-1234567890ab", "cloud-user-1", "cloud-user-2"),
            ("profile.12345678-1234-1234-1234-1234567890ab", "cloud-user-1", nil)
        ]
        for identity in invalidIdentities {
            XCTAssertNil(
                CloudKitDataPolicy.PublicProfile.validatedOwnerUserRecordName(
                    profileRecordName: identity.0,
                    declaredOwnerUserRecordName: identity.1,
                    creatorUserRecordName: identity.2
                )
            )
        }
    }

    @MainActor func testCheckedInSchemaContainsEveryApplicationRecordType() throws {
        let schema = try checkedInSchema()
        let recordTypes = [
            CloudKitDataPolicy.RecordType.drinkExperience,
            CloudKitDataPolicy.RecordType.goalMascotProfile,
            CloudKitDataPolicy.RecordType.goalMascotXPGrant,
            CloudKitDataPolicy.RecordType.sleepSession,
            CloudKitDataPolicy.RecordType.medicationPrescription,
            CloudKitDataPolicy.RecordType.pregnancyProfile,
            CloudKitDataPolicy.RecordType.pregnancyWeightEntry,
            CloudKitDataPolicy.RecordType.fetalMovementEntry,
            CloudKitDataPolicy.RecordType.healthShareRoot,
            CloudKitDataPolicy.RecordType.collaborativeTodoList,
            CloudKitDataPolicy.RecordType.collaborativeTodoItem,
            CloudKitDataPolicy.RecordType.userProfile
        ]

        for recordType in recordTypes {
            XCTAssertTrue(
                schema.contains("RECORD TYPE \(recordType) ("),
                "Missing CloudKit schema for \(recordType)"
            )
        }
    }

    @MainActor func testPrivateAndSharedRecordTypesAreNotWorldReadable() throws {
        let schema = try checkedInSchema()
        let privateAndSharedTypes = [
            CloudKitDataPolicy.RecordType.drinkExperience,
            CloudKitDataPolicy.RecordType.goalMascotProfile,
            CloudKitDataPolicy.RecordType.goalMascotXPGrant,
            CloudKitDataPolicy.RecordType.sleepSession,
            CloudKitDataPolicy.RecordType.medicationPrescription,
            CloudKitDataPolicy.RecordType.pregnancyProfile,
            CloudKitDataPolicy.RecordType.pregnancyWeightEntry,
            CloudKitDataPolicy.RecordType.fetalMovementEntry,
            CloudKitDataPolicy.RecordType.healthShareRoot,
            CloudKitDataPolicy.RecordType.collaborativeTodoList,
            CloudKitDataPolicy.RecordType.collaborativeTodoItem
        ]

        for recordType in privateAndSharedTypes {
            let definition = try XCTUnwrap(recordDefinition(recordType, in: schema))
            XCTAssertFalse(
                definition.contains("GRANT READ TO \"_world\""),
                "Sensitive record type \(recordType) must not be world-readable"
            )
            XCTAssertTrue(definition.contains("GRANT READ TO \"_creator\""))
        }
    }

    @MainActor func testPublicProfileSchemaContainsQueryableIdentityAndLookupFields() throws {
        let schema = try checkedInSchema()
        let definition = try XCTUnwrap(
            recordDefinition(CloudKitDataPolicy.RecordType.userProfile, in: schema)
        )

        XCTAssertTrue(definition.contains("handle STRING QUERYABLE"))
        XCTAssertTrue(definition.contains("isSearchable INT64 QUERYABLE"))
        XCTAssertTrue(definition.contains("ownerUserRecordName STRING QUERYABLE"))
        XCTAssertTrue(definition.contains("GRANT READ TO \"_world\""))
    }

    @MainActor func testSleepSchemaExcludesLegacyDetailedAnalysisFields() throws {
        let schema = try checkedInSchema()
        let definition = try XCTUnwrap(
            recordDefinition(CloudKitDataPolicy.RecordType.sleepSession, in: schema)
        )

        XCTAssertFalse(schema.contains("RECORD TYPE BBSleepInsight ("))
        for forbiddenField in [
            "deepSleepMinutesEstimated",
            "lightSleepMinutesEstimated",
            "remSleepMinutesEstimated",
            "snoreDurationMinutes",
            "snoreFrequencyPerHour",
            "userIdHash"
        ] {
            XCTAssertFalse(definition.contains(forbiddenField))
        }
    }

    @MainActor private func checkedInSchema() throws -> String {
        // 工程根：BioBalanceTests/CloudKit → BioBalanceTests → BioBalance → bio-balance-iOS。
        // CloudKit schema 文件（BioBalanceDevelopment.ckdb）位于工程根的 CloudKit/ 目录。
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let schemaURL = projectDirectory
            .appendingPathComponent("CloudKit/BioBalanceDevelopment.ckdb")
        return try String(contentsOf: schemaURL, encoding: .utf8)
    }

    @MainActor private func recordDefinition(_ recordType: String, in schema: String) -> String? {
        let marker = "RECORD TYPE \(recordType) ("
        guard let start = schema.range(of: marker),
              let end = schema.range(of: "\n);", range: start.upperBound..<schema.endIndex) else {
            return nil
        }
        return String(schema[start.lowerBound..<end.upperBound])
    }
}
