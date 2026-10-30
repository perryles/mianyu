/// CareHubView 是 CareKit 照护模块的主入口页面。
///
/// 聚合以下模块：
/// 1. 今日任务概览（CareTaskEvent 列表，统一卡片）
/// 2. 模块入口（服药/康复/习惯/症状）
/// 3. 计划导入
/// 4. 完成率统计
///
/// 与现有 HealthHubView 的关系：
/// - HealthHubView 继续是健康数据主入口
/// - CareHubView 作为"照护计划"专题页面，可从 HealthHub 或独立 Tab 进入

import SwiftUI

struct CareHubView: View {
    @State private var selectedDate: Date = Date()
    @State private var refreshToken = UUID()
    @State private var showTaskEdit: Bool = false
    @State private var taskEditPresetCategory: CareTaskCategory?
    @State private var taskEditPresetModule: String?
    @State private var navigateToAdherence: Bool = false
    @State private var navigateToImport: Bool = false
    @State private var navigateToRehab: Bool = false
    @State private var navigateToHabit: Bool = false
    @State private var navigateToSymptom: Bool = false
    @State private var navigateToMedication: Bool = false

    private var todaySections: [CareTodaySection] {
        CareTaskEngine.shared.todaySummary(referenceDate: selectedDate)
    }

    private var todayTimeline: [JournalTimelineItem] {
        var items: [JournalTimelineItem] = []
        let events = CareTaskEngine.shared.events(on: selectedDate, referenceDate: selectedDate)
        items.append(contentsOf: events.map { .careTaskEvent($0) })

        // 合并当日症状记录
        let symptoms = SelfObservationStore.shared.records(on: selectedDate)
        items.append(contentsOf: symptoms.map { .symptomRecord($0) })

        return items.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateNavigator
                    todayOverviewSection
                    moduleGridSection
                    todayTimelineSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .id(refreshToken)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "照护中心"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            taskEditPresetCategory = .rehabilitation
                            taskEditPresetModule = nil
                            showTaskEdit = true
                        } label: {
                            Label(String(localized: "新建康复任务"), systemImage: "figure.cooldown")
                        }
                        Button {
                            taskEditPresetCategory = .habit
                            taskEditPresetModule = nil
                            showTaskEdit = true
                        } label: {
                            Label(String(localized: "新建习惯任务"), systemImage: "leaf.fill")
                        }
                        Button {
                            taskEditPresetCategory = .habit
                            taskEditPresetModule = "sunlight"
                            showTaskEdit = true
                        } label: {
                            Label(String(localized: "晒太阳任务"), systemImage: "sun.max.fill")
                        }
                        Divider()
                        Button {
                            navigateToImport = true
                        } label: {
                            Label(String(localized: "导入照护计划"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.appSystem(size: 18, weight: .semibold))
                            .foregroundColor(Theme.Colors.mintGreen)
                    }
                }
            }
            .sheet(isPresented: $showTaskEdit) {
                CareTaskEditView(
                    presetCategory: taskEditPresetCategory,
                    presetLinkedModule: taskEditPresetModule
                ) { task in
                    CareTaskEngine.shared.saveTask(task)
                    refreshToken = UUID()
                }
            }
            .navigationDestination(isPresented: $navigateToAdherence) {
                CareAdherenceView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $navigateToImport) {
                CarePlanImportView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $navigateToRehab) {
                RehabilitationPlanView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $navigateToHabit) {
                HabitPlanView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $navigateToSymptom) {
                SymptomJournalView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $navigateToMedication) {
                MedicationCenterView().toolbar(.hidden, for: .tabBar)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .careTasksDidChange)) { _ in
            refreshToken = UUID()
        }
    }

    // MARK: - 日期导航

    @ViewBuilder
    private var dateNavigator: some View {
        HStack(spacing: 12) {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                refreshToken = UUID()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(dateLabel)
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                refreshToken = UUID()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 14, weight: .semibold))
                    .foregroundColor(canGoForward ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
            }
            .disabled(!canGoForward)

            Spacer()

            if !Calendar.current.isDateInToday(selectedDate) {
                Button(String(localized: "今天")) {
                    selectedDate = Date()
                    refreshToken = UUID()
                }
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.mintGreen)
            }
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if Calendar.current.isDateInToday(selectedDate) {
            formatter.setLocalizedDateFormatFromTemplate("MEd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("Md")
        }
        return formatter.string(from: selectedDate)
    }

    private var canGoForward: Bool {
        !Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - 今日概览

    @ViewBuilder
    private var todayOverviewSection: some View {
        let totalEvents = todaySections.flatMap(\.events)
        let completed = totalEvents.filter { $0.status == .completed }.count
        let overdue = totalEvents.filter { $0.status == .overdue }.count
        let total = totalEvents.count

        BBTitledCard(
            title: String(localized: "今日照护"),
            subtitle: "\(completed)/\(total) \(String(localized: "已完成"))",
            systemImage: "checklist",
            tint: Theme.Colors.mintGreen
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    overviewStat(String(localized: "待完成"), count: total - completed - overdue, color: Theme.Colors.mintGreen)
                    overviewStat(String(localized: "已完成"), count: completed, color: .green)
                    overviewStat(String(localized: "待补记"), count: overdue, color: .red)
                }

                if overdue > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.appSystem(size: 12))
                        Text(String(localized: "有 \(overdue) 项任务待补记，点击完成"))
                            .font(.appSystem(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func overviewStat(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.appSystem(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.appSystem(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
        )
    }

    // MARK: - 模块网格

    @ViewBuilder
    private var moduleGridSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            moduleCard(.medication, count: taskCount(.medication), destination: $navigateToMedication)
            moduleCard(.rehabilitation, count: taskCount(.rehabilitation), destination: $navigateToRehab)
            moduleCard(.habit, count: taskCount(.habit), destination: $navigateToHabit)
            moduleCard(.symptom, count: symptomCount, destination: $navigateToSymptom)
        }
    }

    private func taskCount(_ category: CareTaskCategory) -> Int {
        CareTaskEngine.shared.tasks(category: category).count
    }

    private var symptomCount: Int {
        SelfObservationStore.shared.records(on: selectedDate).count
    }

    @ViewBuilder
    private func moduleCard(_ category: CareTaskCategory, count: Int, destination: Binding<Bool>) -> some View {
        let color = categoryColor(category)
        BBCard(style: .standard, tint: color) {
            Button {
                destination.wrappedValue = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: category.symbol)
                        .font(.appSystem(size: 24))
                        .foregroundColor(color)
                    Text(category.title)
                        .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(count > 0 ? "\(count)\(String(localized: "项"))" : String(localized: "暂无"))
                        .font(.appSystem(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 今日时间线

    @ViewBuilder
    private var todayTimelineSection: some View {
        if !todayTimeline.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "今日日志"))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(todayTimeline.prefix(20)) { item in
                    JournalCardView(item: item) { handleQuickComplete(item) }
                }
            }
        }
    }

    private func handleQuickComplete(_ item: JournalTimelineItem) {
        switch item {
        case .careTaskEvent(let event):
            CareTaskEngine.shared.quickComplete(event: event)
            refreshToken = UUID()
        default:
            break
        }
    }

    private func categoryColor(_ category: CareTaskCategory) -> Color {
        switch category {
        case .medication: return .orange
        case .rehabilitation: return .blue
        case .habit: return .green
        case .symptom: return .purple
        }
    }
}

#if DEBUG
#Preview {
    CareHubView()
}
#endif
