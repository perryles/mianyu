import Foundation
import XCTest
@testable import BioBalance

nonisolated final class DashboardCardStressResolutionTests: XCTestCase {
    @MainActor private let now = Date(timeIntervalSince1970: 1_800_050_000)

    @MainActor func testUsesTodayReconstructedPressureWhenDailyAndCurrentAreUnavailable() throws {
        let viewModel = makeViewModel()
        viewModel.currentStressEvaluation = .unavailable(.baselineCalibrating)
        viewModel.dailyStressEvaluation = .unavailable(.noDailySamples)
        viewModel.currentStressAssessment = StressPresentation.assessment(from: viewModel.currentStressEvaluation)
        viewModel.dailyStressAssessment = StressPresentation.assessment(from: viewModel.dailyStressEvaluation)
        viewModel.todaySevenMinuteStressPoints = [
            TimeSeriesPoint(timestamp: Int64(now.addingTimeInterval(-600).timeIntervalSince1970), value: 58)
        ]

        XCTAssertEqual(viewModel.cardStressAssessment.score, 58)
        XCTAssertEqual(viewModel.cardStressSource, DashboardCardStressSource.todayReconstructed.rawValue)
    }

    @MainActor func testDoesNotUseReconstructedPressureFromAnotherDay() {
        let viewModel = makeViewModel()
        viewModel.currentStressEvaluation = .unavailable(.noPhysiologicalSignal)
        viewModel.dailyStressEvaluation = .unavailable(.noDailySamples)
        viewModel.currentStressAssessment = StressPresentation.assessment(from: viewModel.currentStressEvaluation)
        viewModel.dailyStressAssessment = StressPresentation.assessment(from: viewModel.dailyStressEvaluation)
        viewModel.todaySevenMinuteStressPoints = [
            TimeSeriesPoint(timestamp: Int64(now.addingTimeInterval(-86_400).timeIntervalSince1970), value: 58)
        ]

        XCTAssertNil(viewModel.cardStressAssessment.score)
        XCTAssertEqual(viewModel.cardStressSource, DashboardCardStressSource.unavailable.rawValue)
    }

    @MainActor func testUsesPositiveTodaySnapshotEvenWhenUpstreamReasonIsUnavailable() {
        let viewModel = makeViewModel()
        viewModel.currentStressEvaluation = .unavailable(.baselineCalibrating)
        viewModel.dailyStressEvaluation = .unavailable(.noDailySamples)
        viewModel.currentStressAssessment = StressPresentation.assessment(from: viewModel.currentStressEvaluation)
        viewModel.dailyStressAssessment = StressPresentation.assessment(from: viewModel.dailyStressEvaluation)
        viewModel.realtimeHealth = RealtimeHealth(
            bpm: 72,
            hrv_sdnn: 42,
            stress_value: 63,
            stress_unavailable_reason: StressUnavailableReason.baselineCalibrating.rawValue,
            timestamp: Int64(now.timeIntervalSince1970)
        )

        XCTAssertEqual(viewModel.cardStressAssessment.score, 63)
        XCTAssertEqual(viewModel.cardStressSource, DashboardCardStressSource.todaySnapshot.rawValue)
    }

    @MainActor private func makeViewModel() -> DashboardViewModel {
        let defaults = UserDefaults(suiteName: "DashboardCardStressResolutionTests.\(UUID().uuidString)")!
        return DashboardViewModel(stressStore: StressStore(defaults: defaults), now: { self.now })
    }
}
