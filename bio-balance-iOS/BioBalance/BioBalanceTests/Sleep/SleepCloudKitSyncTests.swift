import CloudKit
import XCTest
@testable import BioBalance

nonisolated final class SleepCloudKitSyncTests: XCTestCase {
    @MainActor func testDecodeSummaryRestoresOnlyWhitelistedCloudFields() throws {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudKitDataPolicy.Zone.sleep,
            ownerName: CKCurrentUserDefaultName
        )
        let record = CKRecord(
            recordType: CloudKitDataPolicy.RecordType.sleepSession,
            recordID: CKRecord.ID(recordName: "session-1", zoneID: zoneID)
        )
        let sourceDate = Date(timeIntervalSince1970: 1_760_000_000)
        let start = sourceDate.addingTimeInterval(22 * 3_600)
        let end = start.addingTimeInterval(7.5 * 3_600)
        let updatedAt = end.addingTimeInterval(120)

        record["sessionId"] = "session-1" as CKRecordValue
        record["sourceDate"] = sourceDate as CKRecordValue
        record["startTime"] = start as CKRecordValue
        record["endTime"] = end as CKRecordValue
        record["sleepDurationMinutes"] = Int64(450) as CKRecordValue
        record["sleepScore"] = Int64(86) as CKRecordValue
        record["sleepContinuityScore"] = Int64(82) as CKRecordValue
        record["watchConfidence"] = 0.91 as CKRecordValue
        record["analysisVersion"] = "sleep-analysis-v2" as CKRecordValue
        record["deviceSource"] = "watch" as CKRecordValue
        record["recommendationCode"] = "sleep_keep_schedule" as CKRecordValue
        record["riskFlag"] = SleepInsightRiskFlag.monitor.rawValue as CKRecordValue
        record[CloudKitDataPolicy.MetadataField.createdAt] = end as CKRecordValue
        record[CloudKitDataPolicy.MetadataField.updatedAt] = updatedAt as CKRecordValue
        record[CloudKitDataPolicy.MetadataField.schemaVersion] = Int64(2) as CKRecordValue

        let summary = try XCTUnwrap(SleepCloudKitSyncService.decodeSummary(record))

        XCTAssertEqual(summary.sessionId, "session-1")
        XCTAssertEqual(summary.sleepDurationMinutes, 450)
        XCTAssertEqual(summary.sleepScore, 86)
        XCTAssertEqual(summary.sleepContinuityScore, 82)
        XCTAssertEqual(summary.watchConfidence, 0.91, accuracy: 0.001)
        XCTAssertEqual(summary.updatedAt, updatedAt)
        XCTAssertEqual(summary.insight.recommendationCode, "sleep_keep_schedule")
        XCTAssertEqual(summary.insight.riskFlag, .monitor)
        XCTAssertEqual(summary.stageSummary, .empty)
        XCTAssertEqual(summary.snoreSummary, .empty)
    }

    @MainActor func testDecodeSummaryRejectsIncompleteRecord() {
        let record = CKRecord(recordType: CloudKitDataPolicy.RecordType.sleepSession)
        record["sleepScore"] = Int64(80) as CKRecordValue

        XCTAssertNil(SleepCloudKitSyncService.decodeSummary(record))
    }
}
