import Foundation
import XCTest
@testable import BioBalance

nonisolated final class VO2MaxRulesTests: XCTestCase {
    @MainActor func testMinimumEvidenceRejectsUnanchoredRecoveryOnlyEstimate() {
        XCTAssertFalse(VO2MaxRules.hasMinimumEvidence(
            actualVO2: nil,
            hasRestingHeartRate: false,
            hasHrv: false,
            hasWalking: false,
            hasRunning: false,
            hasRecovery: true
        ))
        XCTAssertTrue(VO2MaxRules.hasMinimumEvidence(
            actualVO2: nil,
            hasRestingHeartRate: true,
            hasHrv: true,
            hasWalking: false,
            hasRunning: false,
            hasRecovery: false
        ))
        XCTAssertTrue(VO2MaxRules.hasMinimumEvidence(
            actualVO2: nil,
            hasRestingHeartRate: false,
            hasHrv: false,
            hasWalking: false,
            hasRunning: true,
            hasRecovery: false
        ))
    }

    @MainActor func testWeightedScoreRenormalizesAvailableComponents() throws {
        let score = try XCTUnwrap(VO2MaxRules.weightedScore(
            rhr: 40,
            hrv: nil,
            walking: nil,
            running: 80,
            recovery: nil
        ))

        XCTAssertEqual(score, 64, accuracy: 0.001)
        XCTAssertNil(VO2MaxRules.weightedScore(
            rhr: nil,
            hrv: nil,
            walking: nil,
            running: nil,
            recovery: nil
        ))
    }

    @MainActor func testActualHealthKitValueIsNeverNumericallyBlended() throws {
        let resolved = try XCTUnwrap(VO2MaxRules.resolveValue(
            actualVO2: 43.27,
            estimatedValue: 58,
            hasInterpretiveContext: true
        ))

        XCTAssertEqual(resolved.value, 43.3)
        XCTAssertEqual(resolved.source, .engineBlended)
    }

    @MainActor func testInvalidActualFallsBackToBoundedEstimate() throws {
        let resolved = try XCTUnwrap(VO2MaxRules.resolveValue(
            actualVO2: .infinity,
            estimatedValue: 90,
            hasInterpretiveContext: false
        ))

        XCTAssertEqual(resolved.value, 65)
        XCTAssertEqual(resolved.source, .engineEstimated)
    }

    @MainActor func testActualSampleHasHighConfidenceFloor() {
        let sparseActual = VO2MaxRules.confidenceBreakdown(
            actualVO2: 42,
            inputs: coverage(actual: true),
            runningSampleCount: 0,
            walkingSampleCount: 0
        )
        let estimated = VO2MaxRules.confidenceBreakdown(
            actualVO2: nil,
            inputs: coverage(actual: false, rhr: true, hrv: true),
            runningSampleCount: 0,
            walkingSampleCount: 0
        )

        XCTAssertGreaterThanOrEqual(sparseActual.finalScore, 90)
        XCTAssertLessThan(estimated.finalScore, 90)
    }

    @MainActor func testUnknownSexUsesNeutralThresholds() {
        XCTAssertEqual(VO2MaxRules.fitnessLevel(value: 42, age: 35, sex: "男"), .average)
        XCTAssertEqual(VO2MaxRules.fitnessLevel(value: 42, age: 35, sex: "女"), .excellent)
        XCTAssertEqual(VO2MaxRules.fitnessLevel(value: 42, age: 35, sex: nil), .good)
        XCTAssertEqual(VO2MaxRules.fitnessLevel(value: 42, age: 35, sex: "male"), .average)
    }

    @MainActor func testOnlyConsecutiveEstimatedValuesAreRateLimited() {
        XCTAssertEqual(
            VO2MaxRules.smoothedValue(
                current: 50,
                source: .engineEstimated,
                previous: 40,
                previousSource: .engineEstimated,
                daysSincePrevious: 1
            ),
            40.7
        )
        XCTAssertEqual(
            VO2MaxRules.smoothedValue(
                current: 50,
                source: .engineBlended,
                previous: 40,
                previousSource: .engineEstimated,
                daysSincePrevious: 1
            ),
            50
        )
        XCTAssertEqual(
            VO2MaxRules.smoothedValue(
                current: 50,
                source: .healthKitActual,
                previous: 40,
                previousSource: .engineEstimated,
                daysSincePrevious: 1
            ),
            50
        )
        XCTAssertEqual(
            VO2MaxRules.smoothedValue(
                current: 50,
                source: .engineEstimated,
                previous: 40,
                previousSource: .healthKitActual,
                daysSincePrevious: 1
            ),
            50
        )
        XCTAssertEqual(
            VO2MaxRules.smoothedValue(
                current: 50,
                source: .engineEstimated,
                previous: 40,
                previousSource: .engineEstimated,
                daysSincePrevious: 3
            ),
            50
        )
    }

    @MainActor func testVersionAndCalculationContextAdvanceWithSmoothingContract() {
        XCTAssertEqual(VO2MaxDailyAssessment.currentAlgorithmVersion, "3.1")
        XCTAssertEqual(VO2MaxAssessmentStore.cacheKey, "vo2MaxDailyAssessment.v3_1")
        XCTAssertEqual(VO2MaxEngine.minimumSmoothingContextDays, 31)
    }

    @MainActor func testAssessmentStoreMergesDatesAndReplacesSameDay() throws {
        let suiteName = "VO2MaxRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = VO2MaxAssessmentStore(defaults: defaults)
        let dayOne = Date(timeIntervalSince1970: 1_800_000_000)
        let dayTwo = dayOne.addingTimeInterval(86_400)

        store.save([makeAssessment(date: dayOne, value: 40)])
        store.save([makeAssessment(date: dayTwo, value: 42)])
        store.save([makeAssessment(date: dayOne, value: 41)])

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.date), [dayOne, dayTwo])
        XCTAssertEqual(loaded.map(\.value), [41, 42])
    }

    @MainActor func testAssessmentStoreKeepsLatestFourHundredDates() throws {
        let suiteName = "VO2MaxRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = VO2MaxAssessmentStore(defaults: defaults)
        let firstDay = Date(timeIntervalSince1970: 1_800_000_000)
        let assessments = (0..<405).map { offset in
            makeAssessment(
                date: firstDay.addingTimeInterval(Double(offset) * 86_400),
                value: 40 + Double(offset % 10) / 10
            )
        }

        store.save(assessments)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 400)
        XCTAssertEqual(loaded.first?.date, assessments[5].date)
        XCTAssertEqual(loaded.last?.date, assessments[404].date)
    }

    @MainActor func testDashboardBaselineUsesOnlyEarlierActualAndBlendedAssessments() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let currentDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
        let current = makeAssessment(date: currentDay, value: 50, source: .healthKitActual)
        let previousActual = makeAssessment(
            date: try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: currentDay)),
            value: 40,
            source: .healthKitActual
        )
        let previousBlended = makeAssessment(
            date: try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: currentDay)),
            value: 44,
            source: .engineBlended
        )
        let previousEstimated = makeAssessment(
            date: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: currentDay)),
            value: 60,
            source: .engineEstimated
        )
        let laterSameDay = makeAssessment(
            date: currentDay.addingTimeInterval(12 * 60 * 60),
            value: 58,
            source: .healthKitActual
        )

        let average = DashboardViewModel.recentMeasuredVO2Average(
            before: current,
            in: [previousEstimated, laterSameDay, current, previousBlended, previousActual],
            calendar: calendar
        )

        XCTAssertEqual(average, 42)
    }

    @MainActor func testDashboardDoesNotMarkBlendedAssessmentAsEstimated() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let viewModel = DashboardViewModel(now: { referenceDate })
        let blended = makeAssessment(date: referenceDate, value: 43, source: .engineBlended)

        viewModel.applyVO2Assessments([blended], on: referenceDate)

        XCTAssertEqual(viewModel.vo2MaxAssessment?.source, .engineBlended)
        XCTAssertFalse(viewModel.vo2MaxIsEstimated)

        let estimated = makeAssessment(date: referenceDate, value: 41, source: .engineEstimated)
        viewModel.applyVO2Assessments([estimated], on: referenceDate)
        XCTAssertTrue(viewModel.vo2MaxIsEstimated)
    }

    @MainActor func testTrendUsesTwoCalendarWeekWindows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let samples = try (0..<14).map { offset -> VO2MaxRules.TrendSample in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            return VO2MaxRules.TrendSample(
                date: date,
                value: offset < 7 ? 40 : 42,
                confidence: 80
            )
        }

        XCTAssertEqual(VO2MaxRules.trend(samples: samples, calendar: calendar), .improving)
        XCTAssertEqual(VO2MaxRules.trend(samples: Array(samples.suffix(5)), calendar: calendar), .stable)
    }

    @MainActor func testLatestAssessmentCarriesForwardWithinThirtyDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let measuredAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)))
        let assessment = makeAssessment(date: measuredAt, value: 42)

        let resolved = VO2MaxRules.latestAssessment(
            onOrBefore: referenceDate,
            in: [assessment],
            calendar: calendar
        )

        XCTAssertEqual(resolved, assessment)
        XCTAssertEqual(resolved?.date, measuredAt)
    }

    @MainActor func testLatestAssessmentDoesNotCarryForwardStaleOrFutureValues() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let stale = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))),
            value: 40
        )
        let future = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))),
            value: 44
        )

        XCTAssertNil(VO2MaxRules.latestAssessment(onOrBefore: referenceDate, in: [stale, future], calendar: calendar))
    }

    @MainActor func testDashboardRollingWeekUsesLatestValueWhenTodayHasNoSample() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let earlier = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))),
            value: 40
        )
        let latest = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 9))),
            value: 43
        )

        let resolved = VO2MaxRules.latestAssessmentInDashboardRollingWeek(
            onOrBefore: referenceDate,
            in: [latest, earlier],
            calendar: calendar
        )

        XCTAssertEqual(resolved, latest)
    }

    @MainActor func testDashboardRollingWeekIncludesTodayAndPreviousSixCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let firstIncluded = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4))),
            value: 39
        )
        let today = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 12))),
            value: 44
        )

        let resolved = VO2MaxRules.assessmentsInDashboardRollingWeek(
            onOrBefore: referenceDate,
            in: [today, firstIncluded],
            calendar: calendar
        )

        XCTAssertEqual(resolved, [firstIncluded, today])
    }

    @MainActor func testDashboardRollingWeekExcludesSevenDayOldAndFutureDaySamples() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let sevenDaysOld = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))),
            value: 40
        )
        let future = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))),
            value: 45
        )

        XCTAssertNil(VO2MaxRules.latestAssessmentInDashboardRollingWeek(
            onOrBefore: referenceDate,
            in: [sevenDaysOld, future],
            calendar: calendar
        ))
    }

    @MainActor func testDashboardCacheRestoreAndRefreshUseSameRollingWeekSelection() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let stale = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))),
            value: 39
        )
        let weekly = makeAssessment(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 8))),
            value: 42,
            source: .engineBlended
        )
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "VO2MaxRulesTests.\(UUID().uuidString)"))
        let store = VO2MaxAssessmentStore(defaults: defaults)
        store.save([stale, weekly])

        let viewModel = DashboardViewModel(vo2MaxStore: store, now: { referenceDate })
        XCTAssertEqual(viewModel.vo2MaxAssessment, weekly)

        viewModel.applyVO2Assessments([stale, weekly], on: referenceDate)
        XCTAssertEqual(viewModel.vo2MaxAssessment, weekly)
        XCTAssertEqual(viewModel.vo2MaxHistory.count, 2)
    }

    @MainActor func testDailyWalkingAggregateDoesNotNeedInventedDistanceOrDuration() throws {
        let score = VO2MaxEngine.shared.walkingFitnessIndex(input: WalkingFitnessInput(
            speedMps: 1.4,
            paceSecondsPerKm: 714,
            averageHeartRate: 92,
            restingHeartRate: 60,
            distanceKilometers: nil,
            durationMinutes: nil,
            baselineRatio: nil,
            age: 35,
            sex: nil
        ))

        XCTAssertNotNil(score)
    }

    @MainActor func testWalkingSpeedOnlyProducesConservativeEstimate() throws {
        let speedOnly = try XCTUnwrap(VO2MaxEngine.shared.walkingFitnessIndex(input: WalkingFitnessInput(
            speedMps: 1.4,
            paceSecondsPerKm: 714,
            averageHeartRate: nil,
            restingHeartRate: nil,
            distanceKilometers: nil,
            durationMinutes: nil,
            baselineRatio: nil,
            age: 35,
            sex: nil
        )))
        let withHeartRate = try XCTUnwrap(VO2MaxEngine.shared.walkingFitnessIndex(input: WalkingFitnessInput(
            speedMps: 1.4,
            paceSecondsPerKm: 714,
            averageHeartRate: 92,
            restingHeartRate: 60,
            distanceKilometers: nil,
            durationMinutes: nil,
            baselineRatio: nil,
            age: 35,
            sex: nil
        )))

        XCTAssertGreaterThan(speedOnly, 0)
        XCTAssertLessThan(speedOnly, withHeartRate)
    }

    @MainActor func testWalkingEfficiencyUsesPersonalBaseline() throws {
        let baselineRatio = 1.3 / 100
        let efficient = try XCTUnwrap(VO2MaxEngine.shared.walkingFitnessIndex(input: WalkingFitnessInput(
            speedMps: 1.5,
            paceSecondsPerKm: nil,
            averageHeartRate: 95,
            restingHeartRate: 60,
            distanceKilometers: 2,
            durationMinutes: 24,
            baselineRatio: baselineRatio,
            age: nil,
            sex: nil
        )))
        let costly = try XCTUnwrap(VO2MaxEngine.shared.walkingFitnessIndex(input: WalkingFitnessInput(
            speedMps: 1.2,
            paceSecondsPerKm: nil,
            averageHeartRate: 108,
            restingHeartRate: 60,
            distanceKilometers: 2,
            durationMinutes: 24,
            baselineRatio: baselineRatio,
            age: nil,
            sex: nil
        )))

        XCTAssertGreaterThan(efficient, costly)
    }

    @MainActor func testRunningFitnessRejectsImplausibleInput() {
        let score = VO2MaxEngine.shared.runningFitnessIndex(input: RunningFitnessInput(
            paceSecondsPerKm: 0,
            averageHeartRate: 150,
            distanceKilometers: 5,
            durationMinutes: 30,
            baselineEfficiency: nil
        ))

        XCTAssertNil(score)
    }

    @MainActor func testRunningFitnessAcceptsShortEasyRun() {
        let score = VO2MaxEngine.shared.runningFitnessIndex(input: RunningFitnessInput(
            paceSecondsPerKm: 600,
            averageHeartRate: 135,
            distanceKilometers: 0.5,
            durationMinutes: 5,
            baselineEfficiency: nil
        ))
        let tooShort = VO2MaxEngine.shared.runningFitnessIndex(input: RunningFitnessInput(
            paceSecondsPerKm: 600,
            averageHeartRate: 135,
            distanceKilometers: 0.5,
            durationMinutes: 4.9,
            baselineEfficiency: nil
        ))

        XCTAssertNotNil(score)
        XCTAssertNil(tooShort)
    }

    @MainActor func testRunningFitnessDoesNotEnforceFixedHeartRateOrPaceRanges() {
        let score = VO2MaxEngine.shared.runningFitnessIndex(input: RunningFitnessInput(
            paceSecondsPerKm: 60,
            averageHeartRate: 250,
            distanceKilometers: 1,
            durationMinutes: 5,
            baselineEfficiency: nil
        ))

        XCTAssertNotNil(score)
    }

    @MainActor func testRecoverySignalsAreDirectionallyConsistent() throws {
        let recovered = try XCTUnwrap(VO2MaxEngine.shared.recoveryFitnessIndex(input: RecoveryFitnessInput(
            sleepScore: 90,
            nightlyHrv: 60,
            recentNightlyHrvBaseline: 50,
            nightlyAverageHeartRate: 52,
            heartRateRecoveryOneMinute: 30
        )))
        let strained = try XCTUnwrap(VO2MaxEngine.shared.recoveryFitnessIndex(input: RecoveryFitnessInput(
            sleepScore: 50,
            nightlyHrv: 30,
            recentNightlyHrvBaseline: 50,
            nightlyAverageHeartRate: 70,
            heartRateRecoveryOneMinute: 8
        )))

        XCTAssertGreaterThan(recovered, strained)
    }

    @MainActor func testSessionUsesClosestValidActualInsideWorkoutWindow() throws {
        let workoutStart = Date(timeIntervalSince1970: 1_800_000_000)
        let workoutEnd = workoutStart.addingTimeInterval(30 * 60)
        let workout = VO2MaxWorkoutSample(
            id: UUID(),
            activityType: .running,
            startDate: workoutStart,
            endDate: workoutEnd,
            durationMinutes: 30,
            distanceKilometers: 5,
            averageHeartRate: 150,
            peakHeartRate: nil,
            endHeartRate: nil,
            paceSecondsPerKilometer: 360,
            heartRateRecoveryOneMinute: nil,
            heartRateRecoveryTwoMinute: nil
        )
        let samples = [
            point(value: 120, at: workoutEnd.addingTimeInterval(60)),
            point(value: 44.26, at: workoutEnd.addingTimeInterval(5 * 60)),
            point(value: 51, at: workoutEnd.addingTimeInterval(3 * 60 * 60))
        ]

        XCTAssertEqual(VO2MaxEngine.shared.actualVO2(near: workout, samples: samples), 44.3)
    }

    @MainActor func testSessionPreservesActualSampleOutsideWorkoutAssociationWindow() {
        let workoutStart = Date(timeIntervalSince1970: 1_800_000_000)
        let workoutEnd = workoutStart.addingTimeInterval(30 * 60)
        let workout = VO2MaxWorkoutSample(
            id: UUID(),
            activityType: .running,
            startDate: workoutStart,
            endDate: workoutEnd,
            durationMinutes: 30,
            distanceKilometers: 5,
            averageHeartRate: 150,
            peakHeartRate: nil,
            endHeartRate: nil,
            paceSecondsPerKilometer: 360,
            heartRateRecoveryOneMinute: nil,
            heartRateRecoveryTwoMinute: nil
        )
        let associated = point(value: 44.2, at: workoutEnd.addingTimeInterval(5 * 60))
        let independent = point(value: 47.8, at: workoutEnd.addingTimeInterval(3 * 60 * 60))
        let invalidIndependent = point(value: 120, at: workoutEnd.addingTimeInterval(4 * 60 * 60))

        let samples = VO2MaxEngine.shared.unassociatedActualSamples(
            samples: [invalidIndependent, associated, independent],
            workouts: [workout]
        )

        XCTAssertEqual(samples, [independent])
    }

    @MainActor private func coverage(
        actual: Bool,
        rhr: Bool = false,
        hrv: Bool = false,
        walking: Bool = false,
        running: Bool = false,
        recovery: Bool = false
    ) -> VO2MaxInputCoverage {
        VO2MaxInputCoverage(
            actualVO2: actual,
            rhr: rhr,
            hrv: hrv,
            walking: walking,
            running: running,
            recovery: recovery
        )
    }

    @MainActor private func point(value: Double, at date: Date) -> TimeSeriesPointDouble {
        TimeSeriesPointDouble(timestamp: Int64(date.timeIntervalSince1970), value: value)
    }

    @MainActor private func makeAssessment(
        date: Date,
        value: Double,
        source: VO2MaxSource = .healthKitActual
    ) -> VO2MaxDailyAssessment {
        let confidence = VO2MaxConfidenceBreakdown(
            sourceScore: 95,
            coverageScore: 60,
            qualityScore: 60,
            finalScore: 90
        )
        return VO2MaxDailyAssessment(
            date: date,
            value: value,
            source: source,
            confidence: confidence.finalScore,
            trend: .stable,
            fitnessLevel: .average,
            drivers: [],
            components: VO2MaxComponentBreakdown(
                rhrComponent: nil,
                hrvComponent: nil,
                walkingEfficiencyComponent: nil,
                runningEfficiencyComponent: nil,
                recoveryComponent: nil,
                finalWeightedScore: 0
            ),
            inputs: coverage(actual: true),
            confidenceBreakdown: confidence,
            summaryText: ""
        )
    }
}
