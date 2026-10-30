/// DailyActionView 由健康首页与目标入口调用，作为「每日打卡」详情页。
/// 负责展示行为打卡、习惯记录、日照/呼吸/饮水快捷入口以及时间线回放入口。

import SwiftUI

/// 每日操作视图 由上级页面或路由调用，作为习惯模块里的界面或内容组件。
/// 负责展示行为打卡、日常记录与习惯分析内容。
struct DailyActionView: View {
    let openReproductiveRecord: (() -> Void)?
    let linkedActionKind: DailyWellnessActionKind?

    @State private var viewModel = HabitViewModel()
    @Bindable var periodViewModel: PeriodViewModel
    @State private var showingSunlightSheet = false
    @State private var showingBreathingMindfulness = false
    @State private var showingDrinkCheckinSheet = false
    @State private var selectedDate: Date
    @State private var showingTimelineReplay = false
    @State private var showingMicroRecoveryFlow = false
    @State private var recoveryOrchestrationPlan: DailyRecoveryOrchestrationPlan?
    @State private var selectedLongTermHabitDay: LongTermHabitDaySnapshot?
    @State private var selectedLongTermSignalKind: LongTermHabitSignalKind?
    private let calendar = Calendar.current

    @MainActor
    init(
        periodViewModel: PeriodViewModel,
        openReproductiveRecord: (() -> Void)? = nil,
        initialDate: Date = Date(),
        linkedActionKind: DailyWellnessActionKind? = nil
    ) {
        self.openReproductiveRecord = openReproductiveRecord
        self.linkedActionKind = linkedActionKind
        _periodViewModel = Bindable(wrappedValue: periodViewModel)
        self.selectedDate = Calendar.current.startOfDay(for: initialDate)
    }

    @MainActor
    init(
        openReproductiveRecord: (() -> Void)? = nil,
        initialDate: Date = Date(),
        linkedActionKind: DailyWellnessActionKind? = nil
    ) {
        self.openReproductiveRecord = openReproductiveRecord
        self.linkedActionKind = linkedActionKind
        _periodViewModel = Bindable(wrappedValue: PeriodViewModel())
        self.selectedDate = Calendar.current.startOfDay(for: initialDate)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HealthDetailPageBackground()

            dailyGoalHeroBackdrop

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    linkedGoalContextCard
                    nextStepCard
                    recentDateStrip
                    todayDataCard
                    dailyReviewToolsCard
                    recoveryOrchestrationCard
                    RecoveryActionLoopEntryLink()
                    PersonalLifeExperimentEntryLink()
                    wellnessOverviewCard
                    microRecoveryCard
                    wellnessActionsSection
                    weeklyReviewSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .healthDetailNavigation(title: HealthPageName.dailyGoal)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: handleOnAppear)
        .onChange(of: selectedDate) { _, _ in
            reloadSelectedDateData()
        }
        .onChange(of: viewModel.longTermHabitSummary.timeline30Days.map(\.id)) { _, _ in
            syncLongTermHabitSelection()
        }
        .onChange(of: viewModel.dailyWellnessSummary.todayRecord.completedActions.map(\.kind)) { _, _ in
            syncLinkedGoalProgress()
        }
        .sheet(isPresented: $showingBreathingMindfulness, onDismiss: {
            reloadSelectedDateData()
        }) {
            BreathingMindfulnessSheetView()
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingSunlightSheet, onDismiss: {
            reloadSelectedDateData()
        }) {
            SunlightSheetView(initialDate: selectedDate)
                .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingDrinkCheckinSheet, onDismiss: {
            reloadSelectedDateData()
        }) {
            DrinkCheckinSheet(viewModel: viewModel, initialPreset: .water)
                .adaptiveSheetChrome(style: .page, detents: [.large], dragIndicator: .visible)
        }
        .sheet(item: $viewModel.selectedActionDayDetail) { detail in
            FitnessCalendarDayDetailSheet(
                model: detail,
                onShareChanged: { isShared in
                    viewModel.setActionRecordShared(isShared, for: detail.date)
                },
                onSaveFitnessDetail: { draft in
                    viewModel.saveFitnessDayDetail(for: detail.date, draft: draft)
                }
            )
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingTimelineReplay) {
            NavigationStack {
                ReportDetailView(reportDate: selectedDate, initialSummary: nil)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingMicroRecoveryFlow) {
            DailyWellnessMicroRecoverySheet {
                viewModel.completeMicroRecovery()
                showingMicroRecoveryFlow = false
            }
            .adaptiveSheetChrome(style: .reading, detents: [.medium], dragIndicator: .visible)
        }
    }
}

private extension DailyActionView {
    var dailyGoalHeroColor: Color {
        Color(hex: "E4F6EF")
    }

