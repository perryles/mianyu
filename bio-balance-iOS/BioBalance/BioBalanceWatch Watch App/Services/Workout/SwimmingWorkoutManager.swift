import Foundation
import HealthKit
import Observation

private enum SwimmingWorkoutManagerError: LocalizedError {
    case healthDataUnavailable
    case authorizationRequired
    case startFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            String(localized: "游泳训练需要 HealthKit")
        case .authorizationRequired:
            String(localized: "请先授权游泳训练数据")
        case .startFailed:
            String(localized: "无法启动游泳训练")
        case .saveFailed:
            String(localized: "无法保存游泳训练")
        }
    }
}

/// Owns one offline-capable swimming workout on Apple Watch.
@Observable
@MainActor
final class SwimmingWorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private(set) var phase: SwimmingWorkoutPhase = .idle
    private(set) var metrics: SwimmingLiveMetrics = .empty
    /// The location selected for the active or most recently completed session.
    private(set) var sessionLocation: SwimmingWorkoutLocation?
    private(set) var errorMessage: String?

    /// True means HealthKit says an authorization request can still be presented.
    /// It does not mean that read access was granted or that live samples exist.
    private(set) var authorizationRequiresRequest = true
    /// True while launch-time recovery is checking for an app-owned HealthKit session.
    private(set) var isRecoveringActiveSession = true

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var activeWorkoutRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var liveWorkoutBuilder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var startOperationID: UUID?
    @ObservationIgnored private var requestedEndDate: Date?
    @ObservationIgnored private var isFinalizing = false

    override init() {
        super.init()
        activeWorkoutRecoveryTask = Task { @MainActor [weak self] in
            await self?.recoverActiveWorkoutSession()
            await self?.refreshAuthorizationRequestStatus()
            self?.activeWorkoutRecoveryTask = nil
            self?.isRecoveringActiveSession = false
        }
    }

    /// Reconnects a swimming session after watchOS relaunches the app in the background.
    /// HealthKit keeps the system session alive; without recovery, the UI would return to idle
    /// while sensors were still collecting for the orphaned workout.
    private func recoverActiveWorkoutSession() async {
        guard HKHealthStore.isHealthDataAvailable(), phase == .idle else { return }

        let recovered = await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, _ in
                continuation.resume(returning: session)
            }
        }
        guard phase == .idle, let recovered else { return }
        guard recovered.workoutConfiguration.activityType == .swimming else { return }

        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: recovered.workoutConfiguration
        )
        recovered.delegate = self
        builder.delegate = self
        workoutSession = recovered
        liveWorkoutBuilder = builder
        sessionLocation = Self.swimmingLocation(from: recovered.workoutConfiguration)

        switch recovered.state {
        case .running:
            _ = transition(to: .preparing)
            _ = transition(to: .running)
            refreshMetrics(at: Date())
        case .paused:
            _ = transition(to: .preparing)
            _ = transition(to: .running)
            _ = transition(to: .paused)
            refreshMetrics(at: Date())
        case .stopped, .ended:
            _ = transition(to: .preparing)
            _ = transition(to: .ending)
            let endDate = builder.endDate ?? Date()
            Task { @MainActor [weak self] in
                await self?.finalizeWorkout(using: builder, at: endDate)
            }
        case .prepared, .notStarted:
            // A start that never reached HealthKit can be safely discarded. Leave the manager
            // idle so the person can configure and start the swim again.
            recovered.delegate = nil
            builder.delegate = nil
            builder.discardWorkout()
            recovered.end()
            workoutSession = nil
            liveWorkoutBuilder = nil
            sessionLocation = nil
        @unknown default:
            break
        }
    }

    private static func swimmingLocation(
        from configuration: HKWorkoutConfiguration
    ) -> SwimmingWorkoutLocation? {
        switch configuration.swimmingLocationType {
        case .pool: .pool
        case .openWater: .openWater
        case .unknown: nil
        @unknown default: nil
        }
    }

    /// Ask HealthKit for workout write access and the quantity types used by the live UI.
    /// HealthKit intentionally does not reveal whether a read request was granted; optional
    /// metrics remain nil until the live builder actually supplies corresponding samples.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = SwimmingWorkoutManagerError.healthDataUnavailable.localizedDescription
            authorizationRequiresRequest = false
            return
        }

        let statusResult = await authorizationRequestStatus()
        if let error = statusResult.errorMessage {
            errorMessage = error
            authorizationRequiresRequest = true
            return
        }

        guard statusResult.status != .unnecessary else {
            authorizationRequiresRequest = false
            errorMessage = healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
                ? nil
                : SwimmingWorkoutManagerError.authorizationRequired.localizedDescription
            return
        }

        let requestResult = await performAuthorizationRequest()
        if let error = requestResult.errorMessage {
            authorizationRequiresRequest = true
            errorMessage = error
            return
        }

        // The completion's success value reports that the request completed, not which
        // individual read permissions the person allowed.
        authorizationRequiresRequest = !requestResult.succeeded
        let workoutWriteAccess = healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        errorMessage = requestResult.succeeded && workoutWriteAccess
            ? nil
            : SwimmingWorkoutManagerError.authorizationRequired.localizedDescription
    }

    /// Starts a pool workout. If needed, this presents the HealthKit request first.
    func start(poolLength: SwimmingPoolLength) async {
        await start(configuration: .pool(poolLength))
    }

    /// Starts a pool or open-water workout. If needed, this presents the HealthKit request first.
    func start(configuration swimmingConfiguration: SwimmingSessionConfiguration) async {
        guard phase == .idle else { return }
        // A recovered session can still be collecting in the background. Wait for that check
        // before allowing a second HealthKit session to be created.
        if let activeWorkoutRecoveryTask {
            await activeWorkoutRecoveryTask.value
        }
        guard phase == .idle, transition(to: .preparing) else { return }
        errorMessage = nil
        metrics = .empty
        sessionLocation = swimmingConfiguration.location
        isFinalizing = false
        requestedEndDate = nil

        let operationID = UUID()
        startOperationID = operationID

        guard HKHealthStore.isHealthDataAvailable() else {
            fail(with: SwimmingWorkoutManagerError.healthDataUnavailable.localizedDescription)
            return
        }

        await refreshAuthorizationRequestStatus()
        guard startOperationID == operationID else { return }
        if authorizationRequiresRequest {
            await requestAuthorization()
        }
        guard startOperationID == operationID else { return }

        let workoutType = HKObjectType.workoutType()
        guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
            fail(with: SwimmingWorkoutManagerError.authorizationRequired.localizedDescription)
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .swimming
        switch swimmingConfiguration.location {
        case .pool:
            configuration.locationType = .indoor
            configuration.swimmingLocationType = .pool
            configuration.lapLength = swimmingConfiguration.poolLength.map {
                HKQuantity(unit: .meter(), doubleValue: $0.metersValue)
            }
        case .openWater:
            configuration.locationType = .outdoor
            configuration.swimmingLocationType = .openWater
        }

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            let startDate = Date()

            session.delegate = self
            builder.delegate = self
            builder.dataSource = dataSource
            workoutSession = session
            liveWorkoutBuilder = builder

            session.startActivity(with: startDate)
            let result = await beginCollection(builder, at: startDate)
            guard startOperationID == operationID else { return }

            guard result.succeeded else {
                builder.delegate = nil
                builder.discardWorkout()
                session.delegate = nil
                session.end()
                workoutSession = nil
                liveWorkoutBuilder = nil
                fail(with: result.errorMessage ?? SwimmingWorkoutManagerError.startFailed.localizedDescription)
                return
            }

            startOperationID = nil
            if phase == .preparing {
                _ = transition(to: .running)
            }
            refreshMetrics(at: Date())
        } catch {
            let session = workoutSession
            let builder = liveWorkoutBuilder
            startOperationID = nil
            session?.delegate = nil
            builder?.delegate = nil
            if let session, session.state != .ended {
                session.end()
            }
            builder?.discardWorkout()
            workoutSession = nil
            liveWorkoutBuilder = nil
            fail(with: error.localizedDescription)
        }
    }

    func pause() {
        guard phase == .running, let workoutSession else { return }
        workoutSession.pause()
    }

    func resume() {
        guard phase == .paused, let workoutSession else { return }
        workoutSession.resume()
    }

    /// Ends the current workout and waits for HealthKit to finish and save it.
    /// Repeated calls while ending are ignored.
    func end() {
        switch phase {
        case .idle, .finished, .failed, .ending:
            return
        case .preparing:
            cancelStartingWorkout()
            return
        case .running, .paused:
            break
        }

        guard transition(to: .ending) else { return }
        startOperationID = nil

        guard let session = workoutSession, let builder = liveWorkoutBuilder else {
            fail(with: SwimmingWorkoutManagerError.saveFailed.localizedDescription)
            return
        }

        let endDate = Date()
        requestedEndDate = endDate

        // Stop sensor collection first. HealthKit transitions asynchronously to
        // .stopped; only then may the builder be finalized and the workout session ended.
        if session.state == .stopped {
            Task { @MainActor [weak self] in
                await self?.finalizeWorkout(using: builder, at: endDate)
            }
        } else if session.state == .ended {
            Task { @MainActor [weak self] in
                await self?.finalizeWorkout(using: builder, at: endDate)
            }
        } else {
            session.stopActivity(with: endDate)
        }
    }

    /// Cancels a start that has not reached the running state. HealthKit may already have
    /// created the session and may still be invoking `beginCollection`; invalidate the operation
    /// and discard that builder so a late callback cannot finalize an unsampled workout.
    private func cancelStartingWorkout() {
        guard phase == .preparing else { return }

        startOperationID = nil
        let session = workoutSession
        let builder = liveWorkoutBuilder
        session?.delegate = nil
        builder?.delegate = nil
        if let session, session.state != .ended {
            session.end()
        }
        builder?.discardWorkout()

        workoutSession = nil
        liveWorkoutBuilder = nil
        requestedEndDate = nil
        isFinalizing = false
        metrics = .empty
        sessionLocation = nil
        errorMessage = nil
        _ = transition(to: .idle)
    }

    /// Retries end/save after a failure while retaining the samples already collected.
    func retrySave() {
        guard phase == .failed, let builder = liveWorkoutBuilder else { return }
        Task { @MainActor [weak self] in
            await self?.finalizeWorkout(using: builder, at: self?.requestedEndDate ?? Date())
        }
    }

    var canRetrySave: Bool {
        phase == .failed && liveWorkoutBuilder != nil
    }

    /// Clears a terminal workout so a new one can be started.
    func reset() {
        guard phase == .idle || phase == .finished || phase == .failed else { return }

        let session = workoutSession
        let builder = liveWorkoutBuilder
        session?.delegate = nil
        builder?.delegate = nil
        if let session, session.state != .ended {
            session.end()
        }
        // A save failure deliberately retains the builder for a retry. If the person chooses
        // to reset instead, discard that unsaved workout before allowing a new session.
        builder?.discardWorkout()

        workoutSession = nil
        liveWorkoutBuilder = nil
        startOperationID = nil
        requestedEndDate = nil
        isFinalizing = false
        metrics = .empty
        sessionLocation = nil
        errorMessage = nil

        if phase != .idle {
            _ = transition(to: .idle)
        }
    }

    // MARK: HealthKit delegates

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let sessionID = ObjectIdentifier(workoutSession)
        let state = toState
        Task { @MainActor [weak self] in
            self?.handleSessionState(state, sessionID: sessionID, at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let sessionID = ObjectIdentifier(workoutSession)
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, self.workoutSession.map(ObjectIdentifier.init) == sessionID else { return }
            self.fail(with: message)
        }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let builderID = ObjectIdentifier(workoutBuilder)
        Task { @MainActor [weak self] in
            guard let self, self.liveWorkoutBuilder.map(ObjectIdentifier.init) == builderID else { return }
            self.refreshMetrics(at: Date())
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        let builderID = ObjectIdentifier(workoutBuilder)
        Task { @MainActor [weak self] in
            guard let self, self.liveWorkoutBuilder.map(ObjectIdentifier.init) == builderID else { return }
            self.refreshMetrics(at: Date())
        }
    }

    // MARK: Authorization

    private func authorizationReadTypes() -> Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceSwimming,
            .swimmingStrokeCount
        ]
        return Set(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) as HKObjectType? })
    }

    private func authorizationRequestStatus() async -> (status: HKAuthorizationRequestStatus, errorMessage: String?) {
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        let readTypes = authorizationReadTypes()

        return await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
                continuation.resume(returning: (status, error?.localizedDescription))
            }
        }
    }

    private func performAuthorizationRequest() async -> (succeeded: Bool, errorMessage: String?) {
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        let readTypes = authorizationReadTypes()

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { succeeded, error in
                continuation.resume(returning: (succeeded, error?.localizedDescription))
            }
        }
    }

    private func refreshAuthorizationRequestStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationRequiresRequest = false
            return
        }

        let result = await authorizationRequestStatus()
        if result.status == .unnecessary {
            authorizationRequiresRequest = false
        } else {
            authorizationRequiresRequest = true
        }
        if let error = result.errorMessage {
            errorMessage = error
        }
    }

    // MARK: Workout lifecycle

    private func handleSessionState(_ state: HKWorkoutSessionState, sessionID: ObjectIdentifier, at date: Date) {
        guard workoutSession.map(ObjectIdentifier.init) == sessionID else { return }

        switch state {
        case .running:
            if phase == .preparing || phase == .paused {
                _ = transition(to: .running)
            }
            refreshMetrics(at: date)
        case .paused:
            if phase == .running {
                _ = transition(to: .paused)
            }
            refreshMetrics(at: date)
        case .stopped:
            if phase != .ending, phase != .finished, phase != .failed {
                _ = transition(to: .ending)
            }
            guard let liveWorkoutBuilder else {
                fail(with: SwimmingWorkoutManagerError.saveFailed.localizedDescription)
                return
            }
            let endDate = requestedEndDate ?? date
            Task { @MainActor [weak self] in
                await self?.finalizeWorkout(using: liveWorkoutBuilder, at: endDate)
            }
        case .ended:
            guard phase != .finished, phase != .failed else { return }
            if phase != .ending, phase != .finished, phase != .failed {
                _ = transition(to: .ending)
            }
            guard let liveWorkoutBuilder else {
                fail(with: SwimmingWorkoutManagerError.saveFailed.localizedDescription)
                return
            }
            Task { @MainActor [weak self] in
                await self?.finalizeWorkout(using: liveWorkoutBuilder, at: date)
            }
        default:
            break
        }
    }

    private func beginCollection(
        _ builder: HKLiveWorkoutBuilder,
        at date: Date
    ) async -> (succeeded: Bool, errorMessage: String?) {
        await withCheckedContinuation { continuation in
            builder.beginCollection(withStart: date) { succeeded, error in
                continuation.resume(returning: (succeeded, error?.localizedDescription))
            }
        }
    }

    private func finalizeWorkout(using builder: HKLiveWorkoutBuilder, at endDate: Date) async {
        guard !isFinalizing, liveWorkoutBuilder === builder else { return }
        isFinalizing = true

        if phase != .ending, phase != .failed {
            _ = transition(to: .ending)
        }

        // A retry after `finishWorkout` failed must not end collection again; HealthKit has
        // already closed the collection interval in that case.
        let endResult: (succeeded: Bool, errorMessage: String?)
        if builder.endDate == nil {
            endResult = await endCollection(builder, at: endDate)
            guard endResult.succeeded else {
                fail(
                    with: endResult.errorMessage ?? SwimmingWorkoutManagerError.saveFailed.localizedDescription,
                    preservesCollectedWorkout: true
                )
                return
            }
        } else {
            endResult = (true, nil)
        }

        refreshMetrics(at: endDate)
        let saveResult = await finishWorkout(builder)
        guard saveResult.workout != nil else {
            fail(
                with: saveResult.errorMessage ?? SwimmingWorkoutManagerError.saveFailed.localizedDescription,
                preservesCollectedWorkout: true
            )
            return
        }

        // Apple recommends ending the session only after the builder has saved.
        workoutSession?.end()
        if phase == .ending {
            errorMessage = nil
            _ = transition(to: .finished)
        }
        workoutSession = nil
        liveWorkoutBuilder = nil
        startOperationID = nil
        requestedEndDate = nil
    }

    private func endCollection(
        _ builder: HKLiveWorkoutBuilder,
        at date: Date
    ) async -> (succeeded: Bool, errorMessage: String?) {
        await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: date) { succeeded, error in
                continuation.resume(returning: (succeeded, error?.localizedDescription))
            }
        }
    }

    private func finishWorkout(_ builder: HKLiveWorkoutBuilder) async -> (workout: HKWorkout?, errorMessage: String?) {
        await withCheckedContinuation { continuation in
            builder.finishWorkout { workout, error in
                continuation.resume(returning: (workout, error?.localizedDescription))
            }
        }
    }

    // MARK: Live metrics

    /// Refreshes elapsed time and other builder-backed values while the workout page is visible.
    func refreshMetricsForDisplay() {
        refreshMetrics(at: Date())
    }

    private func refreshMetrics(at date: Date) {
        guard let builder = liveWorkoutBuilder else { return }

        let duration = builder.elapsedTime(at: date)
        let distance = quantityValue(
            for: .distanceSwimming,
            in: builder,
            unit: .meter(),
            aggregation: .sum
        )
        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let heartRateStatistics = quantityType(.heartRate).flatMap { builder.statistics(for: $0) }
        let currentHeartRate = heartRateStatistics?
            .mostRecentQuantity()?
            .doubleValue(for: heartRateUnit)
        let averageHeartRate = heartRateStatistics?
            .averageQuantity()?
            .doubleValue(for: heartRateUnit)
        let activeEnergy = quantityValue(
            for: .activeEnergyBurned,
            in: builder,
            unit: .kilocalorie(),
            aggregation: .sum
        )
        let strokeCount = quantityValue(
            for: .swimmingStrokeCount,
            in: builder,
            unit: .count(),
            aggregation: .sum
        ).flatMap(nonnegativeInteger)

        let lapEventCount = builder.workoutEvents.filter { $0.type == .lap }.count
        let validDuration = duration.isFinite && duration >= 0 ? duration : nil
        let validDistance = distance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let pace = SwimmingMetricsCalculator.paceSecondsPer100Meters(
            duration: validDuration,
            distanceMeters: validDistance
        )

        metrics = SwimmingLiveMetrics(
            duration: validDuration,
            distanceMeters: validDistance,
            currentHeartRateBPM: currentHeartRate.flatMap(positiveFinite),
            averageHeartRateBPM: averageHeartRate.flatMap(positiveFinite),
            activeEnergyKilocalories: activeEnergy.flatMap(nonnegativeFinite),
            strokeCount: strokeCount,
            lapCount: lapEventCount > 0 ? lapEventCount : nil,
            averagePaceSecondsPer100Meters: pace
        )
    }

    private enum QuantityAggregation {
        case sum
    }

    private func quantityValue(
        for identifier: HKQuantityTypeIdentifier,
        in builder: HKLiveWorkoutBuilder,
        unit: HKUnit,
        aggregation: QuantityAggregation
    ) -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier),
              let statistics = builder.statistics(for: type) else {
            return nil
        }

        switch aggregation {
        case .sum:
            return statistics.sumQuantity()?.doubleValue(for: unit)
        }
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: identifier)
    }

    private func positiveFinite(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    private func nonnegativeFinite(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }

    private func nonnegativeInteger(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
        return Int(value.rounded(.down))
    }

    // MARK: State helpers

    @discardableResult
    private func transition(to nextPhase: SwimmingWorkoutPhase) -> Bool {
        guard SwimmingWorkoutLifecycle.canTransition(from: phase, to: nextPhase) else { return false }
        phase = nextPhase
        return true
    }

    private func fail(
        with message: String,
        preservesCollectedWorkout: Bool = false
    ) {
        errorMessage = message
        startOperationID = nil
        isFinalizing = false

        if preservesCollectedWorkout {
            // Keep the session and builder so “重试保存” can call HealthKit again instead of
            // discarding samples that may already have been collected.
            if phase != .failed {
                _ = transition(to: .failed)
            }
            return
        }

        requestedEndDate = nil
        let session = workoutSession
        let builder = liveWorkoutBuilder
        session?.delegate = nil
        builder?.delegate = nil
        workoutSession = nil
        liveWorkoutBuilder = nil
        if let session, session.state != .ended {
            session.end()
        }
        builder?.discardWorkout()
        if phase != .failed {
            _ = transition(to: .failed)
        }
    }
}
