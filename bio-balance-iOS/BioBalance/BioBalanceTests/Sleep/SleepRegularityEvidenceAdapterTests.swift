import XCTest
@testable import BioBalance

nonisolated final class SleepRegularityEvidenceAdapterTests: XCTestCase {
    @MainActor private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor func testAcrossMidnightBedtimesStayClose() throws {
        let evidence = SleepRegularityEvidenceAdapter().resolve(
            currentBedtime: try date(year: 2026, month: 8, day: 10, hour: 0, minute: 20),
            recentBedtimes: [
                try date(year: 2026, month: 8, day: 6, hour: 23, minute: 50),
                try date(year: 2026, month: 8, day: 8, hour: 0, minute: 0),
                try date(year: 2026, month: 8, day: 9, hour: 0, minute: 10)
            ],
            calendar: calendar
        )

        XCTAssertEqual(
            try XCTUnwrap(evidence.bedtimeDeviationMinutes),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(evidence.referenceNightCount, 3)
    }

    @MainActor func testFewerThanThreePriorNightsRemainUnavailable() throws {
        let evidence = SleepRegularityEvidenceAdapter().resolve(
            currentBedtime: try date(year: 2026, month: 8, day: 10, hour: 0, minute: 20),
            recentBedtimes: [
                try date(year: 2026, month: 8, day: 8, hour: 0, minute: 0),
                try date(year: 2026, month: 8, day: 9, hour: 0, minute: 10)
            ],
            calendar: calendar
        )

        XCTAssertNil(evidence.bedtimeDeviationMinutes)
        XCTAssertEqual(evidence.referenceNightCount, 2)
    }

    @MainActor func testCurrentAndFutureSamplesDoNotLeakIntoBaseline() throws {
        let current = try date(year: 2026, month: 8, day: 10, hour: 0, minute: 20)
        let evidence = SleepRegularityEvidenceAdapter().resolve(
            currentBedtime: current,
            recentBedtimes: [
                try date(year: 2026, month: 8, day: 6, hour: 23, minute: 50),
                try date(year: 2026, month: 8, day: 8, hour: 0, minute: 0),
                try date(year: 2026, month: 8, day: 9, hour: 0, minute: 10),
                current,
                try date(year: 2026, month: 8, day: 11, hour: 0, minute: 20)
            ],
            calendar: calendar
        )

        XCTAssertEqual(
            try XCTUnwrap(evidence.bedtimeDeviationMinutes),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(evidence.referenceNightCount, 3)
    }

    @MainActor func testDuplicateSessionsOnOneCircadianDayCountAsOneNight() throws {
        let evidence = SleepRegularityEvidenceAdapter().resolve(
            currentBedtime: try date(year: 2026, month: 8, day: 10, hour: 0, minute: 20),
            recentBedtimes: [
                try date(year: 2026, month: 8, day: 7, hour: 23, minute: 55),
                try date(year: 2026, month: 8, day: 8, hour: 0, minute: 5),
                try date(year: 2026, month: 8, day: 9, hour: 0, minute: 10)
            ],
            calendar: calendar
        )

        XCTAssertNil(evidence.bedtimeDeviationMinutes)
        XCTAssertEqual(evidence.referenceNightCount, 2)
    }

    @MainActor private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