    var dailyGoalHeroBackdrop: some View {
        VStack(spacing: 0) {
            dailyGoalHeroColor
                .frame(height: 180)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    var actionPageBackground: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }

    var nextStepCard: some View {
        HealthFeatureNextStepCard(
            focus: HealthFeatureContentPlanner.dailyAction(
                completed: completedActionCount,
                total: DailyWellnessActionKind.allCases.count,
                nextActionTitle: pendingGoalKinds.first?.definition.title
            ),
            symbol: pendingGoalKinds.isEmpty ? "checkmark.seal.fill" : "target",
            accent: Theme.Colors.mintGreen,
            action: handleHeroAction
        )
    }

    @ViewBuilder
    var linkedGoalContextCard: some View {
        if let kind = linkedActionKind {
            let definition = kind.definition
            let tint = Color(hex: definition.tintHex)
            let isCompleted = viewModel.dailyWellnessSummary.todayRecord.isCompleted(kind)

            HStack(spacing: 12) {
                Image(systemName: definition.symbol)
                    .font(.appSystem(size: 16, weight: .black))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("来自目标页 · \(definition.title)")
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(isCompleted ? "这项记录已同步到目标页。" : "完成记录后，目标进度和伙伴经验会自动同步。")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    handleWellnessActionDetailTap(kind)
                } label: {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "arrow.up.right")
                        .font(.appSystem(size: 14, weight: .black))
                        .foregroundColor(isCompleted ? .white : tint)
                        .frame(width: 38, height: 38)
                        .background(isCompleted ? Theme.Colors.mintGreen : tint.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isCompleted)
                .accessibilityLabel(isCompleted ? "目标已同步" : "打开\(definition.title)记录")
            }
            .padding(16)
            .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        }
    }

