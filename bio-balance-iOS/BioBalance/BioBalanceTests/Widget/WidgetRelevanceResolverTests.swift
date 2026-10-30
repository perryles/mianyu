import XCTest
@testable import BioBalance

nonisolated final class WidgetRelevanceResolverTests: XCTestCase {
    @MainActor private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @MainActor func testMorningSleepAndHydrationCandidatesUseTimeWindows() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 10))!
        let snapshot = makeSnapshot(updatedAt: now, sleepScore: 82, waterCompletion: 0.4)
        let values = WidgetRelevanceResolver.candidates(from: snapshot, now: now, calendar: calendar)

        XCTAssertEqual(Set(values.map(\.kind)), Set([.morningRecovery, .hydration]))
        XCTAssertTrue(values.allSatisfy { $0.endDate > $0.startDate })
        XCTAssertEqual(
            Set(values.map(\.deepLink.absoluteString)),
            Set(["biobalance://widget/sleep", "biobalance://widget/overall"])
        )
    }

    @MainActor func testSedentaryRecoveryOutranksStressAndDoesNotDuplicateRecoveryCard() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 14))!
        let snapshot = makeSnapshot(updatedAt: now, stress: 78, sedentaryMinutes: 75, sedentaryActive: true)
        let values = WidgetRelevanceResolver.candidates(from: snapshot, now: now, calendar: calendar)

        XCTAssertEqual(values.first?.id, "sedentary-recovery")
        XCTAssertEqual(values.filter { $0.kind == .recoveryAction }.count, 1)
    }

    @MainActor func testActivityNearGoalAndEveningSleepPreparation() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 21))!
        let snapshot = makeSnapshot(updatedAt: now, steps: 8_500, stepsGoal: 10_000, sleepPrompt: "降低灯光并准备休息")
        let values = WidgetRelevanceResolver.candidates(from: snapshot, now: now, calendar: calendar)

        XCTAssertTrue(values.contains { $0.kind == .activityProgress })
        XCTAssertTrue(values.contains { $0.kind == .sleepPreparation })
        XCTAssertEqual(
            values.first(where: { $0.kind == .activityProgress })?.deepLink.absoluteString,
            "biobalance://widget/activity"
        )
        XCTAssertEqual(
            values.first(where: { $0.kind == .sleepPreparation })?.deepLink.absoluteString,
            "biobalance://widget/sleep"
        )
    }

    @MainActor func testStressRecoveryUsesRoutableStressDeepLink() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 14))!
        let values = WidgetRelevanceResolver.candidates(
            from: makeSnapshot(updatedAt: now, stress: 72),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(values.first?.kind, .recoveryAction)
        XCTAssertEqual(values.first?.deepLink.absoluteString, "biobalance://widget/stress")
    }

    @MainActor func testStaleHealthDataDoesNotCreateActionableCandidates() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 14))!
        let staleUpdate = calendar.date(byAdding: .hour, value: -2, to: now)!
        let values = WidgetRelevanceResolver.candidates(
            from: makeSnapshot(
                updatedAt: staleUpdate,
                staleAfter: 60,
                stress: 80,
                sedentaryMinutes: 90,
                sedentaryActive: true,
                steps: 9_000,
                stepsGoal: 10_000,
                waterCompletion: 0.2
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(values.isEmpty)
    }

    @MainActor func testInvalidHydrationRateDoesNotCreateCandidate() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 14))!
        let values = WidgetRelevanceResolver.candidates(
            from: makeSnapshot(updatedAt: now, waterCompletion: -Double.infinity),
            now: now,
            calendar: calendar
        )

        XCTAssertFalse(values.contains { $0.kind == .hydration })
    }

    @MainActor private func makeSnapshot(
        updatedAt: Date,
        staleAfter: TimeInterval = 3_600,
        stress: Double? = nil,
        sedentaryMinutes: Int? = nil,
        sedentaryActive: Bool? = nil,
        steps: Int? = nil,
        stepsGoal: Int? = nil,
        sleepScore: Int? = nil,
        sleepPrompt: String? = nil,
        waterCompletion: Double? = nil
    ) -> AppGroupHealthSnapshot {
        let freshness = AppGroupHealthSnapshot.MetricFreshness(updatedAt: updatedAt, staleAfter: staleAfter)
        return AppGroupHealthSnapshot(
            schemaVersion: AppGroupHealthSnapshot.currentSchemaVersion,
            generatedAt: Date(),
            vitals: .init(
                heartRate: nil, hrv: nil, stress: stress, stressState: nil,
                stressExplanationCode: nil, stressConfidence: nil, stressTrend: nil,
                stressHistory: [], freshness: freshness
            ),
            hydration: .init(
                waterIntakeMl: nil, waterTargetMl: 2_000,
                waterCompletionRate: waterCompletion, caffeineRemainedMg: nil, freshness: freshness
            ),
            activity: .init(
                steps: steps, stepsGoal: stepsGoal, activeEnergy: nil, activeEnergyGoal: nil,
                exerciseMinutes: nil, exerciseMinutesGoal: nil, standHours: nil, standHoursGoal: nil,
                walkingSpeedMps: nil, walkingPaceSecondsPerKm: nil,
                sedentaryElapsedMinutes: sedentaryMinutes, sedentaryIsCounting: sedentaryActive,
                freshness: freshness
            ),
            sleep: .init(
                durationMinutes: nil, score: sleepScore, snoreIntensity: nil, snoreDurationMinutes: nil,
                lateNightRecoveryPrompt: sleepPrompt, lateNightRecoverySeverity: nil,
                environmentCompletionRate: nil, environmentPrompt: nil, freshness: freshness
            ),
            summary: .init(
                healthSummary: nil, bodyAgeValueYears: nil, bodyAgeStatusText: nil,
                vo2MaxValue: nil, vo2MaxConfidence: nil, vo2MaxTrend: nil, vo2MaxFitnessLevel: nil,
                vo2MaxSource: nil, vo2MaxDriverSummary: nil, freshness: freshness
            ),
            recoveryPlan: nil
        )
    }
}
