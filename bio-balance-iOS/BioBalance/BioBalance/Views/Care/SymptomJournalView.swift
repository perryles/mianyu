/// SymptomJournalView 是症状日记页面。
///
/// 与服药打卡共用同一套 CareKit 数据模型及交互组件（JournalCardView），
/// UI 层统一为"日志卡片"视图。
///
/// 数据来源：
/// - SelfObservationStore（现有症状/自评记录）
/// - CareTaskEngine 中 symptom 类别的 outcomes
///
/// 不重复实现症状记录表单——点击"记录症状"跳转到现有 BodySymptomObservationView。

import SwiftUI

struct SymptomJournalView: View {
    @State private var selectedDate: Date = Date()
    @State private var refreshToken = UUID()
    @State private var showSymptomEntry: Bool = false

    private var todayRecords: [SelfObservationRecord] {
        SelfObservationStore.shared.records(on: selectedDate)
    }

    private var recentRecords: [SelfObservationRecord] {
        SelfObservationStore.shared.allRecords()
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: selectedDate) }
    }

    private var timelineItems: [JournalTimelineItem] {
        let symptoms = todayRecords.map { JournalTimelineItem.symptomRecord($0) }
        let outcomes = CareTaskEngine.shared.outcomes(on: selectedDate)
            .filter { $0.category == .symptom }
            .map { JournalTimelineItem.careOutcome($0) }
        return (symptoms + outcomes).sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dateNavigator
                recordButton
                timelineSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "症状日记"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showSymptomEntry) {
            BodySymptomObservationView()
        }
        .id(refreshToken)
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
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(dateLabel)
                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Button {
                if !Calendar.current.isDateInToday(selectedDate) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    refreshToken = UUID()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(Calendar.current.isDateInToday(selectedDate) ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
            }

            Spacer()
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MEd")
        return formatter.string(from: selectedDate)
    }

    // MARK: - 记录按钮

    @ViewBuilder
    private var recordButton: some View {
        Button {
            showSymptomEntry = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.appSystem(size: 18))
                Text(String(localized: "记录今天的身体状态"))
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12))
            }
            .foregroundColor(.purple)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.purple.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 时间线

    @ViewBuilder
    private var timelineSection: some View {
        if timelineItems.isEmpty {
            BBTitledCard(
                title: String(localized: "今天还没有记录"),
                subtitle: String(localized: "记下身体的感受，帮助你和医生一起回看"),
                systemImage: "stethoscope",
                tint: .purple
            ) {
                EmptyView()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "今日日志"))
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                ForEach(timelineItems) { item in
                    JournalCardView(item: item)
                }
            }
        }
    }
}
