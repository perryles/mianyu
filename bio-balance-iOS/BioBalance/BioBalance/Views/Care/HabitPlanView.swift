/// HabitPlanView 展示健康习惯任务列表。
///
/// 支持：
/// - "每天晒太阳20分钟"
/// - "睡前呼吸训练"
/// - "每晚23点前入睡"
/// 等自定义重复规则与打卡记录。
///
/// 晒太阳任务与 App 内现有的光照模块打通：
/// - 数据共享：读取 AppGroupManager.getSunlightMinutesToday()
/// - UI 联动：点击卡片跳转到 SunlightSheetView

import SwiftUI

struct HabitPlanView: View {
    @State private var selectedDate: Date = Date()
    @State private var refreshToken = UUID()
    @State private var showTaskEdit: Bool = false
    @State private var editingTask: CareTask?
    @State private var showSunlightSheet: Bool = false

    private var activeTasks: [CareTask] {
        CareTaskEngine.shared.tasks(category: .habit, referenceDate: selectedDate)
    }

    private var todayEvents: [CareTaskEvent] {
        CareTaskEngine.shared.events(category: .habit, on: selectedDate, referenceDate: selectedDate)
    }

    private var sunlightMinutes: Int {
        AppGroupManager.shared.getSunlightMinutesToday() ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sunlightBridgeCard
                todayHabitsSection
                activePlansSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "健康习惯"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingTask = nil
                        showTaskEdit = true
                    } label: {
                        Label(String(localized: "自定义习惯"), systemImage: "plus.circle")
                    }
                    Button {
                        editingTask = nil
                        showTaskEdit = true
                    } label: {
                        Label(String(localized: "晒太阳任务"), systemImage: "sun.max.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.Colors.mintGreen)
                }
            }
        }
        .sheet(isPresented: $showTaskEdit) {
            CareTaskEditView(
                task: editingTask,
                presetCategory: .habit
            ) { task in
                CareTaskEngine.shared.saveTask(task)
                refreshToken = UUID()
            }
        }
        .sheet(isPresented: $showSunlightSheet) {
            SunlightSheetView()
        }
        .id(refreshToken)
        .onReceive(NotificationCenter.default.publisher(for: .careTasksDidChange)) { _ in
            refreshToken = UUID()
        }
    }

    // MARK: - 日照桥接卡片

    @ViewBuilder
    private var sunlightBridgeCard: some View {
        let goal = AppGroupManager.shared.getSunlightGoalMinutes() ?? 20
        let rate = goal > 0 ? min(1.0, Double(sunlightMinutes) / Double(goal)) : 0

        BBTitledCard(
            title: String(localized: "今日日照"),
            subtitle: "\(sunlightMinutes) / \(goal) \(String(localized: "分钟"))",
            systemImage: "sun.max.fill",
            tint: .green
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.02, rate)))
                        .stroke(.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text("\(Int(rate * 100))%")
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rate >= 1.0 ? String(localized: "日照目标已完成") : String(localized: "还需 \(max(0, goal - sunlightMinutes)) 分钟"))
                            .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(String(localized: "数据来自健康 App 户外时长"))
                            .font(.appSystem(size: 11, weight: .medium))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showSunlightSheet = true
        }
    }

    // MARK: - 今日习惯

    @ViewBuilder
    private var todayHabitsSection: some View {
        if !todayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "今日习惯"))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(todayEvents) { event in
                    CareTaskCardView(
                        event: event,
                        onQuickComplete: {
                            if event.linkedModule == "sunlight" {
                                // 晒太阳任务跳转到详情页
                                showSunlightSheet = true
                            } else {
                                CareTaskEngine.shared.quickComplete(event: event)
                                refreshToken = UUID()
                            }
                        },
                        onSkip: {
                            let outcome = CareOutcome(
                                logicalTaskID: event.logicalTaskID,
                                taskID: event.taskID,
                                taskRevision: event.taskRevision,
                                category: .habit,
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
                Text(String(localized: "习惯计划"))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(activeTasks) { task in
                    habitRow(task)
                }
            }
        } else {
            BBTitledCard(
                title: String(localized: "还没有习惯计划"),
                subtitle: String(localized: "添加晒太阳、呼吸训练等每日习惯"),
                systemImage: "leaf",
                tint: .green
            ) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func habitRow(_ task: CareTask) -> some View {
        BBCard(style: .standard, tint: .green) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: task.icon)
                        .font(.appSystem(size: 18))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        if let subtitle = task.subtitle {
                            Text(subtitle)
                                .font(.appSystem(size: 12, weight: .medium))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    if task.linkedModule == "sunlight" {
                        Image(systemName: "link")
                            .font(.appSystem(size: 10))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                scheduleSummary(task.schedule)

                if let target = task.targetValue, let unit = task.unit {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.appSystem(size: 10))
                        Text("\(String(localized: "目标")): \(formattedNumber(target)) \(unit)")
                            .font(.appSystem(size: 12, weight: .medium))
                    }
                    .foregroundColor(.green)
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
