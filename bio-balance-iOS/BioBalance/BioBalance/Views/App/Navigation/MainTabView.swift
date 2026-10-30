/// MainTabView 由应用根路由调用，作为「主标签」根容器页面。
/// 负责组织今日、健康、趋势、目标、我的五个 Tab 的页面切换、深度链接路由和弹窗态管理。

import SwiftUI

/// 主标签枚举 作为共享界面层里的能力或分类定义。
/// 负责描述共享布局与通用界面能力过程中会用到的状态、分类或分支。
enum MainTab: String, CaseIterable {
    case today = "今日"
    case vitality = "健康"
    case trends = "趋势"
    case goals = "目标"
    case settings = "我的"

    /// 本地化标题：非 SwiftUI 字面量场景需显式走 String Catalog。
    var title: String {
        switch self {
        case .today: return String(localized: "今日")
        case .vitality: return String(localized: "健康")
        case .trends: return String(localized: "趋势")
        case .goals: return String(localized: "目标")
        case .settings: return String(localized: "我的")
        }
    }

    var icon: String {
        switch self {
        case .today: return Theme.Icons.today
        case .vitality: return "figure.run.circle.fill"
        case .trends: return "chart.xyaxis.line"
        case .goals: return "target"
        case .settings: return "person.crop.circle.fill"
        }
    }

}

/// 主标签视图 由上级页面或路由调用，作为共享界面层里的界面或内容组件。
/// 负责共享布局与通用界面能力。
struct MainTabView: View {
    @State private var selectedTab: MainTab = .today
    @Environment(DeepLinkStore.self) private var deepLinkStore
    @State private var modalRoute: ModalRoute?
    @State private var periodViewModel = PeriodViewModel()
    @AppStorage("purchase_pending") private var purchasePending: Bool = false
    @AppStorage("purchase_pending_sku") private var purchasePendingSku: String = ""
    @State private var showingPaywall = false
    @State private var vitalityRoute: VitalityRoute?
    @State private var goalLinkedAction: DailyWellnessActionKind?
    @State private var goalLinkedDate: Date?
    @State private var goalRefreshToken = 0
    
    var body: some View {
        AdaptiveLayoutReader { layout in
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(
                        periodViewModel: periodViewModel,
                        openReproductiveRecord: openReproductiveRecord
                    )
                }
                .environment(\.adaptiveLayout, layout)
                .tabItem { Label(MainTab.today.title, systemImage: MainTab.today.icon) }
                .tag(MainTab.today)

                NavigationStack {
                    HealthHubView(
                        periodViewModel: periodViewModel,
                        openReproductiveRecord: openReproductiveRecord,
                        route: $vitalityRoute,
                        goalLinkedAction: goalLinkedAction,
                        goalLinkedDate: goalLinkedDate
                    )
                }
                .environment(\.adaptiveLayout, layout)
                .tabItem { Label(MainTab.vitality.title, systemImage: MainTab.vitality.icon) }
                .tag(MainTab.vitality)

                NavigationStack {
                    TrendsRootView(periodViewModel: periodViewModel)
                }
                .environment(\.adaptiveLayout, layout)
                .tabItem { Label(MainTab.trends.title, systemImage: MainTab.trends.icon) }
                .tag(MainTab.trends)

                NavigationStack {
                    GoalsView(
                        refreshToken: goalRefreshToken,
                        onOpenLinkedAction: openGoalLinkedAction
                    )
                }
                .environment(\.adaptiveLayout, layout)
                .tabItem { Label(MainTab.goals.title, systemImage: MainTab.goals.icon) }
                .tag(MainTab.goals)

                NavigationStack {
                    ProfileView()
                }
                .environment(\.adaptiveLayout, layout)
                .tabItem { Label(MainTab.settings.title, systemImage: MainTab.settings.icon) }
                .tag(MainTab.settings)
            }
            .tint(Theme.Colors.mintGreen)
            .ignoresSafeArea(.keyboard)
            .onAppear {
                if let pending = deepLinkStore.pending {
                    handleDeepLink(pending)
                    deepLinkStore.pending = nil
                }
                handlePurchasePending()
            }
            .onChange(of: deepLinkStore.pending) { _, newValue in
                guard let newValue else { return }
                handleDeepLink(newValue)
                deepLinkStore.pending = nil
            }
            .onChange(of: purchasePending) { _, _ in
                handlePurchasePending()
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == .goals {
                    goalRefreshToken += 1
                }
            }
            .sheet(item: $modalRoute) { route in
                switch route {
                case .stress:
                    NavigationStack {
                        StressRootView()
                    }
                    .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
                case .activity:
                    NavigationStack {
                        ActivityDetailView(realtimeHealth: nil, history: nil)
                    }
                    .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
                case .sleep:
                    NavigationStack {
                        SleepView(showsDismissButton: true)
                    }
                    .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
                case .sunlight:
                    SunlightSheetView(initialDate: Date(), showsDismissButton: true)
                        .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
                }
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                purchasePendingSku = ""
            }) {
                PaywallView(initialSku: purchasePendingSku.isEmpty ? nil : purchasePendingSku)
                    .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
            }
        }
    }

    private enum ModalRoute: String, Identifiable {
        case stress
        case activity
        case sleep
        case sunlight
        
        var id: String { rawValue }
    }

    /// Vitality Route 枚举，作为内部辅助类型，用于细分外层共享布局与通用界面能力中的状态或分支。
    enum VitalityRoute: String, Identifiable {
        case mealHub
        case drinkHub
        case medicationHub
        case moodHub
        case dailyAction
        case goalAction
        case reproductiveRecord
        case pregnancyRecord
        case bodyAge
        case careHub

        var id: String { rawValue }
    }
    
    private func handleDeepLink(_ deepLink: MianyuDeepLink) {
        switch deepLink {
        case .home:
            selectedTab = .today
            modalRoute = nil
        case .widget(.overall):
            selectedTab = .today
            modalRoute = nil
        case .widget(.vitals):
            selectedTab = .today
            modalRoute = nil
        case .widget(.stress):
            selectedTab = .today
            modalRoute = .stress
        case .widget(.activity):
            selectedTab = .today
            modalRoute = .activity
        case .widget(.sleep):
            selectedTab = .today
            modalRoute = .sleep
        case .widget(.sunlight):
            selectedTab = .today
            modalRoute = .sunlight
        case .watchDashboard:
            selectedTab = .today
            modalRoute = nil
        case .reminder:
            selectedTab = .today
            modalRoute = nil
        }
    }

    private func handlePurchasePending() {
        let result = PurchasePendingRouter.consume(pending: purchasePending)
        purchasePending = result.pending
        guard result.shouldShowPaywall else { return }
        selectedTab = .vitality
        showingPaywall = true
    }

    private func openReproductiveRecord() {
        vitalityRoute = .reproductiveRecord
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            selectedTab = .vitality
        }
    }

    private func openGoalLinkedAction(_ action: DailyWellnessActionKind, date: Date) {
        goalLinkedAction = action
        goalLinkedDate = Calendar.current.startOfDay(for: date)
        vitalityRoute = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = .vitality
        }

        DispatchQueue.main.async {
            vitalityRoute = .goalAction
        }
    }

}

#Preview {
    MainTabView()
        .environment(DeepLinkStore())
}
