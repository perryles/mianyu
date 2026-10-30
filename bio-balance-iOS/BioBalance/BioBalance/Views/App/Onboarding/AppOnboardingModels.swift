import Foundation
import Observation

enum AppOnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case focus
    case healthPermission
    case watch
    case dailyPreview
    case ready

    var id: Int { rawValue }
    var number: Int { rawValue + 1 }

    var shortTitle: String {
        switch self {
        case .welcome: String(localized: "欢迎")
        case .focus: String(localized: "关注重点")
        case .healthPermission: String(localized: "健康数据")
        case .watch: "Apple Watch"
        case .dailyPreview: String(localized: "今日状态")
        case .ready: String(localized: "开始使用")
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome: String(localized: "开始我的眠屿")
        case .focus: String(localized: "继续设置")
        case .healthPermission: String(localized: "选择并授权")
        case .watch: String(localized: "继续看看")
        case .dailyPreview: String(localized: "继续")
        case .ready: String(localized: "进入眠屿")
        }
    }
}

enum AppOnboardingFocus: String, CaseIterable, Identifiable {
    case sleep = "sleep"
    case stress = "stress"
    case activity = "activity"
    case body = "body"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: String(localized: "睡眠与恢复")
        case .stress: String(localized: "压力与情绪")
        case .activity: String(localized: "活动与体能")
        case .body: String(localized: "身体趋势")
        }
    }

    var detail: String {
        switch self {
        case .sleep: String(localized: "昨晚睡得怎么样")
        case .stress: String(localized: "什么时候更容易紧绷")
        case .activity: String(localized: "今天动得够不够")
        case .body: String(localized: "长期变化有没有异常")
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.fill"
        case .stress: "waveform.path"
        case .activity: "arrow.up.right"
        case .body: "scope"
        }
    }
}

enum AppOnboardingPreferences {
    static let completedKey = "hasCompletedAppOnboarding"
    static let focusKey = OnboardingPreferenceCloudStore.LocalKey.focusAreas
    private static let legacyCompletedKey = "hasCompletedFirstLaunchOnboarding"

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: completedKey) == nil else { return }
        let hadCompletedLegacyFlow = defaults.bool(forKey: legacyCompletedKey)
        let isExistingUser = defaults.bool(forKey: "isLoggedIn") || defaults.bool(forKey: "isGuest")
        if hadCompletedLegacyFlow || isExistingUser {
            defaults.set(true, forKey: completedKey)
        }
    }

    static func selectedFocus(defaults: UserDefaults = .standard) -> AppOnboardingFocus {
        let savedValue = defaults.string(forKey: focusKey)?
            .split(separator: ",")
            .first
            .map(String.init)
        return savedValue.flatMap(AppOnboardingFocus.init(rawValue:)) ?? .sleep
    }

    static func saveFocus(_ focus: AppOnboardingFocus, defaults: UserDefaults = .standard) {
        defaults.set(focus.rawValue, forKey: focusKey)
        defaults.set(Date(), forKey: OnboardingPreferenceCloudStore.LocalKey.updatedAt)
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }

    #if DEBUG
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
    }
    #endif
}

@MainActor
@Observable
final class AppOnboardingStore {
    private(set) var currentStep: AppOnboardingStep
    private(set) var selectedFocus: AppOnboardingFocus
    private(set) var healthAuthorizationPhase: HealthAuthorizationPhase = .unknown
    private(set) var isRequestingAuthorization = false

    private let defaults: UserDefaults

    init(currentStep: AppOnboardingStep = .welcome, defaults: UserDefaults = .standard) {
        self.currentStep = currentStep
        self.defaults = defaults
        selectedFocus = AppOnboardingPreferences.selectedFocus(defaults: defaults)
        if defaults.object(forKey: AppOnboardingPreferences.focusKey) == nil {
            AppOnboardingPreferences.saveFocus(selectedFocus, defaults: defaults)
        }
    }

    func next() {
        guard let next = AppOnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func previous() {
        guard let previous = AppOnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    func selectFocus(_ focus: AppOnboardingFocus) {
        guard focus != selectedFocus else { return }
        selectedFocus = focus
        AppOnboardingPreferences.saveFocus(focus, defaults: defaults)
    }

    func refreshHealthAuthorization(
        using evaluate: @escaping @MainActor () async -> HealthAuthorizationPhase
    ) async {
        guard !isRequestingAuthorization else { return }
        healthAuthorizationPhase = await evaluate()
    }

    @discardableResult
    func requestHealthAuthorization(
        using request: @escaping @MainActor () async -> HealthAuthorizationPhase
    ) async -> HealthAuthorizationPhase {
        guard !isRequestingAuthorization else { return healthAuthorizationPhase }
        isRequestingAuthorization = true
        let phase = await request()
        healthAuthorizationPhase = phase
        isRequestingAuthorization = false
        return phase
    }

    func markCompleted() {
        AppOnboardingPreferences.markCompleted(defaults: defaults)
    }
}

extension HealthAuthorizationPhase {
    var canContinueWithoutRequest: Bool {
        switch self {
        case .unavailable, .authorizedFresh, .authorizedNeedsRefresh, .authorizedNoData:
            true
        case .unknown, .promptAvailable:
            false
        }
    }

    var onboardingStatusText: String {
        switch self {
        case .unknown: String(localized: "正在检查")
        case .unavailable: String(localized: "当前设备不可用")
        case .promptAvailable: String(localized: "等待系统选择")
        case .authorizedFresh, .authorizedNeedsRefresh: String(localized: "已检测到可读数据")
        case .authorizedNoData: String(localized: "已完成系统选择")
        }
    }

    var shouldPlaySuccessHaptic: Bool {
        switch self {
        case .authorizedFresh, .authorizedNeedsRefresh: true
        case .unknown, .unavailable, .promptAvailable, .authorizedNoData: false
        }
    }
}
