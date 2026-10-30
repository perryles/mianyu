/// Content View 定义 Apple Watch 端的界面或同步逻辑，负责在手表上展示核心健康信息并与 iPhone 侧保持数据联动。
import SwiftUI
import HealthKit

struct WatchLiveWorkoutZoneState: Sendable, Equatable {
    let index: Int
    let duration: TimeInterval
    let lastSampleDate: Date?
}

enum WatchHeartRateAuthorizationState: Equatable {
    case checking
    case needsAuthorization
    case requesting
    case ready
    case unavailable
}

/// 手表心率管理器 作为Apple Watch 应用里的服务或调度入口。
/// 负责Apple Watch 端展示与同步。
@Observable
final class WatchHeartRateManager: NSObject {
    var bpm: Int = 0
    var heartRateZone: WatchLiveWorkoutZoneState?
    var cyclingPowerZone: WatchLiveWorkoutZoneState?
    var authorizationState: WatchHeartRateAuthorizationState = .checking

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = heartRateTypes()
        guard !types.isEmpty else {
            authorizationState = .unavailable
            return
        }

        // 启动只检查状态，不调用 requestAuthorization，避免打开 Watch 首页时主动弹窗。
        healthStore.getRequestStatusForAuthorization(toShare: [], read: types) { [weak self] status, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .shouldRequest:
                    self.authorizationState = .needsAuthorization
                case .unnecessary:
                    self.authorizationState = .ready
                    self.startHeartRateObservation()
                case .unknown:
                    self.authorizationState = .unavailable
                @unknown default:
                    self.authorizationState = .unavailable
                }
            }
        }
    }

    /// 仅由用户点击 Watch 页面中的授权按钮调用。
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable(), authorizationState != .requesting else { return }
        let types = heartRateTypes()
        guard !types.isEmpty else {
            authorizationState = .unavailable
            return
        }

        authorizationState = .requesting
        healthStore.requestAuthorization(toShare: [], read: types) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationState = success ? .ready : .needsAuthorization
                if success {
                    self.startHeartRateObservation()
                }
            }
        }
    }

    func stop() {
        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
            self.heartRateQuery = nil
        }
        heartRateZone = nil
        cyclingPowerZone = nil
    }

    private func startHeartRateObservation() {
        guard heartRateQuery == nil,
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        refreshLatestHeartRate(type: type)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor [weak self] in
                self?.refreshLatestHeartRate(type: type)
            }
            completion()
        }
        heartRateQuery = query
        healthStore.execute(query)
    }

    private func heartRateTypes() -> Set<HKObjectType> {
        Set([HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap { $0 })
    }

    private func refreshLatestHeartRate(type: HKQuantityType) {
        let recentPredicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-10 * 60),
            end: nil,
            options: .strictStartDate
        )
        let query = HKSampleQuery(
            sampleType: type,
            predicate: recentPredicate,
            limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let value = Int(sample.quantity.doubleValue(for: unit).rounded())
            DispatchQueue.main.async {
                self?.bpm = value
            }
        }
        healthStore.execute(query)
    }
}

@Observable
private final class WatchRootPresentationState {
    var showAlert = false
    var alertMessage = ""
    var showBreathingSession = false
}

/// 手表根视图 由应用入口挂载，负责组合首页、同步与心率能力。
struct WatchRootView: View {
    @State private var hrManager = WatchHeartRateManager()
    @State private var receiver = WatchConnectivityReceiver.shared
    @State private var swimmingWorkoutManager = SwimmingWorkoutManager()
    @State private var presentationState = WatchRootPresentationState()

    var body: some View {
        NavigationStack {
            WatchHomeView(
                hrManager: hrManager,
                receiver: receiver,
                swimmingWorkoutManager: swimmingWorkoutManager
            )
        }
        .onAppear {
            hrManager.start()
            _ = receiver
            receiver.requestLatestFromiPhone()
        }
        .onDisappear {
            hrManager.stop()
        }
        .onChange(of: receiver.latest) { _, newValue in
            guard let bpm = newValue?.bpm else { return }
            if bpm > 120 {
                presentationState.alertMessage = String(localized: "检测到心率偏高 (\(bpm) 次/分)，建议稍作休息。")
                presentationState.showAlert = true
            } else if bpm < 40 {
                presentationState.alertMessage = String(localized: "检测到心率偏低 (\(bpm) 次/分)，请留意身体状态。")
                presentationState.showAlert = true
            }
        }
        .onChange(of: hrManager.bpm) { _, newValue in
            receiver.publishLocalHeartRate(newValue)
        }
        .onChange(of: receiver.isReachable) { _, newValue in
            guard newValue else { return }
            receiver.requestLatestFromiPhone()
        }
        .alert("心率提醒", isPresented: $presentationState.showAlert) {
            Button("知道了", role: .cancel) {}
            Button("开始呼吸") {
                presentationState.showBreathingSession = true
            }
        } message: {
            Text(presentationState.alertMessage)
        }
        .sheet(isPresented: $presentationState.showBreathingSession) {
            NavigationStack {
                BreathingSessionView()
            }
        }
    }
}
