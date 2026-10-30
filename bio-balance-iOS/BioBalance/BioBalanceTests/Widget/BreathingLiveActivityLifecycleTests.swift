import XCTest
@testable import BioBalance

nonisolated final class BreathingLiveActivityLifecycleTests: XCTestCase {
    @MainActor func testStartingSessionStartsLiveActivityWithSelectedDuration() {
        let coordinator = BreathingLiveActivityCoordinatorSpy()
        let viewModel = BreathingMindfulnessViewModel(liveActivityCoordinator: coordinator)
        viewModel.selectedSessionLength = .five

        viewModel.startSession()

        XCTAssertEqual(coordinator.startedDurations, [300])
        viewModel.cancelSession()
    }

    @MainActor func testCancellingRunningSessionEndsLiveActivity() {
        let coordinator = BreathingLiveActivityCoordinatorSpy()
        let viewModel = BreathingMindfulnessViewModel(liveActivityCoordinator: coordinator)
        viewModel.startSession()

        viewModel.cancelSession()

        XCTAssertEqual(coordinator.endCallCount, 1)
    }
}

@MainActor
private final class BreathingLiveActivityCoordinatorSpy: BreathingLiveActivityCoordinating {
    private(set) var startedDurations: [Int] = []
    private(set) var endCallCount = 0

    func start(durationSeconds: Int) {
        startedDurations.append(durationSeconds)
    }

    func end() {
        endCallCount += 1
    }
}
