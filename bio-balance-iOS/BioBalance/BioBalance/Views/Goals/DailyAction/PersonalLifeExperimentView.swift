import SwiftUI

struct PersonalLifeExperimentEntryLink: View {
    @State private var active: PersonalLifeExperimentRecord?
    private let store = PersonalLifeExperimentStore.shared

    var body: some View {
        NavigationLink {
            PersonalLifeExperimentView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "flask.fill")
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(Color(hex: "8B6F9E"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "8B6F9E").opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("个人生活实验")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(active.map { String(localized: "进行中 · \($0.kind.title)") } ?? String(localized: "用 7 天观察一个生活调整"))
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(16)
            .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .personalLifeExperimentDidChange)) { _ in reload() }
    }

    private func reload() { active = store.activeExperiment() }
}

struct PersonalLifeExperimentView: View {
    @State private var records: [PersonalLifeExperimentRecord] = []
    @State private var followedPlan: Bool?
    @State private var feelingScore: Int?
    private let store = PersonalLifeExperimentStore.shared
    private let calendar = Calendar.current

    private var active: PersonalLifeExperimentRecord? { records.first { $0.status == .active } }

    var body: some View {
        ZStack {
            HealthDetailPageBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let active { activeCard(active) } else { templateCard }
                    historyCard
                    boundaryCard
                }
                .padding(18)
            }
        }
        .healthDetailNavigation(title: "个人生活实验")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .personalLifeExperimentDidChange)) { _ in reload() }
    }

    private var templateCard: some View {
        ReportsContentCard(spacing: 14) {
            ReportsSectionHeader("开始一个 7 天实验", subtitle: "同一时间只进行一个，执行与体感均由你主动记录。")
            ForEach(PersonalLifeExperimentKind.allCases) { kind in
                Button {
                    _ = store.start(kind: kind)
                } label: {
                    HStack {
                        Image(systemName: kind.symbol).frame(width: 28)
                        Text(kind.title)
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        Spacer()
                        Text("开始")
                            .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    }
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(13)
                    .background(Theme.Colors.mintGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func activeCard(_ record: PersonalLifeExperimentRecord) -> some View {
        let summary = PersonalLifeExperimentEngine.make(record: record)
        return ReportsContentCard(spacing: 14) {
            ReportsSectionHeader(record.kind.title, subtitle: progressText(record))

            Text("今天是否做到？")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            HStack(spacing: 10) {
                choiceButton("做到了", value: true)
                choiceButton("没做到", value: false)
            }

            Text("今天体感（可选）")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { score in
                    Button("\(score)") { feelingScore = feelingScore == score ? nil : score }
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundColor(feelingScore == score ? .white : Theme.Colors.textSecondary)
                        .background(feelingScore == score ? Color(hex: "8B6F9E") : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Button("保存今天记录") {
                guard let followedPlan else { return }
                _ = store.saveCheckIn(followedPlan: followedPlan, feelingScore: feelingScore)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.mintGreen)
            .disabled(followedPlan == nil)

            Text(summaryText(summary))
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            Button("提前结束实验", role: .destructive) { _ = store.endActive() }
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
        }
    }

    private var historyCard: some View {
        ReportsContentCard(spacing: 12) {
            ReportsSectionHeader("实验历史", subtitle: "最近完成或结束的实验")
            let history = records.filter { $0.status != .active }.prefix(5)
            if history.isEmpty {
                ReportsInlineEmptyState(text: "暂无历史实验")
            } else {
                ForEach(Array(history)) { record in
                    let summary = PersonalLifeExperimentEngine.make(record: record)
                    HStack {
                        Image(systemName: record.kind.symbol).foregroundColor(Color(hex: "8B6F9E"))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.kind.title).font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            Text(historyStatusText(record))
                                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(record.status == .completed ? Theme.Colors.mintGreen : Theme.Colors.textTertiary)
                            Text(summaryText(summary)).font(.appSystem(size: 10, weight: .medium, design: .rounded)).foregroundColor(Theme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var boundaryCard: some View {
        Label("结果只表示个人时间线观察，不证明生活调整造成了体感变化。", systemImage: "shield.checkered")
            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(14)
            .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
    }

    private func choiceButton(_ title: String, value: Bool) -> some View {
        Button(title) { followedPlan = value }
            .font(.appSystem(size: 12, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundColor(followedPlan == value ? .white : Theme.Colors.textSecondary)
            .background(followedPlan == value ? Theme.Colors.mintGreen : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private func progressText(_ record: PersonalLifeExperimentRecord) -> String {
        let offset = max(0, calendar.dateComponents([.day], from: record.startDate, to: calendar.startOfDay(for: Date())).day ?? 0)
        return String(localized: "第 \(min(offset + 1, record.durationDays)) / \(record.durationDays) 天")
    }

    private func historyStatusText(_ record: PersonalLifeExperimentRecord) -> String {
        switch record.status {
        case .completed: return String(localized: "已完成 7 天")
        case .ended: return String(localized: "已提前结束")
        case .active: return String(localized: "进行中")
        }
    }

    private func summaryText(_ summary: PersonalLifeExperimentSummary) -> String {
        let rate = summary.executionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
        let average = summary.averageFeeling.map { String(format: "%.1f", $0) } ?? "--"
        let direction: String
        switch summary.direction {
        case .higher: direction = String(localized: "后段较高")
        case .close: direction = String(localized: "前后接近")
        case .lower: direction = String(localized: "后段较低")
        case nil: direction = String(localized: "前后段样本不足")
        }
        return String(localized: "记录 \(summary.recordedDays) 天 · 执行率 \(rate) · 平均体感 \(average) · \(direction)")
    }

    private func reload() {
        _ = store.activeExperiment()
        records = store.allRecords()
        guard let today = active?.checkIns.first(where: { calendar.isDateInToday($0.date) }) else {
            followedPlan = nil
            feelingScore = nil
            return
        }
        followedPlan = today.followedPlan
        feelingScore = today.feelingScore
    }
}
