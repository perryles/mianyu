import CloudKit
import Foundation

/// iCloud 管理页与 App 启动流程共用的跨业务域同步编排器。
///
/// 业务记录的编解码和合并仍由各 Feature Repository / Store 负责；
/// 这里只统一账户检查、偏好开关与同步调度，避免 View 直接编排多个业务 Store。
@MainActor
final class ICloudSyncCoordinator {
    static let shared = ICloudSyncCoordinator()

    private let defaults: UserDefaults
    private let container: CKContainer

    init(
        defaults: UserDefaults = .standard,
        container: CKContainer = CloudKitDataPolicy.makeContainer()
    ) {
        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        self.defaults = defaults
        self.container = container
    }

    func accountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }

    /// 同步所有已开启项目。孕期数据默认按需读取，只在用户手动同步时纳入。
    func synchronizeEnabledDomains(
        includePregnancy: Bool,
        includeOnboardingPreference: Bool = true
    ) async -> ICloudSyncReport {
        let status = await accountStatus()
        guard status == .available else {
            return ICloudSyncReport(accountStatus: status, outcomes: [])
        }

        var domains = ICloudSyncDomain.allCases.filter(isEnabled)
        if !includePregnancy {
            domains.removeAll { $0 == .pregnancy }
        }
        if !includeOnboardingPreference {
            domains.removeAll { $0 == .onboardingPreference }
        }

        var outcomes: [ICloudSyncOutcome] = []
        for domain in domains {
            outcomes.append(await synchronize(domain))
        }

        // 云端数据拉取后重新发布小组件快照并刷新 timeline，
        // 让 Widget / Complications 尽快反映多设备同步结果（PEN-15 增量同步链路）。
        WidgetSyncService.refresh(
            WidgetRefreshDomain.appVisibleDefaults,
            reason: .healthUpdate,
            force: true
        )

        return ICloudSyncReport(accountStatus: status, outcomes: outcomes)
    }

    func synchronize(_ domain: ICloudSyncDomain) async -> ICloudSyncOutcome {
        guard isEnabled(domain) else {
            return ICloudSyncOutcome(domain: domain, state: .skipped)
        }

        switch domain {
        case .drinkExperience:
            let succeeded = await DrinkExperienceStore.shared.synchronizePrivateCloud()
            return outcome(domain, succeeded: succeeded)
        case .sleepSummary:
            await SleepMonitoringOrchestrator.shared.restoreState()
            return ICloudSyncOutcome(domain: domain, state: .succeeded)
        case .medicationHealth:
            let succeeded = await MedicationHealthCloudSyncCoordinator.shared.synchronize()
            return outcome(domain, succeeded: succeeded)
        case .pregnancy:
            do {
                _ = try await PregnancyCloudKitRepository().fetchSnapshot()
                return ICloudSyncOutcome(domain: domain, state: .succeeded)
            } catch {
                return ICloudSyncOutcome(domain: domain, state: .failed, message: error.localizedDescription)
            }
        case .goalMascot:
            GoalsStore.shared.refreshMascotFromCloud()
            return ICloudSyncOutcome(domain: domain, state: .requested)
        case .onboardingPreference:
            let succeeded = await OnboardingPreferenceCloudStore.shared.synchronize()
            return outcome(domain, succeeded: succeeded)
        case .socialSharing:
            await SharedHealthDataStore.shared.bootstrap()
            await SharedHealthDataStore.shared.refresh()
            return ICloudSyncOutcome(domain: domain, state: .succeeded)
        }
    }

    func isEnabled(_ domain: ICloudSyncDomain) -> Bool {
        defaults.bool(forKey: domain.preferenceKey)
    }

    private func outcome(_ domain: ICloudSyncDomain, succeeded: Bool) -> ICloudSyncOutcome {
        ICloudSyncOutcome(
            domain: domain,
            state: succeeded ? .succeeded : .failed,
            message: succeeded ? nil : "未能完成同步，请稍后重试"
        )
    }
}

nonisolated enum ICloudSyncDomain: String, CaseIterable, Sendable {
    case drinkExperience
    case sleepSummary
    case medicationHealth
    case pregnancy
    case goalMascot
    case onboardingPreference
    case socialSharing

    var preferenceKey: String {
        switch self {
        case .drinkExperience: CloudKitDataPolicy.PreferenceKey.drinkExperienceSyncEnabled
        case .sleepSummary: CloudKitDataPolicy.PreferenceKey.sleepSummarySyncEnabled
        case .medicationHealth: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled
        case .pregnancy: CloudKitDataPolicy.PreferenceKey.pregnancySyncEnabled
        case .goalMascot: CloudKitDataPolicy.PreferenceKey.goalMascotSyncEnabled
        case .onboardingPreference: CloudKitDataPolicy.PreferenceKey.onboardingPreferenceSyncEnabled
        case .socialSharing: CloudKitDataPolicy.PreferenceKey.socialSharingEnabled
        }
    }
}

nonisolated struct ICloudSyncOutcome: Sendable {
    enum State: Equatable, Sendable {
        case succeeded
        case requested
        case failed
        case skipped
    }

    let domain: ICloudSyncDomain
    let state: State
    let message: String?

    init(domain: ICloudSyncDomain, state: State, message: String? = nil) {
        self.domain = domain
        self.state = state
        self.message = message
    }
}

nonisolated struct ICloudSyncReport: Sendable {
    let accountStatus: CKAccountStatus
    let outcomes: [ICloudSyncOutcome]

    var failureCount: Int { outcomes.filter { $0.state == .failed }.count }
    var successfulCount: Int { outcomes.filter { $0.state == .succeeded || $0.state == .requested }.count }
}
