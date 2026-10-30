/// ReportsContentView 由趋势页报告分段或报告入口调用，作为「报告」内容容器。
/// 负责组织报告总览（周期切换+评分环+AI 总结+指标网格）、报表入口、深入分析、最近报告与工具板块。

import SwiftUI

/// 报告内容视图 由趋势页报告分段或其他容器嵌入，作为报告模块里的界面或内容组件。
/// 负责组织报告总览、报表入口、深入分析、最近报告与工具板块。
struct ReportsContentView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @State private var viewModel = ReportSummaryViewModel()
    @State private var showingShareSheet = false
    @State private var showingAlertHistory = false
    @State private var detailNavigationDate: Date?

    private var historyItems: [ReportDaySummary] {
        Array(viewModel.days.filter(\.hasData).suffix(7).reversed())
    }

    private var recentPoints: [ReportDaySummary] {
        Array(viewModel.days.filter(\.hasData).suffix(14))
    }

    private var currentMonthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Calendar.current.startOfDay(for: Date()), duration: 30 * 24 * 3600)
    }

    private var currentMonthPoints: [ReportDaySummary] {
        viewModel.summaries(for: currentMonthInterval).filter { $0.hasData }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: adaptiveLayout.sectionSpacing) {
            // AnyView 边界：隔断每个板块的泛型类型，避免 iOS 27 运行时
            // 实例化整页深层嵌套类型时递归爆栈（与 HealthHubView 网格同类问题）。
            AnyView(ReportsOverviewSection(viewModel: viewModel, onOpenAlerts: {
                showingAlertHistory = true
            }, onOpenDetail: {
                detailNavigationDate = viewModel.latest?.date ?? Date()
            }))

            AnyView(reportLinksSection)

            AnyView(reportInsightSection)

            AnyView(ReportsSection(title: "最近报告", tint: Color(hex: "5B8CFF")) {
                reportsHistoryList(limit: 5)
            })

            AnyView(reportToolsSection)
        }
        .task {
            viewModel.load(days: 64)
        }
        .navigationDestination(item: $detailNavigationDate) { date in
            ReportDetailView(reportDate: date, initialSummary: viewModel.summary(for: date))
        }
        .sheet(isPresented: $showingAlertHistory) {
            NavigationStack {
                AlertHistoryView()
            }
            .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingShareSheet) {
            ReportShareView(reportDate: viewModel.latest?.date ?? Date(), score: viewModel.latest?.scoreValue ?? 0)
                .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.92), .large], dragIndicator: .hidden)
                .presentationCornerRadius(26)
                .presentationBackground(Color(hex: "F1F1EF"))
        }
    }

    private var reportLinksSection: some View {
        ReportsSection(title: "周期报告", tint: Theme.Colors.mintGreen) {
            VStack(spacing: 0) {
                NavigationLink {
                    DailyReportView()
                } label: {
                    reportDestinationRow(
                        title: "日报",
                        subtitle: "今天",
                        detail: "查看当日状态与恢复建议",
                        icon: "sun.max.fill",
                        tint: Color(hex: "F3A53B")
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 68)

                NavigationLink {
                    WeeklyReportView()
                } label: {
                    reportDestinationRow(
                        title: "报告详情",
                        subtitle: "近 7 天",
                        detail: "复盘节律、波动与关键趋势",
                        icon: "calendar",
                        tint: Color(hex: "5B8CFF")
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 68)

                NavigationLink {
                    WeeklyReportView(period: .month)
                } label: {
                    reportDestinationRow(
                        title: "月度报告",
                        subtitle: "本月",
                        detail: "观察长期变化与稳定性",
                        icon: "calendar.circle.fill",
                        tint: Theme.Colors.mintGreen
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .background(Theme.Colors.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func reportDestinationRow(
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }

                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var reportInsightSection: some View {
        ReportsSection(title: "深入分析", tint: Color(hex: "8E6CFF")) {
            VStack(alignment: .leading, spacing: 12) {
                ReportPeriodReviewCard(
                    title: "最近 14 天复盘",
                    subtitle: "平均分、最高/最低、关键支撑。",
                    scope: "近 14 天",
                    points: recentPoints
                )

                ReportMetricCompositeTrendCard(
                    title: "指标趋势",
                    subtitle: "睡眠、压力、HRV 和活动的同尺趋势。",
                    points: recentPoints,
                    kinds: [.sleep, .stress, .hrv, .activity]
                )

                ReportCalendarHeatmapCard(
                    title: "本月热力",
                    subtitle: "按天查看本月评分。",
                    points: currentMonthPoints,
                    interval: currentMonthInterval
                )

                reportAssociationAnalysisCard
            }
        }
    }

    /// 两个页面都是跨指标的长周期关联分析，承接在报告页的「深入分析」而不单独增加主导航。
    private var reportAssociationAnalysisCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                BehaviorImpactView()
            } label: {
                reportsGroupedRowContent(
                    title: "行为影响",
                    subtitle: "补水、咖啡因与睡眠压力的关联",
                    icon: "point.3.connected.trianglepath.dotted",
                    tint: Theme.Colors.mintGreen
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 70)

            NavigationLink {
                SleepStressAnalyticsView()
            } label: {
                reportsGroupedRowContent(
                    title: "睡眠与压力",
                    subtitle: "对照睡眠得分、HRV 和压力变化",
                    icon: "moon.stars.fill",
                    tint: Color(hex: "6D7EF7")
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
        )
    }

    private var reportToolsSection: some View {
        reportsGroupedSection(title: "工具") {
            Button {
                showingShareSheet = true
            } label: {
                reportsGroupedRowContent(title: "分享报告", subtitle: "生成健康分享卡", icon: "square.and.arrow.up", tint: Color(hex: "8E6CFF"))
            }
            .buttonStyle(.plain)
        }
    }

    private func reportsGroupedSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.mintGreen, Theme.Colors.mintGreen.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 15)

                Text(title)
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "555B58"))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 3)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
        }
    }

    private func reportsGroupedRowContent(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: tint.opacity(0.26), radius: 5, x: 0, y: 2)

                Image(systemName: icon)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "D7D9D7"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func reportsHistoryList(limit: Int) -> some View {
        if historyItems.isEmpty {
            ReportsInlineEmptyState(text: viewModel.isLoading ? "正在整理健康报告" : "健康 App 暂无可生成报告的数据")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(historyItems.prefix(limit))) { item in
                    NavigationLink {
                        ReportDetailView(reportDate: item.date, initialSummary: item)
                    } label: {
                        ReportsHistoryCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ReportsSection<Content: View>: View {
    let title: String
    var tint: Color = Color(hex: "9AA3AD")
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.appSystem(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)

                Rectangle()
                    .fill(tint.opacity(0.28))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)

            content
        }
    }
}

private struct ReportsHistoryCard: View {
    let item: ReportDaySummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(scoreTint.opacity(0.14), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: CGFloat(min(max(Double(item.score ?? 0) / 100.0, 0), 1)))
                    .stroke(scoreTint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(item.score.map(String.init) ?? "--")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(scoreTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.date.reportsShortDateString())
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(statusText)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(scoreTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(scoreTint.opacity(0.11), in: Capsule())
                }

                Text(historySummaryText)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.appSystem(size: 13, weight: .black))
                .foregroundColor(Color(hex: "B8BDC3"))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }

    private var historySummaryText: String {
        let values = [
            item.sleepHours.map { String(format: String(localized: "睡眠 %.1f 小时"), $0) },
            item.stress.map { "压力 \(Int($0.rounded()))" },
            item.steps.map { "步数 \(Int($0.rounded()))" }
        ].compactMap { $0 }
        return values.isEmpty ? "等待健康样本" : values.joined(separator: " · ")
    }

    private var scoreTint: Color {
        guard let score = item.score else { return Color(hex: "8AA0B8") }
        switch score {
        case 85...: return Theme.Colors.mintGreen
        case 70...84: return Color(hex: "5B8CFF")
        case 50...69: return Color(hex: "F3A53B")
        default: return Color(hex: "F46B5A")
        }
    }

    private var statusText: String {
        ReportScoreStatus.shortLabel(for: item.score)
    }

}

/// 报告内联空结构体 作为报告模块里的辅助类型。
/// 负责报告展示与分享。
struct ReportsInlineEmptyState: View {
    let text: String

    var body: some View {
        BBInlineEmptyState(systemImage: "doc.text.magnifyingglass", title: text)
    }
}

/// 报告柔和视图 由上级页面或路由调用，作为报告模块里的界面或内容组件。
/// 负责报告展示与分享。
struct ReportsSoftBackground: View {
    var body: some View {
        HealthDetailPageBackground()
    }
}

#Preview {
    NavigationStack {
        ZStack {
            ReportsSoftBackground()

            AdaptivePageScrollView(style: .reading, topPadding: 14, bottomPadding: 88) {
                ReportsContentView()
            }
        }
    }
}
