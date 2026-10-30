import SwiftData
import XCTest
@testable import BioBalance

nonisolated final class PersonalLifeExperimentEngineTests: XCTestCase {
    @MainActor func testMissingFeelingsAreNotTreatedAsZeroAndDirectionNeedsSamples() {
        var record = PersonalLifeExperimentRecord(kind: .bedtimeRoutine, startDate: day(0))
        record.checkIns = [checkIn(0, true, 4), checkIn(1, false, nil), checkIn(5, true, 5)]

        let summary = PersonalLifeExperimentEngine.make(record: record, calendar: calendar)

        XCTAssertEqual(summary.recordedDays, 3)
        XCTAssertEqual(summary.followedDays, 2)
        XCTAssertEqual(summary.feelingSampleCount, 2)
        XCTAssertEqual(summary.averageFeeling, 4.5)
        XCTAssertNil(summary.direction)
    }

    @MainActor func testComparesFirstThreeAndLastThreeWithHalfPointThreshold() {
        var record = PersonalLifeExperimentRecord(kind: .caffeineCutoff, startDate: day(0))
        record.checkIns = [checkIn(0, true, 2), checkIn(2, true, 3), checkIn(4, true, 4), checkIn(6, true, 5)]
        XCTAssertEqual(PersonalLifeExperimentEngine.make(record: record, calendar: calendar).direction, .higher)
    }

    @MainActor private var calendar: Calendar { Calendar(identifier: .gregorian) }
    @MainActor private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_760_000_000))!
    }
    @MainActor private func checkIn(_ offset: Int, _ followed: Bool, _ score: Int?) -> PersonalLifeExperimentCheckIn {
        PersonalLifeExperimentCheckIn(date: day(offset), followedPlan: followed, feelingScore: score, updatedAt: day(offset))
    }
}

nonisolated final class PersonalLifeExperimentStoreTests: XCTestCase {
    @MainActor func testOnlyOneActiveExperimentAndSameDayCheckInIsReplaced() throws {
        let container = try MianyuModelContainer.make(isStoredInMemoryOnly: true)
        let store = PersonalLifeExperimentStore(calendar: Calendar(identifier: .gregorian), container: container)
        let start = Date(timeIntervalSince1970: 1_760_000_000)

        XCTAssertNotNil(store.start(kind: .caffeineCutoff, on: start))
        XCTAssertNil(store.start(kind: .bedtimeRoutine, on: start))
        XCTAssertNotNil(store.saveCheckIn(on: start, followedPlan: false, feelingScore: nil))
        XCTAssertNotNil(store.saveCheckIn(on: start, followedPlan: true, feelingScore: 4))

        let active = try XCTUnwrap(store.activeExperiment())
        XCTAssertEqual(active.checkIns.count, 1)
        XCTAssertTrue(active.checkIns[0].followedPlan)
        XCTAssertEqual(active.checkIns[0].feelingScore, 4)
    }

    @MainActor func testExperimentAutoCompletesWhenEighthDayBeginsWithoutFinalCheckIn() throws {
        let container = try MianyuModelContainer.make(isStoredInMemoryOnly: true)
        let calendar = Calendar(identifier: .gregorian)
        let store = PersonalLifeExperimentStore(calendar: calendar, container: container)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let eighthDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))

        XCTAssertNotNil(store.start(kind: .daylight20Minutes, on: start))
        XCTAssertNil(store.activeExperiment(on: eighthDay))

        let archived = try XCTUnwrap(store.allRecords().first)
        XCTAssertEqual(archived.status, .completed)
        XCTAssertEqual(archived.endedAt, eighthDay)
    }
}
