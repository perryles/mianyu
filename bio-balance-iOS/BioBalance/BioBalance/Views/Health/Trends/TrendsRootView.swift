/// TrendsRootView 由健康首页趋势入口调用，作为「趋势」模块独立页面。
/// 负责根据 Pro 权限切换展示 TrendsDashboardView 或锁定页，并管理付费墙弹窗。

import SwiftUI

/// 趋势独立页面。趋势与报告分别从健康首页进入，不再共用页内分段切换。
struct TrendsRootView: View {
    @Bindable var periodViewModel: PeriodViewModel
    @State private var showingPaywall = false
    @Bindable var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        ZStack {
            ambientBackground

            if subscriptionManager.hasEntitlement(.pro) {
                TrendsDashboardView(periodViewModel: periodViewModel)
            } else {
                TrendsLockedView {
                    showingPaywall = true
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        // 作为 Tab 根页面隐藏系统导航栏，标题头由内容自绘，与其他 Tab 首页一致。
        .toolbar(.hidden, for: .navigationBar)
    }

    private var ambientBackground: some View {
        HealthDetailPageBackground()
    }
}

#Preview("趋势") {
    NavigationStack {
        TrendsRootView(periodViewModel: PeriodViewModel())
    }
}
