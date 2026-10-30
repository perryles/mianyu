import SwiftUI
import SwiftData

/// 应用App结构体 作为当前模块里的辅助类型。
/// 负责启动主程序、挂载根视图，并初始化应用级依赖与全局状态。
@main
struct MianyuApp: App {
    @UIApplicationDelegateAdaptor(MianyuAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var deepLinkStore = DeepLinkStore()
    @State private var appFontScaleStore = AppFontScaleStore.shared
    
    init() {
        CloudKitDataPolicy.registerDefaultPreferences()
        // 受控数据迁移：App Group 业务 key → 标准 UserDefaults → SwiftData。
        // 幂等、增量、失败回滚，任何失败都不影响启动（详见 ControlledMigrationCoordinator）。
        ControlledMigrationCoordinator.runAtLaunch()
        AppNavigationAppearance.configure()
        // HealthKit 观察者改在 AppDelegate didFinishLaunching 中注册。
        _ = HealthDataManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deepLinkStore)
                .environment(appFontScaleStore)
                .environment(\.appFontScaleLevel, appFontScaleStore.level)
                .id(appFontScaleStore.level.rawValue)
                .task {
                    // 启动时先完成 HealthKit 授权与数据可用性评估，后续页面直接消费结果。
                    await HealthAuthorizationCoordinator.shared.evaluateAtLaunch()
                    await AppleSignInManager.shared.restorePreviousSignInIfNeeded()
                    await SubscriptionManager.shared.refreshEntitlement()
                    // 首次引导偏好已由 AppLaunchView 在路由放行前恢复，避免并发重复同步。
                    _ = await ICloudSyncCoordinator.shared.synchronizeEnabledDomains(
                        includePregnancy: false,
                        includeOnboardingPreference: false
                    )
                    DailyWellnessStore.shared.applyReminder(DailyWellnessStore.shared.loadReminderSettings())
                    RecoveryChallengeStore.shared.refreshReminderSchedule()
                    await PersonalizedReminderCenter.shared.evaluateAndReschedule()
                }
                .onOpenURL { url in
                    deepLinkStore.handle(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .notificationDidTapNavigation)) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        deepLinkStore.handle(url)
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    guard newPhase == .active else { return }
                    // PEN-3 P1-2/P2-2：回前台不再全局 force 重查（避免每次回前台全量 HealthKit 查询风暴），
                    // 由 syncAllDataIfNeeded 自带 5 分钟节流；用户主动刷新路径仍可 force。
                    HealthDataManager.shared.syncAllDataIfNeeded()
                    Task {
                        // 回前台重评估授权状态，覆盖用户去健康 App/系统设置改完权限返回的场景。
                        await HealthAuthorizationCoordinator.shared.handleScenePhaseActive()
                        DailyWellnessStore.shared.applyReminder(DailyWellnessStore.shared.loadReminderSettings())
                        RecoveryChallengeStore.shared.refreshReminderSchedule()
                        await PersonalizedReminderCenter.shared.evaluateAndReschedule()
                    }
                }
        }
        .modelContainer(MianyuModelContainer.shared)
    }
}
