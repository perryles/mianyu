/// RehabilitationPlanView 展示康复训练任务列表与进度。
///
/// 功能：
/// - 按周期编排训练任务
/// - 每个任务可设定时长、频率与提醒规则
/// - 支持多任务编排与进度跟踪
/// - 今日任务快速打卡
/// - 历史记录时间线

import SwiftUI

struct RehabilitationPlanView: View {
    @State private var selectedDate: Date = Date()
    @State private var refreshToken = UUID()
    @State private var showTaskEdit: Bool = false
    @State private var editingTask: CareTask?

    private var activeTasks: [CareTask] {
        CareTaskEngine.shared.tasks(category: .rehabilitation, referenceDate: selectedDate)
    }

    private var todayEvents: [CareTaskEvent] {
        CareTaskEngine.shared.events(category: .rehabilitation, on: selectedDate, referenceDate: selectedDate)
    }

    private var completedToday: Int { todayEvents.filter { $0.status == .completed }.count }
    private var totalToday: Int { todayEvents.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                progressOverviewCard
                activeChallengeSection
                todayTasksSection
                activePlansSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "康复训练"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingTask = nil
                    showTaskEdit = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.Colors.mintGreen)
                }
            }
        }
        .sheet(isPresented: $showTaskEdit) {
            CareTaskEditView(
                task: editingTask,
                presetCategory: .rehabilitation,
                presetLinkedModule: nil
            ) { task in
                CareTaskEngine.shared.saveTask(task)
                refreshToken = UUID()
            }
        }
        .id(refreshToken)
        .onReceive(NotificationCenter.default.publisher(for: .careTasksDidChange)) { _ in
            refreshToken = UUID()
        }
    }

    // MARK: - 进度概览

    @ViewBuilder
    private var progressOverviewCard: some View {
        let rate = totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
        BBTitledCard(
            title: String(localized: "今日进度"),
            subtitle: "\(completedToday)/\(totalToday) \(String(localized: "已完成"))",
            systemImage: "figure.cooldown",
            tint: .blue
        ) {
            VStack(spacing: 10) {
                ProgressView(value: rate)
                    .tint(.blue)
                    .frame(height: 8)

                if totalToday == 0 {
                    Text(String(localized: "今天没有安排训练任务"))
                        .font(.appSystem(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                } else if completedToday == totalToday {
                    Label(String(localized: "今日训练全部完成"), systemImage: "checkmark.seal.fill")
                        .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - 进行中挑战桥接

    /// 活跃康复挑战区块。
    /// 把 RecoveryChallengeStore 的活跃 7 天挑战展示在康复页面，与 CareTaskEngine 自管的训练任务并列。
    @ViewBuilder
    private var activeChallengeSection: some View {
        if let summary = CareChallengeBridge.shared.activeChallengeSummary {
            BBTitledCard(
                title: String(localized: "进行中的康复挑战"),
                subtitle: summary.dayText,
                systemImage: "flame.fill",
                tint: .orange
            ) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title)
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(summary.dayText)
                            .font(.appSystem(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    ProgressView(value: summary.progress)
                        .tint(.orange)
                        .frame(width: 60, height: 6)
                }
            }
        }
    }

    // MARK: - 今日任务

    @ViewBuilder
    private var todayTasksSection: some View {
        if !todayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "今日任务"))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(todayEvents) { event in
                    CareTaskCardView(
                        event: event,
                        onQuickComplete: {
                            CareTaskEngine.shared.quickComplete(event: event)
                            refreshToken = UUID()
                        },
                        onSkip: {
                            let outcome = CareOutcome(
                                logicalTaskID: event.logicalTaskID,
                                taskID: event.taskID,
                                taskRevision: event.taskRevision,
                                category: .rehabilitation,
                                completedAt: Date(),
                                scheduledDate: Calendar.current.startOfDay(for: event.scheduledAt),
                                values: [],
                                note: String(localized: "用户跳过")
                            )
                            CareTaskEngine.shared.recordOutcome(outcome)
                            refreshToken = UUID()
                        }
                    )
                }
            }
        }
    }

    // MARK: - 进行中计划

    @ViewBuilder
    private var activePlansSection: some View {
        if !activeTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "训练计划"))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(activeTasks) { task in
                    planRow(task)
                }
            }
        } else {
            BBTitledCard(
                title: String(localized: "还没有训练计划"),
                subtitle: String(localized: "点击右上角添加训练任务"),
                systemImage: "plus.circle",
                tint: .blue
            ) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func planRow(_ task: CareTask) -> some View {
        BBCard(style: .standard, tint: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: task.icon)
                        .font(.appSystem(size: 18))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        if let subtitle = task.subtitle {
                            Text(subtitle)
                                .font(.appSystem(size: 12, weight: .medium))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text("v\(task.revision)")
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                scheduleSummary(task.schedule)

                if let target = task.targetValue, let unit = task.unit {
                    Text("\(String(localized: "目标")): \(formattedNumber(target)) \(unit)")
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }

                if let instructions = task.instructions {
                    Text(instructions)
                        .font(.appSystem(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingTask = task
            showTaskEdit = true
        }
    }

    @ViewBuilder
    private func scheduleSummary(_ schedule: CareSchedule) -> some View {
        let times = schedule.slots.map(\.formattedTime).joined(separator: " ")
        let freqText = switch schedule.frequency {
        case .daily: schedule.weekdays.isEmpty ? String(localized: "每天") : formatWeekdays(schedule.weekdays)
        case .weekly: formatWeekdays(schedule.weekdays)
        case .customInterval: String(localized: "每\(schedule.customIntervalDays)天")
        }
        Text("\(freqText) · \(times)")
            .font(.appSystem(size: 12, weight: .medium))
            .foregroundColor(Theme.Colors.textTertiary)
    }

    private func formatWeekdays(_ days: Set<Int>) -> String {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let sorted = days.sorted()
        if sorted.isEmpty { return String(localized: "每天") }
        return "周" + sorted.compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: "周")
    }

    private func formattedNumber(_ value: Double) -> String {
        if floor(value) == value { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
}