    var recentDateStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("查看日期")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(selectedDateLabel)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.mintGreen)
            }

            HStack(spacing: 8) {
                ForEach(recentDates, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 6) {
                            Text(weekdayText(date))
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            Text(dayText(date))
                                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            isSelected ? Theme.Colors.mintGreen : Color.white,
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    var todayDataCard: some View {
        let summary = viewModel.dailyWellnessSummary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(selectedDateLabel)进度")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(goalProgressSummary)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text("\(summary.todayCompletedCount)/\(DailyWellnessActionKind.allCases.count)")
                    .font(.appSystem(size: 25, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.mintGreen)
            }

            ProgressView(value: goalCompletionProgress)
                .tint(Theme.Colors.mintGreen)

            HStack(spacing: 10) {
                dataMetric(title: "目标分", value: "\(summary.todayScore)", note: "满分 100")
                dataMetric(title: "连续完成", value: "\(summary.streak)", note: "天")
                dataMetric(title: "7 天日均", value: String(format: "%.1f", weeklyAverageCompleted), note: "项/天")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(pendingGoalKinds.isEmpty ? "\(selectedDateLabel)目标已全部完成" : "待完成目标")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                if pendingGoalKinds.isEmpty {
                    Label("保持当前节奏即可，不需要额外增加负担。", systemImage: "checkmark.seal.fill")
                        .foregroundColor(Theme.Colors.mintGreen)
                } else {
                    ForEach(pendingGoalKinds.prefix(3)) { kind in
                        HStack(spacing: 10) {
                            Image(systemName: kind.definition.symbol)
                                .foregroundColor(Color(hex: kind.definition.tintHex))
                                .frame(width: 22)
                            Text(kind.definition.title)
                                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer()
                            Text(kind.definition.targetText)
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }
            }
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            .padding(14)
            .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    var recoveryOrchestrationCard: some View {
        if let plan = recoveryOrchestrationPlan,
           calendar.isDate(plan.date, inSameDayAs: selectedDate) {
            DailyRecoveryPlanCard(title: "今日编排", plan: plan)
        }
    }

    func dataMetric(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(note)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    var heroCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Label(heroDateText, systemImage: "calendar")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "455F56"))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.surface.opacity(0.72), in: Capsule())

                Spacer(minLength: 8)

                Label(actionStatusTitle, systemImage: actionStatusSymbol)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.mintGreen)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.mintGreen.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("你的每日行动")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.mintGreen)
                    Text(heroProgressTitle)
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "172B25"))
                    Text(heroSubtitle)
                        .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "4F665E"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HealthReferenceScoreRing(
                    valueText: localizedPercentRatio(goalCompletionProgress),
                    title: "今日进度",
                    progress: goalCompletionProgress,
                    accent: Theme.Colors.mintGreen,
                    animates: true
                )
            }

            VStack(spacing: 8) {
                HealthReferenceHeroFact(title: "已完成", value: "\(completedActionCount)/\(DailyWellnessActionKind.allCases.count)", symbol: "checkmark.circle.fill", accent: Theme.Colors.mintGreen)
                HealthReferenceHeroFact(title: "连续记录", value: String(localized: "\(viewModel.longTermHabitSummary.currentStreak) 天"), symbol: "flame.fill", accent: Theme.Colors.mintGreen)
                HealthReferenceHeroFact(title: "30 天完成率", value: percentText(viewModel.longTermHabitSummary.completionRate30Days), symbol: "chart.line.uptrend.xyaxis", accent: Theme.Colors.mintGreen)
            }

            Button(action: handleHeroAction) {
                HStack(spacing: 8) {
                    Image(systemName: heroActionSymbol)
                        .font(.appSystem(size: 15, weight: .black))
                    Text(heroActionTitle)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(hex: "168A67"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [dailyGoalHeroColor, Color.white.opacity(0.74)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 36,
                bottomTrailingRadius: 36,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -18)
        .padding(.top, -16)
    }

    var goalHeroSpeechBubble: some View {
        Text(heroBubbleTitle)
            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "50675F"))
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .offset(y: 5)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.bottom, 8)
    }

    var dailyReviewToolsCard: some View {
        VStack(spacing: 0) {
            Button {
                showingTimelineReplay = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "timeline.selection")
                        .font(.appSystem(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "3A79F8"))
                        .frame(width: 44, height: 44)
                        .background(Color(hex: "EAF4FF"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("回看\(selectedDateLabel)的行为时间线")
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("查看咖啡因、情绪、睡眠和压力的关联。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "8EA2BA"))
                }
                .padding(.bottom, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(Theme.Colors.surfaceBorder)

            Toggle(isOn: Binding(
                get: { viewModel.selectedActionRecord?.isShared ?? false },
                set: { viewModel.setSelectedDayShared($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("共享这一天的养成记录")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("好友只会看到长期养成摘要，不包含原始点击流水。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 14)
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    var wellnessOverviewCard: some View {
        let summary = viewModel.dailyWellnessSummary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "E9FFF4"))
                        .frame(width: 62, height: 62)
                    Image(systemName: "leaf.circle.fill")
                        .font(.appSystem(size: 30, weight: .black))
                        .foregroundColor(Theme.Colors.mintGreen)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("今日目标 · \(summary.levelTitle)")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(summary.levelDetail)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(summary.todayScore)")
                        .font(.appSystem(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.mintGreen)
                    Text("目标分")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            HStack(spacing: 10) {
                heroMetric(title: "今日完成", value: "\(summary.todayCompletedCount)/5", note: "轻动作")
                heroMetric(title: "连续", value: "\(summary.streak)", note: "天")
                heroMetric(title: "周完成", value: "\(Int((summary.weeklyCompletionRate * 100).rounded()))%", note: "7 天")
            }

            Toggle(isOn: Binding(
                get: { viewModel.wellnessReminderEnabled },
                set: { viewModel.toggleWellnessReminder($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每日目标提醒")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(viewModel.wellnessReminderEnabled ? "每天 \(viewModel.wellnessReminderTimeText) 提醒收一个轻动作" : "开启后每天 20:30 轻提醒一次")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Colors.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(20)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    var microRecoveryCard: some View {
        Button {
            showingMicroRecoveryFlow = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "EFFFF8"), Color(hex: "EEF5FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles")
                        .font(.appSystem(size: 22, weight: .black))
                        .foregroundColor(Theme.Colors.mintGreen)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 6) {
                    Text("3 分钟微恢复流程")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("呼吸 1 分钟、起身 1 分钟、补水或日照 1 分钟。低门槛，但真的能把身体拉回来一点。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("开始")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.Colors.mintGreen, in: Capsule())
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), Color(hex: "EFFFF8").opacity(0.74)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    var wellnessActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(
                title: "目标动作",
                subtitle: "每项都可以低门槛完成，先做一点也算数。"
            )

            ForEach(Array(viewModel.wellnessActionCards.enumerated()), id: \.element.id) { index, card in
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: card.tintHex).opacity(0.18), Color(hex: card.tintHex).opacity(0.07)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Image(systemName: card.symbol)
                                    .font(.appSystem(size: 18, weight: .bold))
                                    .foregroundColor(Color(hex: card.tintHex))
                            }
                            .frame(width: 56, height: 56)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 10) {
                                    Text(card.title)
                                        .font(.appSystem(size: 19, weight: .black, design: .rounded))
                                        .foregroundColor(Theme.Colors.textPrimary)

                                    Spacer(minLength: 10)

                                    statusBadge(for: card)
                                }

                                Text(card.subtitle)
                                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(card.isCompleted ? card.sourceText : card.detailText)
                                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(card.isCompleted ? Theme.Colors.mintGreen : Theme.Colors.textTertiary)
                            }
                        }

                        HStack(spacing: 12) {
                            infoPill(title: "当前进度", value: card.progressText, tint: Color(hex: card.tintHex))
                            infoPill(title: "目标", value: card.targetText, tint: Color(hex: card.tintHex).opacity(0.82))
                        }

                        HStack(spacing: 10) {
                            Button {
                                viewModel.completeWellnessAction(card.kind)
                            } label: {
                                Text(card.isCompleted ? "已完成" : card.quickCompleteText)
                                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: card.tintHex), Color(hex: card.tintHex).opacity(0.72)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(card.isCompleted)

                            Button {
                                handleWellnessActionDetailTap(card.kind)
                            } label: {
                                Text("查看")
                                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: card.tintHex))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(Color(hex: card.tintHex).opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color(hex: card.tintHex).opacity(card.isCompleted ? 0.14 : 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if card.isCompleted {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.appSystem(size: 22, weight: .bold))
                                .foregroundColor(Theme.Colors.mintGreen.opacity(0.72))
                                .padding(16)
                        }
                    }
                    .shadow(color: Color(hex: card.tintHex).opacity(card.isCompleted ? 0.12 : 0.08), radius: 18, x: 0, y: 12)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    var weeklyReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(title: "最近 7 天轻复盘", subtitle: viewModel.dailyWellnessSummary.reviewText)

            HStack(spacing: 8) {
                ForEach(viewModel.dailyWellnessSummary.weeklyDays) { day in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(day.score >= 100 ? Theme.Colors.mintGreen : Color(hex: "DDE8F2"))
                                .frame(height: 46)
                            Text("\(day.score)")
                                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(day.score >= 100 ? .white : Theme.Colors.textSecondary)
                        }
                        Text(ChineseDateText.compactMonthDay(day.date))
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            longTermHabitCard
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    var longTermHabitCard: some View {
        let summary = viewModel.longTermHabitSummary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: summary.trend.tintHex).opacity(0.18), Color(hex: "EFFFF8").opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.appSystem(size: 23, weight: .black))
                        .foregroundColor(Color(hex: summary.trend.tintHex))
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("目标趋势 · \(summary.phaseTitle)")
                            .font(.appSystem(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(summary.trend.title)
                            .font(.appSystem(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: summary.trend.tintHex))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(hex: summary.trend.tintHex).opacity(0.12), in: Capsule())
                    }

                    Text(summary.phaseDetail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(summary.score)")
                        .font(.appSystem(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: summary.trend.tintHex))
                    Text("长期成长分")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            HStack(spacing: 10) {
                heroMetric(title: "连续", value: "\(summary.currentStreak)", note: "天")
                heroMetric(title: "最长", value: "\(summary.longestStreak)", note: "天")
                heroMetric(title: "30天", value: percentText(summary.completionRate30Days), note: "完成率")
            }

            longTermScoreSourceCard(summary)

            longTermFourWeekRhythm(summary.timeline30Days)

            longTermTimeline(summary.timeline30Days)

            longTermSelectedDayCard(summary)

            longTermSignalRanking(summary.signals)

            HStack(spacing: 10) {
                longTermSignalBlock(title: "最稳习惯", signal: summary.strongestHabit, emptyText: "等待形成")
                longTermSignalBlock(title: "待巩固", signal: summary.focusHabit, emptyText: "暂时均衡")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("本周建议")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(summary.suggestionText)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("90 天有 \(summary.recordedDays90) 天留下记录 · 完成挑战 \(summary.completedChallengeCount) 个 · 90天完成率 \(percentText(summary.completionRate90Days))")
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    func longTermTimeline(_ days: [LongTermHabitDaySnapshot]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 15)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("30 天养成热力图")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer(minLength: 8)

                Text("点击日期查看详情")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "6A7F98"))
            }

            if days.isEmpty {
                Text("先完成一个轻动作，长期成长分会从这里开始积累。")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(days) { day in
                        let isSelected = isSelectedLongTermDay(day)
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                selectedLongTermHabitDay = day
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(longTermTimelineColor(for: day))
                                .frame(height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(isSelected ? Color(hex: "15325D") : Color.clear, lineWidth: 2)
                                )
                                .shadow(color: isSelected ? Color(hex: "15325D").opacity(0.18) : .clear, radius: 8, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ChineseDateText.compactMonthDay(day.date)) \(longTermDayStatusText(day))")
                    }
                }

                HStack(spacing: 10) {
                    longTermHeatLegend(title: "无记录", color: Color(hex: "DDE8F2"))
                    longTermHeatLegend(title: "轻量", color: Color(hex: "B8D9CE"))
                    longTermHeatLegend(title: "稳定", color: Color(hex: "7AB7A8"))
                    longTermHeatLegend(title: "高完成", color: Theme.Colors.mintGreen)
                }

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectAdjacentLongTermDay(in: days, step: -1)
                        }
                    } label: {
                        longTermStepButtonLabel(systemImage: "chevron.left", text: "前一天")
                    }
                    .buttonStyle(.plain)

                    Text(effectiveSelectedLongTermHabitDay(viewModel.longTermHabitSummary).map { ChineseDateText.compactMonthDay($0.date) } ?? "今天")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectAdjacentLongTermDay(in: days, step: 1)
                        }
                    } label: {
                        longTermStepButtonLabel(systemImage: "chevron.right", text: "后一天")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func longTermSelectedDayCard(_ summary: LongTermHabitSummary) -> some View {
        let day = effectiveSelectedLongTermHabitDay(summary)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: summary.trend.tintHex).opacity(0.13))
                Image(systemName: day?.hasAnyRecord == true ? "checkmark.seal.fill" : "plus.circle.fill")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(Color(hex: summary.trend.tintHex))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text(day.map { "\(ChineseDateText.compactMonthDay($0.date)) · \(longTermDayStatusText($0))" } ?? "等待第一条养成记录")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(day.map(longTermDayDetailText) ?? "先完成一个轻动作，长期成长分会从这里开始积累。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let day {
                    HStack(spacing: 8) {
                        longTermTinyMetric(title: "完成信号", value: "\(day.completedSignals)/\(LongTermHabitSignalKind.allCases.count)")
                        longTermTinyMetric(title: "完成强度", value: longTermDayStrengthText(day))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func longTermSignalRanking(_ signals: [LongTermHabitSignal]) -> some View {
        let sortedSignals = signals.sorted {
            if $0.completionRate == $1.completionRate {
                return $0.completedDays > $1.completedDays
            }
            return $0.completionRate > $1.completionRate
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("习惯信号完成率")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            if sortedSignals.isEmpty {
                Text("先完成一个轻动作，长期成长分会从这里开始积累。")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedSignals) { signal in
                        longTermSignalRankingRow(signal)
                    }
                }

                if let selected = effectiveSelectedLongTermSignal(signals) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected.symbol)
                            .font(.appSystem(size: 15, weight: .bold))
                            .foregroundColor(Color(hex: selected.tintHex))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: selected.tintHex).opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(selected.title) · 90 天完成 \(selected.completedDays) 天")
                                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("完成率 \(percentText(selected.completionRate)) · 缺口 \(max(0, selected.observedDays - selected.completedDays)) 天")
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: selected.tintHex))
                            Text(selected.detailText)
                                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Theme.Colors.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func longTermSignalRankingRow(_ signal: LongTermHabitSignal) -> some View {
        let isSelected = selectedLongTermSignalKind == signal.kind
        let tint = Color(hex: signal.tintHex)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedLongTermSignalKind = signal.kind
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: signal.symbol)
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(signal.title)
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Spacer(minLength: 8)

                        Text(percentText(signal.completionRate))
                            .font(.appSystem(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(tint)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(hex: "DFE8EF"))
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * CGFloat(min(1, max(0, signal.completionRate))))
                        }
                    }
                    .frame(height: 7)

                    Text("90 天 \(signal.completedDays)/\(signal.observedDays) 天")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .padding(10)
            .background(isSelected ? tint.opacity(0.12) : Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.38) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func longTermScoreSourceCard(_ summary: LongTermHabitSummary) -> some View {
        let completionScore = summary.completionRate30Days * 70
        let streakScore = min(Double(summary.currentStreak), 14) / 14 * 20
        let challengeScore = min(Double(summary.completedChallengeCount), 2) / 2 * 10
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("长期成长分拆解")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer(minLength: 8)

                Text("\(summary.score)/100")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: summary.trend.tintHex))
            }

            HStack(spacing: 8) {
                scoreSourcePill(title: "30天完成", value: percentText(summary.completionRate30Days), tint: Color(hex: summary.trend.tintHex))
                scoreSourcePill(title: "连续天数", value: "\(summary.currentStreak)天", tint: Theme.Colors.mintGreen)
                scoreSourcePill(title: "恢复挑战", value: "\(summary.completedChallengeCount)个", tint: Color(hex: "69B8F0"))
            }

            VStack(spacing: 8) {
                longTermScoreBar(title: "30 天完成率", value: completionScore, maxValue: 70, tint: Color(hex: summary.trend.tintHex))
                longTermScoreBar(title: "连续性加成", value: streakScore, maxValue: 20, tint: Theme.Colors.mintGreen)
                longTermScoreBar(title: "恢复挑战加成", value: challengeScore, maxValue: 10, tint: Color(hex: "69B8F0"))
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.60), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func longTermScoreBar(title: String, value: Double, maxValue: Double, tint: Color) -> some View {
        let progress = maxValue > 0 ? min(1, max(0, value / maxValue)) : 0
        return HStack(spacing: 10) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 82, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "DFE8EF"))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(progress))
                }
            }
            .frame(height: 8)

            Text("\(Int(value.rounded()))/\(Int(maxValue))")
                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                .foregroundColor(tint)
                .frame(width: 42, alignment: .trailing)
        }
    }

    func longTermFourWeekRhythm(_ days: [LongTermHabitDaySnapshot]) -> some View {
        let weeks = longTermWeekBuckets(days)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("四周节奏概览")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer(minLength: 8)

                Text("看最近 28 天稳定性")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "6A7F98"))
            }

            if weeks.isEmpty {
                Text("先完成一个轻动作，长期成长分会从这里开始积累。")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        VStack(spacing: 7) {
                            GeometryReader { proxy in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(hex: "DFE8EF"))
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(longTermWeekColor(rate: week.rate))
                                        .frame(height: max(8, proxy.size.height * CGFloat(week.rate)))
                                }
                            }
                            .frame(height: 58)

                            Text("第\(index + 1)周")
                                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)

                            Text(percentText(week.rate))
                                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(longTermWeekColor(rate: week.rate))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                Text(longTermWeekInsightText(weeks))
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func scoreSourcePill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func longTermHeatLegend(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func longTermStepButtonLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.appSystem(size: 10, weight: .black))
            Text(text)
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
        }
        .foregroundColor(Color(hex: "45627D"))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func longTermTinyMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface.opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func longTermSignalBlock(title: String, signal: LongTermHabitSignal?, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: signal?.tintHex ?? "94A3C3").opacity(0.13))
                    Image(systemName: signal?.symbol ?? "circle.dashed")
                        .font(.appSystem(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: signal?.tintHex ?? "94A3C3"))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(signal?.title ?? emptyText)
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(signal.map { percentText($0.completionRate) } ?? "0%")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 24, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    func heroMetric(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(note)
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Theme.Colors.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func statusBadge(for card: DailyWellnessActionCardModel) -> some View {
        Text(card.isCompleted ? "已完成" : "可一键完成")
            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(card.isCompleted ? Theme.Colors.mintGreen : Color(hex: card.tintHex))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((card.isCompleted ? Theme.Colors.mintGreen : Color(hex: card.tintHex)).opacity(0.12), in: Capsule())
    }

    func infoPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func longTermTimelineColor(for day: LongTermHabitDaySnapshot) -> Color {
        guard day.hasAnyRecord else { return Color(hex: "DDE8F2") }
        switch day.completedSignals {
        case 4...:
            return Theme.Colors.mintGreen
        case 2...3:
            return Color(hex: "7AB7A8")
        default:
            return Color(hex: "B8D9CE")
        }
    }

    func longTermWeekColor(rate: Double) -> Color {
        switch rate {
        case 0.75...:
            return Theme.Colors.mintGreen
        case 0.45..<0.75:
            return Color(hex: "7AB7A8")
        case 0.15..<0.45:
            return Color(hex: "F4A259")
        default:
            return Color(hex: "94A3C3")
        }
    }

    func isSelectedLongTermDay(_ day: LongTermHabitDaySnapshot) -> Bool {
        guard let selected = effectiveSelectedLongTermHabitDay(viewModel.longTermHabitSummary) else { return false }
        return calendar.isDate(selected.date, inSameDayAs: day.date)
    }

    func effectiveSelectedLongTermHabitDay(_ summary: LongTermHabitSummary) -> LongTermHabitDaySnapshot? {
        if let selectedLongTermHabitDay,
           let currentSnapshot = summary.timeline30Days.first(where: { calendar.isDate($0.date, inSameDayAs: selectedLongTermHabitDay.date) }) {
            return currentSnapshot
        }
        return summary.timeline30Days.last(where: \.hasAnyRecord) ?? summary.timeline30Days.last
    }

    func effectiveSelectedLongTermSignal(_ signals: [LongTermHabitSignal]) -> LongTermHabitSignal? {
        if let selectedLongTermSignalKind,
           let selected = signals.first(where: { $0.kind == selectedLongTermSignalKind }) {
            return selected
        }
        return signals.max {
            if $0.completionRate == $1.completionRate {
                return $0.completedDays < $1.completedDays
            }
            return $0.completionRate < $1.completionRate
        }
    }

    func selectAdjacentLongTermDay(in days: [LongTermHabitDaySnapshot], step: Int) {
        guard !days.isEmpty else { return }
        let current = effectiveSelectedLongTermHabitDay(viewModel.longTermHabitSummary)
        let currentIndex = current.flatMap { currentDay in
            days.firstIndex { calendar.isDate($0.date, inSameDayAs: currentDay.date) }
        } ?? (step > 0 ? -1 : days.count)
        let nextIndex = min(max(currentIndex + step, 0), days.count - 1)
        selectedLongTermHabitDay = days[nextIndex]
    }

    func syncLongTermHabitSelection() {
        let summary = viewModel.longTermHabitSummary
        selectedLongTermHabitDay = effectiveSelectedLongTermHabitDay(summary)
        selectedLongTermSignalKind = effectiveSelectedLongTermSignal(summary.signals)?.kind
    }

    func longTermDayStatusText(_ day: LongTermHabitDaySnapshot) -> String {
        guard day.hasAnyRecord else { return "暂无养成记录" }
        switch day.completedSignals {
        case 4...:
            return String(localized: "高完成度")
        case 2...3:
            return String(localized: "稳定推进")
        default:
            return String(localized: "轻量完成")
        }
    }

    func longTermDayDetailText(_ day: LongTermHabitDaySnapshot) -> String {
        guard day.hasAnyRecord else {
            return String(localized: "这一天还没有形成养成信号，补一个轻动作就能让长期成长分开始连续。")
        }
        return String(localized: "这一天完成了 \(day.completedSignals) 个长期信号，已计入 30 天热力图、连续天数和长期成长分。")
    }

    func longTermDayStrengthText(_ day: LongTermHabitDaySnapshot) -> String {
        guard day.hasAnyRecord else { return "待记录" }
        let total = max(LongTermHabitSignalKind.allCases.count, 1)
        let rate = Double(day.completedSignals) / Double(total)
        switch rate {
        case 0.67...:
            return String(localized: "高")
        case 0.34..<0.67:
            return String(localized: "中")
        default:
            return String(localized: "轻")
        }
    }

    func longTermWeekBuckets(_ days: [LongTermHabitDaySnapshot]) -> [(completed: Int, total: Int, rate: Double)] {
        let recent = Array(days.suffix(28))
        guard !recent.isEmpty else { return [] }
        return stride(from: 0, to: recent.count, by: 7).map { start in
            let chunk = Array(recent[start..<min(start + 7, recent.count)])
            let completed = chunk.filter(\.hasAnyRecord).count
            let total = max(chunk.count, 1)
            return (completed, total, Double(completed) / Double(total))
        }
    }

    func longTermWeekInsightText(_ weeks: [(completed: Int, total: Int, rate: Double)]) -> String {
        guard let first = weeks.first, let last = weeks.last else {
            return String(localized: "先完成一个轻动作，长期成长分会从这里开始积累。")
        }
        if last.rate >= 0.75 {
            return String(localized: "最近一周 \(last.completed)/\(last.total) 天有记录，节奏已经很稳，适合开始补强低完成率信号。")
        }
        if last.rate > first.rate {
            return String(localized: "最近一周比四周前更稳定，继续保住最容易完成的动作，成长分会更快上来。")
        }
        if last.rate < first.rate {
            return String(localized: "最近一周略有回落，先把一个低负担动作接回来，不需要一次补满。")
        }
        return String(localized: "四周节奏比较平稳，下一步看信号排行里最薄弱的一项。")
    }

    func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    var completedActionCount: Int {
        viewModel.dailyWellnessSummary.todayCompletedCount
    }

    var recentDates: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: today)
        }
    }

    var pendingGoalKinds: [DailyWellnessActionKind] {
        DailyWellnessActionKind.allCases.filter {
            !viewModel.dailyWellnessSummary.todayRecord.isCompleted($0)
        }
    }

    var goalCompletionProgress: Double {
        Double(viewModel.dailyWellnessSummary.todayCompletedCount) / Double(max(DailyWellnessActionKind.allCases.count, 1))
    }

    var weeklyAverageCompleted: Double {
        let days = viewModel.dailyWellnessSummary.weeklyDays
        guard !days.isEmpty else { return 0 }
        return Double(days.reduce(0) { $0 + $1.completedCount }) / Double(days.count)
    }

    var goalProgressSummary: String {
        let completed = viewModel.dailyWellnessSummary.todayCompletedCount
        if completed == DailyWellnessActionKind.allCases.count {
            return String(localized: "五项目标都已完成，这一天的基础恢复动作已经收齐。")
        }
        if completed == 0 {
            return String(localized: "还没有完成目标，从最容易的一项开始即可。")
        }
        return String(localized: "已完成 \(completed) 项，还有 \(pendingGoalKinds.count) 项可以继续推进。")
    }

    func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    func dayText(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    var selectedDateLabel: String {
        calendar.isDateInToday(selectedDate)
            ? String(localized: "今天")
            : ChineseDateText.compactMonthDay(selectedDate)
    }

    var heroSubtitle: String {
        if viewModel.wellnessActionCards.isEmpty {
            return String(localized: "先完成一个轻动作，长期成长分会从这里开始积累。")
        }
        if calendar.isDateInToday(selectedDate) {
            return String(localized: "用低负担动作换取连续性，让补水、日照、呼吸和起身慢慢长成习惯。")
        }
        return String(localized: "这是 \(selectedDateLabel) 的长期养成记录，方便回看当时的节奏。")
    }

    var heroDateText: String {
        selectedDate.formatted(
            .dateTime
                .locale(Locale.autoupdatingCurrent)
                .month()
                .day()
                .weekday(.wide)
        )
    }

    var heroProgressTitle: String {
        let total = DailyWellnessActionKind.allCases.count
        if completedActionCount >= total {
            return String(localized: "\(selectedDateLabel)的目标都完成了")
        }
        if completedActionCount == 0 {
            return calendar.isDateInToday(selectedDate)
                ? String(localized: "从一个小目标开始")
                : String(localized: "\(selectedDateLabel)还没有完成记录")
        }
        return String(localized: "\(selectedDateLabel)已完成 \(completedActionCount) 项")
    }

    var heroBubbleTitle: String {
        if completedActionCount >= DailyWellnessActionKind.allCases.count {
            return calendar.isDateInToday(selectedDate)
                ? String(localized: "今天收得很完整")
                : String(localized: "这一天收得很完整")
        }
        if let nextGoal = pendingGoalKinds.first {
            return String(localized: "下一项 · \(nextGoal.definition.title)")
        }
        return String(localized: "保持现在的节奏")
    }

    var heroActionTitle: String {
        pendingGoalKinds.isEmpty
            ? String(localized: "回看这天节奏")
            : String(localized: "开始下一项目标")
    }

    var heroActionSymbol: String {
        pendingGoalKinds.isEmpty ? "timeline.selection" : "arrow.right"
    }

    var actionStatusTitle: String {
        completedActionCount >= DailyWellnessActionKind.allCases.count
            ? String(localized: "今日已完成")
            : String(localized: "今日进行中")
    }

    var actionStatusSymbol: String {
        completedActionCount >= DailyWellnessActionKind.allCases.count ? "checkmark.seal.fill" : "figure.walk.motion"
    }

    func handleHeroAction() {
        if let nextGoal = pendingGoalKinds.first {
            handleWellnessActionDetailTap(nextGoal)
        } else {
            showingTimelineReplay = true
        }
    }

    func handleOnAppear() {
        reloadSelectedDateData()
        periodViewModel.reload()
        syncLongTermHabitSelection()
    }

    func reloadSelectedDateData() {
        viewModel.loadData(for: selectedDate)
        recoveryOrchestrationPlan = DailyRecoveryOrchestrationStore.shared.load(for: selectedDate, calendar: calendar)
        syncLongTermHabitSelection()
    }

    func syncLinkedGoalProgress() {
        _ = GoalsStore.shared.syncLinkedGoalRewards(
            on: selectedDate,
            wellnessRecord: viewModel.dailyWellnessSummary.todayRecord
        )
    }

    func handleDailyActionTap(_ destination: HabitDailyActionDestination) {
        switch destination {
        case .water:
            showingDrinkCheckinSheet = true
        case .sunlight:
            showingSunlightSheet = true
        case .mindfulness:
            showingBreathingMindfulness = true
        case .stand:
            if let todayCard = viewModel.fitnessCalendarModel.days.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
                viewModel.selectActionDay(todayCard)
            }
        }
    }

    func handleWellnessActionDetailTap(_ kind: DailyWellnessActionKind) {
        switch kind {
        case .water:
            showingDrinkCheckinSheet = true
        case .sunlight:
            showingSunlightSheet = true
        case .breathing:
            showingBreathingMindfulness = true
        case .move:
            if let selectedDay = viewModel.fitnessCalendarModel.days.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
                viewModel.selectActionDay(selectedDay)
            } else {
                viewModel.completeWellnessAction(.move)
            }
        case .bedtimeWindDown:
            viewModel.completeWellnessAction(.bedtimeWindDown)
        }
    }
}

private struct DailyWellnessMicroRecoverySheet: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Capsule()
                .fill(Color(hex: "D7E8E0"))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("3 分钟微恢复")
                    .font(.appSystem(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("不用做得完美，只要给身体一个很小的回弹窗口。完成后会计入呼吸、起身，以及补水或日照。")
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                recoveryStep(number: "1", title: "呼吸 1 分钟", detail: "慢慢吸气、呼气，肩膀放下来。", symbol: "wind", tint: Color(hex: "7AB7A8"))
                recoveryStep(number: "2", title: "起身 1 分钟", detail: "站起来走一圈，或者轻轻伸展。", symbol: "figure.walk", tint: Color(hex: "69B8F0"))
                recoveryStep(number: "3", title: "补一点能量", detail: "喝一杯水；如果还早，也可以去窗边晒一会。", symbol: "drop.fill", tint: Color(hex: "32ADE6"))
            }

            Button(action: onComplete) {
                Text("完成 3 分钟微恢复")
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Theme.Colors.mintGreen, Color(hex: "63B7F0")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(hex: "FCFEFF"), Color(hex: "EFFFF8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func recoveryStep(number: String, title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Image(systemName: symbol)
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
