import BackgroundTasks
import CloudKit
import UIKit
import UserNotifications

final class MianyuAppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - 应用生命周期

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 官方要求在 didFinishLaunching 尽早注册 HealthKit 观察者，
        // 后台交付唤醒 App 时才能重新接上更新回调。
        HealthKitManager.shared.registerObserversIfNeeded()

        // 设置通知代理（必须在请求权限之前）
        UNUserNotificationCenter.current().delegate = self

        // 注册通知分类（支持快捷操作）
        registerNotificationCategories()

        // 注册 APNs 远程推送
        registerForRemoteNotificationsIfAuthorized()

        // 清理上次残留的 Live Activity
        cleanupStaleLiveActivities()

        // 注册并调度 Widget 后台刷新任务：系统按机会唤醒 App 重新发布小组件快照
        registerBackgroundTasks()
        scheduleWidgetBackgroundRefresh()

        return true
    }

    /// App 进入后台前提交 Widget 刷新请求，让小组件在系统允许时保持数据新鲜
    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleWidgetBackgroundRefresh()
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MianyuSceneDelegate.self
        return configuration
    }

    // MARK: - APNs 注册

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[推送] APNs 注册成功 token=\(token)")
        // 本地优先：无自建后端，不上传 Token；推送仍走系统 APNs 与本地通知。
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[推送] APNs 注册失败: \(error.localizedDescription)")
    }

    // MARK: - 小组件后台刷新（BGTaskScheduler）

    /// Widget 后台刷新任务标识，需与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 保持一致
    private static let widgetRefreshTaskIdentifier = "com.boundesu.BioBalance.widget-refresh"

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.widgetRefreshTaskIdentifier,
            // UIApplicationDelegate and this callback are MainActor-isolated.
            // A nil queue lets the system invoke the callback on a background queue,
            // which trips Swift 6's executor assertion before the handler body runs.
            using: .main
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleWidgetRefreshTask(refreshTask)
        }
    }

    private func scheduleWidgetBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.widgetRefreshTaskIdentifier)
        // 至少 15 分钟后再执行，给系统留出合并窗口，避免频繁唤醒
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 调度失败不影响主流程；HealthKit 后台交付仍会触发小组件刷新
            print("[Widget刷新] 提交后台刷新任务失败: \(error.localizedDescription)")
        }
    }

    /// 后台刷新处理器：重新拉取健康数据并发布小组件快照后完成
    private func handleWidgetRefreshTask(_ task: BGAppRefreshTask) {
        // 续期下一次刷新
        scheduleWidgetBackgroundRefresh()

        let execution = WidgetBackgroundRefreshExecution { success in
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        }
        // Expiration can arrive on a system queue. Explicitly Sendable prevents
        // the closure from inheriting MainActor isolation at its entry point.
        task.expirationHandler = { @Sendable in
            Task { @MainActor in
                execution.expire()
            }
        }
        execution.start {
            await HealthDataManager.shared.syncAllData(forceRefresh: false)
        } publish: {
            WidgetSyncService.refresh(
                WidgetRefreshDomain.appVisibleDefaults,
                reason: .healthUpdate,
                force: true
            )
        }
    }

    // MARK: - 私有实现

    private func registerForRemoteNotificationsIfAuthorized() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional ||
                  settings.authorizationStatus == .ephemeral else {
                return
            }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func cleanupStaleLiveActivities() {
        #if canImport(ActivityKit) && os(iOS)
        Task {
            await ReminderLiveActivityController.shared.cleanupStaleActivities()
        }
        #endif
    }

    private func registerNotificationCategories() {
        // 个性化恢复提醒分类 — 支持"查看详情"快捷操作
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "查看详情",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "稍后提醒",
            options: [.destructive]
        )
        let personalizedCategory = UNNotificationCategory(
            identifier: LocalNotificationScheduler.personalizedCategoryIdentifier,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // 喝水提醒分类
        let drinkAction = UNNotificationAction(
            identifier: "DRINK_DONE_ACTION",
            title: "已喝水",
            options: []
        )
        let waterCategory = UNNotificationCategory(
            identifier: "water.reminder",
            actions: [drinkAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // 用药提醒分类
        let takeMedAction = UNNotificationAction(
            identifier: "MEDICATION_TAKEN_ACTION",
            title: "已服药",
            options: []
        )
        let medicationCategory = UNNotificationCategory(
            identifier: "medication.reminder",
            actions: [takeMedAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            personalizedCategory,
            waterCategory,
            medicationCategory
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension MianyuAppDelegate: UNUserNotificationCenterDelegate {

    /// 前台收到通知时展示横幅和声音
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// 用户点击通知后的跳转处理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let actionIdentifier = response.actionIdentifier

        print("[推送] 通知交互 category=\(categoryIdentifier) action=\(actionIdentifier)")

        // 根据 actionIdentifier 处理快捷操作
        switch actionIdentifier {
        case "DRINK_DONE_ACTION":
            // 用户已确认喝水，可在此记录
            print("[推送] 用户通过通知确认已喝水")
            return
        case "MEDICATION_TAKEN_ACTION":
            print("[推送] 用户通过通知确认已服药")
            return
        case "DISMISS_ACTION":
            return
        default:
            break
        }

        // 根据 userInfo 或 category 路由到对应页面
        let deepLink = resolveDeepLink(from: userInfo, category: categoryIdentifier)
        if let deepLink, let url = URL(string: deepLink) {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .notificationDidTapNavigation,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
    }

    private func resolveDeepLink(from userInfo: [AnyHashable: Any], category: String) -> String? {
        // 优先使用 userInfo 中后端下发的路由
        if let route = userInfo["deepLink"] as? String, !route.isEmpty {
            return route
        }
        if let route = userInfo["route"] as? String, !route.isEmpty {
            return "biobalance://\(route)"
        }

        // 根据通知分类推断路由
        switch category {
        case "water.reminder":
            return "biobalance://widget/overall"
        case "medication.reminder":
            return "biobalance://widget/overall"
        case LocalNotificationScheduler.personalizedCategoryIdentifier:
            return "biobalance://widget/stress"
        default:
            return nil
        }
    }
}

// MARK: - Notification Name for navigation

extension Notification.Name {
    static let notificationDidTapNavigation = Notification.Name("notificationDidTapNavigation")
}

// MARK: - Scene Delegate (CloudKit Sharing)

final class MianyuSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        print("[社交共享] 冷启动收到 CloudKit 分享 metadata share=\(metadata.share.recordID.recordName)")
        acceptCloudKitShare(metadata)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        print("[社交共享] 前台收到 CloudKit 分享 metadata share=\(cloudKitShareMetadata.share.recordID.recordName)")
        acceptCloudKitShare(cloudKitShareMetadata)
    }

    private func acceptCloudKitShare(_ metadata: CKShare.Metadata) {
        Task {
            print("[社交共享] 开始接收共享 share=\(metadata.share.recordID.recordName)")
            await SharedHealthDataStore.shared.acceptShare(metadata: metadata)
        }
    }
}
