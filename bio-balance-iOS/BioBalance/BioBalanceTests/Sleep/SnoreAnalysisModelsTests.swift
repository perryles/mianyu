import XCTest
@testable import BioBalance

nonisolated final class SnoreAnalysisModelsTests: XCTestCase {
    @MainActor func testSessionMapsEventsIntoMeasuredSleepStages() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = makeSummary(
            id: "night-1",
            start: start,
            segments: [
                makeSegment(start: start.addingTimeInterval(600), intensity: .low),
                makeSegment(start: start.addingTimeInterval(4_000), intensity: .medium)
            ]
        )
        let stages = [
            SleepStage(stage: "Core", duration: 60, startDate: start, endDate: start.addingTimeInterval(3_600)),
            SleepStage(stage: "REM", duration: 60, startDate: start.addingTimeInterval(3_600), endDate: start.addingTimeInterval(7_200))
        ]

        let session = try XCTUnwrap(SnoreSession.make(from: summary, stages: stages))

        XCTAssertEqual(session.eventCount, 2)
        XCTAssertEqual(session.stageCorrelation.first(where: { $0.stage == "浅睡" })?.eventCount, 1)
        XCTAssertEqual(session.stageCorrelation.first(where: { $0.stage == "REM" })?.eventCount, 1)
    }

    @MainActor func testLocalStoreKeepsNewestUniqueHistory() async throws {
        let suiteName = "SnoreAnalysisModelsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalSleepSessionStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeSummary(id: "first", start: start, segments: [makeSegment(start: start, intensity: .low)])
        let second = makeSummary(id: "second", start: start.addingTimeInterval(86_400), segments: [makeSegment(start: start.addingTimeInterval(86_400), intensity: .high)])

        await store.save(summary: first)
        await store.save(summary: second)
        await store.save(summary: first)
        let history = await store.recentSummaries(limit: 10)

        XCTAssertEqual(history.map(\.sessionId), ["second", "first"])
    }

    @MainActor private func makeSummary(id: String, start: Date, segments: [SnoreSegmentSummary]) -> SleepSessionSummary {
        SleepSessionSummary(
            sessionId: id,
            sourceDate: start,
            startTime: start,
            endTime: start.addingTimeInterval(8 * 3_600),
            sleepDurationMinutes: 480,
            sleepScore: 80,
            sleepContinuityScore: 82,
            stageSummary: .empty,
            snoreSummary: SnoreAnalysisSummary(
                snoreDetected: true,
                snoreDurationMinutes: Double(segments.count),
                snoreFrequencyPerHour: Double(segments.count) / 8,
                intensity: .medium,
                disturbanceScore: 28,
                riskFlag: .monitor,
                segments: segments,
                histogram: [segments.count, 0, 0, 0, 0, 0]
            ),
            insight: .placeholder,
            watchConfidence: 0.8,
            deviceSource: "test",
            analysisVersion: "test",
            createdAt: start,
            updatedAt: start,
            source: .manual
        )
    }

    @MainActor private func makeSegment(start: Date, intensity: SleepSnoreIntensity) -> SnoreSegmentSummary {
        SnoreSegmentSummary(
            segmentStart: start,
            segmentEnd: start.addingTimeInterval(2),
            durationSeconds: 2,
            intensity: intensity,
            peakDbfsBucket: intensity == .high ? 11 : 5,
            confidence: 0.84,
            disturbanceWeight: 0.6
        )
    }
}
