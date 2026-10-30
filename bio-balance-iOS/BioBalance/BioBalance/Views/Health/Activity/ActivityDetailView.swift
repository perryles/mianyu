/// ActivityDetailView 由健康首页活动入口调用，作为「活动概览」详情页。
/// 负责展示实时活动数据、活动历史趋势与权限引导。

import SwiftUI

/// Activity视图 由上级页面或路由调用，作为活动模块里的界面或内容组件。
/// 负责展示运动概览、活动详情与趋势变化。
struct ActivityDetailView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let realtimeHealth: RealtimeHealth?
    let history: HealthHistory?
    
    @State private var viewModel = ActivityViewModel()
    @Bindable private var subscriptionManager = SubscriptionManager.shared
    @State private var isRequestingAuthorization = false
    @State private var showingPaywall = false
    
    var body: some View {
        ZStack {
            Theme.Colors.secondaryBackground
                .ignoresSafeArea()
            
            AdaptivePageScrollView(style: .reading, topPadding: 18, bottomPadding: 96) {
                VStack(spacing: adaptiveLayout.sectionSpacing) {
                    ActivityDetailHero(data: viewModel.activityData, lastUpdatedAt: viewModel.lastUpdatedAt)

                    if let missingReason = viewModel.missingReason {
                        missingReasonCard(reason: missingReason)
                    } else {
                        if let data = viewModel.activityData {
                            ActivityDataCard(
                                steps: data.steps,
                                activeEnergy: data.active_energy,
                                exerciseTime: data.exercise_time,
                                standHours: data.stand_hours
                            )
                        } else {
                            ActivityDataCard(steps: 0, activeEnergy: 0, exerciseTime: 0, standHours: 0)
                                .redacted(reason: .placeholder)
                        }
                        
                        ActivityLockedModuleContainer(isUnlocked: subscriptionManager.isPro) {
                            ActivityTrendChartView(
                                steps: viewModel.dailySteps,
                                activeEnergy: viewModel.dailyActiveEnergy,
                                exerciseMinutes: viewModel.dailyExerciseMinutes,
                                standHours: viewModel.dailyStandHours,
                                walkingSpeed: viewModel.dailyWalkingSpeed
                            )
                        } onUnlock: {
                            showingPaywall = true
                        }
                        
                        ActivitySummaryCard(realtimeHealth: realtimeHealth)
                            .glassCard()
                        
                        ActivityLockedModuleContainer(isUnlocked: subscriptionManager.isPro) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text("详情")
                                                .font(.appSystem(.headline, design: .default))
                                                .foregroundColor(Theme.Colors.textPrimary)
                                            ActivityProBadge()
                                        }

                                        Text("把活动表现和心率、HRV、压力一起看，更容易判断今天该继续推进还是该回收负荷。")
                                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(Theme.Colors.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                
                                NavigationLink {
                                    HeartRateDetailView(history: history)
                                } label: {
                                    ActivityDetailRow(
                                        title: "心率详情",
                                        subtitle: "查看今日心率走势",
                                        icon: "heart.fill",
                                        tint: Theme.Colors.accentRed,
                                        badge: "实时节律",
                                        insight: "更适合看活动后的恢复速度和当前节奏是否偏快。"
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                NavigationLink {
                                    HRVDetailView(realtimeHealth: realtimeHealth)
                                } label: {
                                    ActivityDetailRow(
                                        title: "心率变异性详情",
                                        subtitle: "查看短窗口 HRV",
                                        icon: "waveform.path.ecg",
                                        tint: Theme.Colors.accentBlue,
                                        badge: "恢复状态",
                                        insight: "更适合判断最近负荷、睡眠与恢复有没有跟上。"
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                NavigationLink {
                                    PressureDetailView(history: history)
                                } label: {
                                    ActivityDetailRow(
                                        title: "压力详情",
                                        subtitle: "查看压力波动",
                                        icon: "brain.head.profile",
                                        tint: Color(hex: "FFB340"),
                                        badge: "负荷判断",
                                        insight: "更适合读活动之外的紧张负荷，避免把所有疲劳都当成运动问题。"
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                NavigationLink {
                                    BreathingDetailView()
                                } label: {
                                    ActivityDetailRow(
                                        title: "呼吸详情",
                                        subtitle: "查看呼吸练习记录",
                                        icon: "wind",
                                        tint: Theme.Colors.mintGreen,
                                        badge: "主动恢复",
                                        insight: "更适合把呼吸练习作为活动后的回收和放松补充。"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .glassCard()
                        } onUnlock: {
                            showingPaywall = true
                        }
                    }
                }
            }
        }
        .navigationTitle("活动")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .onAppear {
            viewModel.loadData()
        }
    }

    @ViewBuilder
    private func missingReasonCard(reason: HealthDataMissingReason) -> some View {
        switch reason {
        case .notAuthorized:
            VStack(alignment: .leading, spacing: 12) {
                Text("需要健康数据授权")
                    .font(.appSystem(.headline, design: .default))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("为展示站立、步数、步速、训练、声音与恢复趋势，请允许读取系统健康数据。")
                    .font(.appSystem(.subheadline, design: .default))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    handleAuthorizationButton()
                } label: {
                    Text(isRequestingAuthorization ? "处理中..." : "去授权")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.mintGreen)
                        .cornerRadius(14)
                }
                .disabled(isRequestingAuthorization)
            }
            .padding(16)
            .glassCard()
        case .noData:
            VStack(alignment: .leading, spacing: 12) {
                Text("暂无活动数据")
                    .font(.appSystem(.headline, design: .default))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("当前还没有可展示的活动记录，稍后再试或手动刷新。")
                    .font(.appSystem(.subheadline, design: .default))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    viewModel.loadData()
                } label: {
                    Text("刷新")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.Colors.mintGreen)
                        .cornerRadius(14)
                }
            }
            .padding(16)
            .glassCard()
        }
    }

    private func handleAuthorizationButton() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        Task { @MainActor in
            let phase = await HealthAuthorizationCoordinator.shared.requestAuthorizationIfNeeded()
            isRequestingAuthorization = false
            if phase.isAuthorizedLike {
                viewModel.loadData()
            }
        }
    }
}

private struct ActivityLockedModuleContainer<Content: View>: View {
    let isUnlocked: Bool
    @ViewBuilder let content: () -> Content
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            content()
                .blur(radius: isUnlocked ? 0 : 4)
                .allowsHitTesting(isUnlocked)

            if !isUnlocked {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.appSystem(size: 28))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text("会员可查看该内容")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Button(action: onUnlock) {
                        Text("免费试用")
                            .font(Theme.Typography.bodyMedium.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Theme.Colors.mintGreen)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isUnlocked else { return }
            onUnlock()
        }
    }
}

