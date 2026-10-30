import XCTest
@testable import BioBalance

nonisolated final class BodyRecoveryPersonalizationTests: XCTestCase {
    @MainActor func testNoDataShowsSyncStateWithoutInventingActions() {
        let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput())

        XCTAssertFalse(presentation.hasHealthData)
        XCTAssertFalse(presentation.shouldReturnToToday)
        XCTAssertTrue(presentation.factors.isEmpty)
        XCTAssertTrue(presentation.actions.isEmpty)
    }

    @MainActor func testBodyBatteryBandsProduceExpectedToneAndThreeActions() {
        let cases: [(Int, BodyRecoveryPresentationTone)] = [
            (90, .positive),
            (65, .neutral),
            (40, .caution),
            (20, .critical)
        ]

        for (battery, expectedTone) in cases {
            let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput(
                currentBodyBattery: battery,
                overnightRecoveryScore: battery,
                stressScore: 45
            ))

            XCTAssertEqual(presentation.tone, expectedTone, "Unexpected tone for battery \(battery)")
            XCTAssertEqual(presentation.actions.count, 3)
            XCTAssertEqual(Set(presentation.actions.map(\.kind)).count, presentation.actions.count)
        }
    }

    @MainActor func testLowRecoveryAndHighStressArePrioritized() {
        let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput(
            currentBodyBattery: 48,
            overnightRecoveryScore: 45,
            stressScore: 78
        ))

        XCTAssertEqual(presentation.actions.first?.kind, .decompress)
        XCTAssertTrue(presentation.actions.contains(where: { $0.kind == .protectSleep }))
        XCTAssertTrue(presentation.summary.contains("压力"))
        XCTAssertTrue(presentation.summary.contains("恢复"))
    }

    @MainActor func testActivityLoadAddsFactorAndAvoidsAdditionalTraining() {
        let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput(
            currentBodyBattery: 43,
            overnightRecoveryScore: 62,
            stressScore: 50,
            physicalEffortSampleCount: 4,
            workoutEventCount: 1
        ))

        XCTAssertTrue(presentation.factors.contains(where: { $0.kind == .activityLoad }))
        XCTAssertTrue(presentation.actions.contains(where: { $0.kind == .reduceTraining }))
    }

    @MainActor func testHrvAndHeartRateUsePersonalBaselines() {
        let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput(
            currentBodyBattery: 58,
            overnightRecoveryScore: 64,
            stressScore: 42,
            nightlyHrv: 34,
            baselineHrv: 50,
            overnightHeartRate: 70,
            baselineOvernightHeartRate: 58
        ))

        let hrv = presentation.factors.first(where: { $0.kind == .hrv })
        let heartRate = presentation.factors.first(where: { $0.kind == .heartRate })
        XCTAssertEqual(hrv?.tone, .caution)
        XCTAssertEqual(heartRate?.tone, .caution)
        XCTAssertTrue(presentation.actions.contains(where: { $0.kind == .keepLoadLight }))
    }

    @MainActor func testPartialDataOnlyReturnsAvailableFactors() {
        let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput(
            stressScore: 32
        ))

        XCTAssertTrue(presentation.hasHealthData)
        XCTAssertEqual(presentation.factors.map(\.kind), [.daytimeStress])
        XCTAssertFalse(presentation.actions.isEmpty)
    }

    @MainActor func testHistoricalPeriodDoesNotReuseTodayPersonalization() {
        let presentation = BodyRecoveryPersonalizationEngine.make(input: makeInput(
            currentBodyBattery: 82,
            overnightRecoveryScore: 88,
            stressScore: 24,
            isCurrentDay: false
        ))

        XCTAssertTrue(presentation.shouldReturnToToday)
        XCTAssertTrue(presentation.factors.isEmpty)
        XCTAssertTrue(presentation.actions.isEmpty)
    }

    @MainActor private func makeInput(
        currentBodyBattery: Int? = nil,
        overnightRecoveryScore: Int? = nil,
        stressScore: Int? = nil,
        nightlyHrv: Double? = nil,
        baselineHrv: Double? = nil,
        overnightHeartRate: Double? = nil,
        baselineOvernightHeartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        baselineRestingHeartRate: Double? = nil,
        physicalEffortSampleCount: Int = 0,
        workoutEventCount: Int = 0,
        isCurrentDay: Bool = true
    ) -> BodyRecoveryPersonalizationInput {
        BodyRecoveryPersonalizationInput(
            currentBodyBattery: currentBodyBattery,
            overnightRecoveryScore: overnightRecoveryScore,
            stressScore: stressScore,
            nightlyHrv: nightlyHrv,
            baselineHrv: baselineHrv,
            overnightHeartRate: overnightHeartRate,
            baselineOvernightHeartRate: baselineOvernightHeartRate,
            restingHeartRate: restingHeartRate,
            baselineRestingHeartRate: baselineRestingHeartRate,
            physicalEffortSampleCount: physicalEffortSampleCount,
            workoutEventCount: workoutEventCount,
            isCurrentDay: isCurrentDay
        )
    }
}