/// ActivityPro标签组件 作为活动模块里的信息标签组件。
/// 负责活动数据展示与分析。
struct ActivityProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.appSystem(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.accentBlue, Theme.Colors.mintGreen],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .fixedSize()
    }
}

private struct ActivityDetailHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let data: ActivityData?
    let lastUpdatedAt: Date?

    private var steps: Int { data?.steps ?? 0 }
    private var exercise: Int { data?.exercise_time ?? 0 }
    private var activeEnergy: Int { data?.active_energy ?? 0 }
    private var standHours: Int { data?.stand_hours ?? 0 }
    private var stepsGoal: Int { AppGroupManager.shared.getStepsGoal() ?? 8000 }
    private var exerciseGoal: Int {
        let stored = AppGroupManager.shared.getExerciseMinutesGoal() ?? 0
        return stored > 0 ? stored : 30
    }
    private var standGoal: Int {
        let stored = AppGroupManager.shared.getStandHoursGoal() ?? 0
        return stored > 0 ? stored : 12
    }
    private var stepProgress: Double { progress(value: steps, goal: stepsGoal) }
    private var exerciseProgress: Double { progress(value: exercise, goal: exerciseGoal) }
    private var standProgress: Double { progress(value: standHours, goal: standGoal) }
    private var overallProgress: Double { min(1.0, (stepProgress + exerciseProgress + standProgress) / 3.0) }
    private var completedGoalCount: Int { [stepProgress, exerciseProgress, standProgress].filter { $0 >= 1.0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日活动")
                        .font(.appSystem(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(heroHeadline)
                        .font(.appSystem(size: 19, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(activitySummary)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        heroPill(title: "已完成", value: "\(completedGoalCount)/3")
                        heroPill(title: "当前重点", value: focusText)
                    }
                }

                Spacer(minLength: 0)

                completionDial
            }

            HStack(spacing: 10) {
                heroMetric(title: "步数", value: "\(steps)", unit: "步", tint: Theme.Colors.mintGreen)
                heroMetric(title: "锻炼", value: "\(exercise)", unit: "分钟", tint: Color(hex: "5E5CE6"))
                heroMetric(title: "消耗", value: "\(activeEnergy)", unit: "千卡", tint: Color(hex: "FF9F0A"))
            }

            VStack(spacing: 12) {
                progressRow(title: "步数目标", valueText: "\(steps) / \(stepsGoal) 步", progress: stepProgress, tint: Theme.Colors.mintGreen, trailingText: stepGapText)
                progressRow(title: "锻炼目标", valueText: "\(exercise) / \(exerciseGoal) 分钟", progress: exerciseProgress, tint: Color(hex: "5E5CE6"), trailingText: exerciseGapText)
                progressRow(title: "站立目标", valueText: "\(standHours) / \(standGoal) 小时", progress: standProgress, tint: Color(hex: "73C8E8"), trailingText: standGapText)
            }

            HStack(spacing: 12) {
                if let lastUpdatedAt {
                    Text("更新于 \(timeString(lastUpdatedAt))")
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer()

                Text(bottomInsightText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Theme.Colors.mintGreen.opacity(0.18),
                    Color(hex: "EAF8F0"),
                    Color(hex: "F3FBF7"),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.045), radius: 18, x: 0, y: 10)
    }

    private var heroHeadline: String {
        guard data != nil else { return "正在整理今天的活动概览" }
        if overallProgress >= 0.95 { return "今天的活动完成度已经很完整" }
        if overallProgress >= 0.66 { return "今天的活动节奏已经稳住了" }
        if overallProgress >= 0.33 { return "已经动起来了，继续把节奏接上" }
        return "今天还可以再主动活动一点"
    }

    private var activitySummary: String {
        guard data != nil else { return "正在读取健康 App 中的活动数据" }
        if completedGoalCount == 3 { return "步数、锻炼和站立都已经达标，今天更适合以恢复和维持状态为主。" }
        if stepProgress >= 1 && exerciseProgress >= 1 { return "主要活动目标基本完成，剩下更适合补站立连续性。" }
        if exerciseProgress >= 1 { return "训练已经到位，现在更值得补全天活动量和站立时长。" }
        return String(localized: "这张卡更适合先判断离目标还差多少，再决定今天是补步数、补锻炼还是打断久坐。")
    }

    private var focusText: String {
        let items: [(String, Double)] = [
            ("步数", stepProgress),
            ("锻炼", exerciseProgress),
            ("站立", standProgress)
        ]
        return items.min(by: { $0.1 < $1.1 })?.0 ?? "活动"
    }

    private var stepGapText: String { gapText(current: steps, goal: stepsGoal, unit: "步") }
    private var exerciseGapText: String { gapText(current: exercise, goal: exerciseGoal, unit: "分钟") }
    private var standGapText: String { gapText(current: standHours, goal: standGoal, unit: "小时") }

    private var bottomInsightText: String {
        if completedGoalCount == 3 {
            return String(localized: "今天适合维持，不必再刻意堆量")
        }
        if focusText == "站立" {
            return String(localized: "久坐打断仍然是今天最值得补的一环")
        }
        if focusText == "锻炼" {
            return String(localized: "补一段连续活动会比零碎走动更有效")
        }
        return "优先补足全天活动总量会更划算"
    }

    private var completionDial: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 12)
            Circle()
                .stroke(Theme.Colors.mintGreen.opacity(0.14), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            Circle()
                .trim(from: 0, to: overallProgress)
                .stroke(
                    LinearGradient(
                        colors: [Theme.Colors.mintGreen, Theme.Colors.accentBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(localizedPercentRatio(overallProgress))
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("完成度")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(width: 94, height: 94)
    }

    private func heroPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
    }

    private func heroMetric(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(reduceMotion ? MotionTokens.numberTransitionReduced : MotionTokens.numberTransition)
                    .animation(reduceMotion ? MotionTokens.numberAnimationReduced : MotionTokens.numberAnimation, value: value)
                Text(unit)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func progressRow(title: String, valueText: String, progress: Double, tint: Color, trailingText: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text(valueText)
                    .font(.appSystem(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, geometry.size.width * min(progress, 1.0)))
                }
            }
            .frame(height: 7)

            Text(trailingText)
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private func progress(value: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(1.0, max(0, Double(value) / Double(goal)))
    }

    private func gapText(current: Int, goal: Int, unit: String) -> String {
        let gap = max(0, goal - current)
        if gap == 0 {
            return String(localized: "今天这一项已经达标")
        }
        return String(localized: "距离目标还差 \(gap) \(unit)")
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct ActivitySummaryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let realtimeHealth: RealtimeHealth?

    private var measuredAtText: String? {
        guard let realtimeHealth else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(realtimeHealth.timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前状态")
                        .font(.appSystem(.headline, design: .default))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(realtimeHealth == nil ? "等待同步实时体征" : "用实时心率、HRV 与压力估计当前身体负荷")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                if let measuredAtText {
                    Text("更新于 \(measuredAtText)")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.04), in: Capsule())
                }
            }
            
            if let rt = realtimeHealth {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        statusPill(
                            title: "当前负荷",
                            value: stressHeadline(for: rt),
                            tint: stressTint(for: rt)
                        )
                        statusPill(
                            title: "心率状态",
                            value: heartRateHeadline(for: rt),
                            tint: heartRateTint(for: rt)
                        )
                    }

                    HStack(spacing: 12) {
                        compactVitalCard(
                            title: "心率",
                            value: "\(rt.bpm)",
                            unit: "bpm",
                            tint: Theme.Colors.mintGreen,
                            progress: min(max(Double(rt.bpm) / 160.0, 0), 1),
                            detail: heartRateDetail(for: rt)
                        )
                        compactVitalCard(
                            title: "HRV",
                            value: String(format: "%.0f", rt.hrv),
                            unit: "ms",
                            tint: Theme.Colors.accentBlue,
                            progress: min(max(rt.hrv / 80.0, 0), 1),
                            detail: hrvDetail(for: rt)
                        )
                        compactVitalCard(
                            title: "压力",
                            value: "\(rt.stress_value)",
                            unit: "/100",
                            tint: stressTint(for: rt),
                            progress: min(max(Double(rt.stress_value) / 100.0, 0), 1),
                            detail: stressDetail(for: rt)
                        )
                    }

                    Text(summaryText(for: rt))
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Theme.Colors.mintGreen)
                        Text("暂无健康数据")
                            .font(.appSystem(.subheadline, design: .default))
                            .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                    }

                    Text("连接健康数据后，这里会用更实时的心率、HRV 和压力状态帮助你判断今天的活动负荷是否合适。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactVitalCard(
        title: String,
        value: String,
        unit: String,
        tint: Color,
        progress: Double,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(reduceMotion ? MotionTokens.numberTransitionReduced : MotionTokens.numberTransition)
                    .animation(reduceMotion ? MotionTokens.numberAnimationReduced : MotionTokens.numberAnimation, value: value)
                Text(unit)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geometry.size.width * progress))
                }
            }
            .frame(height: 6)

            Text(detail)
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        )
    }

    private func stressHeadline(for rt: RealtimeHealth) -> String {
        let value = rt.stress_value
        if value >= 75 { return "偏高" }
        if value >= 45 { return "中等" }
        return String(localized: "平稳")
    }

    private func heartRateHeadline(for rt: RealtimeHealth) -> String {
        if rt.bpm >= 110 { return "偏快" }
        if rt.bpm <= 55 && rt.bpm > 0 { return "偏低" }
        return "正常"
    }

    private func stressTint(for rt: RealtimeHealth) -> Color {
        let value = rt.stress_value
        if value >= 75 { return Color(hex: "FF8A4C") }
        if value >= 45 { return Color(hex: "F2B94B") }
        return Theme.Colors.mintGreen
    }

    private func heartRateTint(for rt: RealtimeHealth) -> Color {
        if rt.bpm >= 110 {
            return Color(hex: "FF6B6B")
        }
        return Theme.Colors.mintGreen
    }

    private func heartRateDetail(for rt: RealtimeHealth) -> String {
        if rt.bpm >= 110 {
            return String(localized: "活动后或紧张时常见，建议结合体感一起看。")
        }
        if rt.bpm <= 55 && rt.bpm > 0 {
            return String(localized: "更接近静息状态，适合搭配 HRV 一起读。")
        }
        return String(localized: "当前节律相对平稳，可继续看整体活动表现。")
    }

    private func hrvDetail(for rt: RealtimeHealth) -> String {
        if rt.hrv >= 55 {
            return String(localized: "恢复信号较好，通常说明自主神经状态更从容。")
        }
        if rt.hrv >= 30 {
            return String(localized: "处在常见区间，更适合结合睡眠和压力一起判断。")
        }
        return String(localized: "偏低时更值得留意最近疲劳、睡眠或训练负荷。")
    }

    private func stressDetail(for rt: RealtimeHealth) -> String {
        let value = rt.stress_value
        if value >= 75 {
            return String(localized: "当前负荷偏高，适合稍微放慢节奏。")
        }
        if value >= 45 {
            return String(localized: "负荷中等，今天更适合稳住活动连续性。")
        }
        return String(localized: "状态相对平稳，适合安排轻中等活动。")
    }

    private func summaryText(for rt: RealtimeHealth) -> String {
        if rt.stress_value >= 75 {
            return String(localized: "当前更像是身体在处理较高负荷的时段，今天活动建议以舒缓步行、低强度活动为主。")
        }
        if rt.hrv >= 55 && rt.bpm < 95 {
            return String(localized: "从实时状态看，恢复和节律都比较顺，今天通常更适合完成完整活动目标。")
        }
        return String(localized: "这张卡更适合快速判断当下身体负荷，再结合上面的活动趋势一起看最近是否稳住节奏。")
    }
}

private struct ActivityDetailRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let badge: String
    let insight: String
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(badge)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.10), in: Capsule())
                }

                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Text(insight)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)

                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        )
    }
}
