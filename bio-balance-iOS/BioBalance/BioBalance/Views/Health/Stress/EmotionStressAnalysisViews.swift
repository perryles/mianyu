import SwiftUI

nonisolated struct InsightEvidence: Identifiable, Sendable {
    let id: String
    let source: String
    let dateRange: String
    let metric: String
    let value: String
    let confidence: String
}

private enum EmotionStressData {
    static var moods: [MoodEntry] { MoodStore.shared.allEntries().sorted { $0.loggedAt > $1.loggedAt } }
    static var stress: [TimeSeriesPoint] { HealthDataManager.shared.currentStress?.history.sorted { $0.timestamp < $1.timestamp } ?? [] }
    static var todayStress: [TimeSeriesPoint] {
        stress.filter { Calendar.current.isDateInToday($0.date) }
    }
    static func recentMoods(days: Int) -> [MoodEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        return moods.filter { $0.loggedAt >= start }
    }
    static var significantEvents: [StressEvent] {
        let points = todayStress
        guard points.count >= 3 else { return [] }
        var events: [StressEvent] = []
        for index in points.indices {
            let point = points[index]
            guard point.value >= 55 else { continue }
            let previous = index > 0 ? points[index - 1].value : point.value
            let next = index + 1 < points.count ? points[index + 1].value : point.value
            guard point.value >= previous, point.value >= next else { continue }
            if let last = events.last, point.date.timeIntervalSince(last.date) < 45 * 60 { continue }
            events.append(StressEvent(date: point.date, value: point.value, kind: point.value >= 65 ? .noticeable : .moderate))
        }
        if let lastPeak = events.last,
           let recovered = points.first(where: { $0.date > lastPeak.date && $0.value <= max(35, lastPeak.value - 20) }) {
            events.append(StressEvent(date: recovered.date, value: recovered.value, kind: .recovery))
        }
        return events
    }
}

nonisolated struct StressEvent: Identifiable, Sendable {
    enum Kind: Sendable { case moderate, noticeable, recovery }
    let id = UUID()
    let date: Date
    let value: Int
    let kind: Kind
}

struct EmotionHistoryView: View {
    @State private var filter: EmotionKind?
    @State private var showingCapture = false
    private var entries: [MoodEntry] {
        let all = EmotionStressData.moods
        guard let filter else { return all }
        return all.filter { EmotionKind.resolve(moodID: $0.moodID, backendCode: $0.backendEmotionCode) == filter }
    }

    var body: some View {
        page(title: "记录历史", subtitle: "回看过去的情绪与触发因素") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterButton("全部", selected: filter == nil) { filter = nil }
                    ForEach(EmotionKind.allCases) { kind in
                        filterButton(kind.title, selected: filter == kind) { filter = kind }
                    }
                }
            }
            if entries.isEmpty {
                EmotionStressEmptyState(title: "还没有情绪记录", message: "花 10 秒记录现在的感觉，趋势会从这里开始。", actionTitle: "记录此刻") { showingCapture = true }
            } else {
                ForEach(entries) { entry in historyCard(entry) }
            }
            Button("+ 记录新的情绪") { showingCapture = true }
                .buttonStyle(BBTintedButtonStyle(tint: EmotionStressStyle.mint, isFullWidth: true))
        }
        .navigationDestination(isPresented: $showingCapture) { EmotionCaptureView() }
    }

    private func historyCard(_ entry: MoodEntry) -> some View {
        let kind = EmotionKind.resolve(moodID: entry.moodID, backendCode: entry.backendEmotionCode)
        return EmotionStressCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(EmotionStressStyle.tertiary)
                HStack {
                    EmotionIconView(emotion: kind, size: 24)
                    Text(kind.title).font(.title3.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                    Spacer()
                    Text((entry.factors ?? []).joined(separator: " · ")).font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                }
                Text("强度 \(entry.intensity) / 100").font(.caption.weight(.bold)).foregroundStyle(kind.tint)
                if let note = entry.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(EmotionStressStyle.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(selected ? .bold : .regular))
            .foregroundStyle(selected ? .white : EmotionStressStyle.secondary)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(selected ? EmotionStressStyle.ink : .white, in: Capsule())
            .buttonStyle(.plain)
    }
}

struct StressEventTimelineView: View {
    private var events: [StressEvent] { EmotionStressData.significantEvents }
    private var average: Int? {
        let values = EmotionStressData.todayStress.map(\.value)
        return values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    var body: some View {
        page(title: "压力事件", subtitle: "看看压力是在哪些时刻发生的") {
            EmotionStressCard {
                HStack {
                    VStack(alignment: .leading) {
                        Text("今日平均压力").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                        Text(average.map(String.init) ?? "--").font(.system(size: 30, weight: .bold))
                    }
                    Spacer()
                    Text(events.isEmpty ? "暂无明显波动" : "\(events.filter { $0.kind != .recovery }.count) 次明显波动")
                        .font(.subheadline.weight(.bold))
                }
            }
            if events.isEmpty {
                EmotionStressEmptyState(title: "今天比较平稳", message: "暂时没有发现明显压力事件。")
            } else {
                EmotionStressCard {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            eventRow(event)
                            if event.id != events.last?.id { Divider().padding(.leading, 30) }
                        }
                    }
                }
                if let peak = events.filter({ $0.kind == .noticeable }).max(by: { $0.value < $1.value }) {
                    EmotionStressCard(fill: EmotionStressStyle.mintFill) {
                        Text("最值得关注").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                        Text("\(peak.date.formatted(.dateTime.hour().minute())) 压力峰值 \(peak.value)")
                            .font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                        NavigationLink("查看关联") { MindBodyCorrelationView() }
                            .font(.subheadline.weight(.bold)).foregroundStyle(EmotionStressStyle.mint).frame(minHeight: 44)
                    }
                }
            }
            Text("压力事件会结合心率、HRV、呼吸和记录内容自动整理。")
                .font(.caption).foregroundStyle(EmotionStressStyle.tertiary)
        }
    }

    private func eventRow(_ event: StressEvent) -> some View {
        let isPeak = event.kind == .noticeable
        let isRecovery = event.kind == .recovery
        let color = isPeak ? EmotionStressStyle.coral : (isRecovery ? EmotionStressStyle.mint : EmotionStressStyle.grayGreen)
        let label = isPeak ? "明显" : (isRecovery ? "恢复" : "中等")
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 12, height: 12).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.date.formatted(.dateTime.hour().minute())).font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.tertiary)
                Text(isRecovery ? "压力回落" : "身体信号波动").font(.subheadline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                Text("压力 \(event.value)").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
            }
            Spacer()
            Text(label).font(.caption.weight(.bold)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6)
                .background(color.opacity(0.10), in: Capsule())
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
}

struct MindBodyCorrelationView: View {
    private var moods: [MoodEntry] { EmotionStressData.recentMoods(days: 14) }
    private var hasEnoughData: Bool { Set(moods.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count >= 5 }

    var body: some View {
        page(title: "身心关联", subtitle: "找出影响情绪和压力的关键因素") {
            if !hasEnoughData {
                EmotionStressEmptyState(title: "数据还不够", message: "再记录几天，我才能帮你发现更可靠的趋势。")
            } else {
                let factors = factorSummaries
                EmotionStressCard {
                    Text("本周最明显的关联").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.secondary)
                    Text(factors.first.map { "\($0.name) ↔ \($0.effect)" } ?? "记录 ↔ 情绪变化")
                        .font(.title2.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                    Text("这是记录共同出现频率较高的趋势，不代表因果关系。").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                }
                EmotionStressCard(fill: EmotionStressStyle.mintFill) {
                    Text("依据强度").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                    Text("过去 14 天 · \(Set(moods.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count) 天数据支持")
                        .font(.subheadline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
                }
                EmotionStressCard {
                    Text("关联强度").font(.headline.weight(.bold))
                    ForEach(factors) { factor in correlationRow(factor) }
                }
                EmotionStressCard {
                    HStack { AIInsightIcon(); Text("AI 解释").font(.headline.weight(.bold)) }
                    Text("这些是健康数据中的相关性分析，不能表达为医学因果。")
                        .font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
                }
            }
            Text("分析用于帮助理解健康趋势，不用于医疗诊断。")
                .font(.caption).foregroundStyle(EmotionStressStyle.tertiary).frame(maxWidth: .infinity)
        }
    }

    private var factorSummaries: [FactorSummary] {
        let values = moods.flatMap { $0.factors ?? [] }
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(4).enumerated().map { index, item in
            FactorSummary(name: item.key, effect: item.key == "睡眠" ? "情绪稳定" : "情绪变化", strength: max(0.35, 0.86 - Double(index) * 0.13))
        }
    }

    private func correlationRow(_ factor: FactorSummary) -> some View {
        HStack {
            Text(factor.name).font(.caption.weight(.bold)).frame(width: 52, alignment: .leading)
            Text("→ \(factor.effect)").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
            ProgressView(value: factor.strength).tint(EmotionStressStyle.mintMuted)
            Text(factor.strength > 0.75 ? "强" : factor.strength > 0.55 ? "较强" : "中等").font(.caption.weight(.bold))
        }.frame(minHeight: 36).accessibilityElement(children: .combine)
    }
}

private struct FactorSummary: Identifiable {
    var id: String { name }
    let name: String
    let effect: String
    let strength: Double
}

struct EmotionAIInsightView: View {
    private var moods: [MoodEntry] { EmotionStressData.recentMoods(days: 7) }
    private var evidence: [InsightEvidence] {
        var result: [InsightEvidence] = []
        if let peak = EmotionStressData.todayStress.max(by: { $0.value < $1.value }), peak.value >= 60 {
            result.append(.init(id: "stress", source: "HealthKit 与眠屿压力估算", dateRange: "今天", metric: "压力峰值", value: "\(peak.value) · \(peak.date.formatted(.dateTime.hour().minute()))", confidence: "基于现有样本"))
        }
        if moods.count >= 3 {
            let dominant = Dictionary(grouping: moods) { EmotionKind.resolve(moodID: $0.moodID, backendCode: $0.backendEmotionCode) }.max { $0.value.count < $1.value.count }
            if let dominant { result.append(.init(id: "mood", source: "本机情绪记录", dateRange: "最近 7 天", metric: "常见情绪", value: dominant.key.title, confidence: "\(dominant.value.count) 条记录")) }
        }
        return result
    }

    var body: some View {
        page(title: "AI 情绪洞察", subtitle: "结合你的健康数据，解释今天发生了什么") {
            VStack(spacing: 10) {
                AIInsightIcon(size: 28).frame(width: 68, height: 68).background(Theme.Colors.surface, in: Circle())
                Text(evidence.isEmpty ? "数据还不够" : "今天的数据已完成整理").font(.title3.weight(.bold))
                Text("睡眠、压力、运动与情绪记录综合分析").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
            if evidence.isEmpty {
                EmotionStressEmptyState(title: "数据还不够", message: "再记录几天，我才能帮你发现更可靠的趋势。")
            } else {
                ForEach(Array(evidence.enumerated()), id: \.element.id) { index, item in
                    EmotionStressCard {
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.mint).frame(width: 32, height: 32).background(EmotionStressStyle.mintFill, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.metric).font(.headline.weight(.bold))
                                Text(item.value).font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
                                Text("\(item.source) · \(item.dateRange)").font(.caption2).foregroundStyle(EmotionStressStyle.tertiary)
                            }
                        }
                    }
                }
            }
            EmotionStressCard {
                Text("今天可以试试").font(.headline.weight(.bold))
                NavigationLink("进行一次 3 分钟呼吸练习") { BalancedBreathingView() }
                    .font(.subheadline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink).frame(minHeight: 44)
            }
            NavigationLink("继续问我") { EmotionAIChatView(evidence: evidence) }
                .buttonStyle(BBPrimaryButtonStyle(isFullWidth: true))
        }
    }
}

struct EmotionAIChatView: View {
    let evidence: [InsightEvidence]
    @State private var assistant: HealthAIViewModel

    init(evidence: [InsightEvidence]) {
        self.evidence = evidence
        let dashboard = DashboardViewModel.shared
        let context = HealthAIContextBuilder().makeContext(
            assessment: dashboard.dailyStressAssessment,
            realtimeHealth: dashboard.realtimeHealth,
            restingHeartRate: dashboard.restingHeartRate,
            avgHrvToday: dashboard.avgHrvToday,
            recentAvgHrv: dashboard.recentAvgHrv,
            recentAvgRestingHeartRate: dashboard.recentAvgRestingHeartRate,
            sleepData: HealthDataManager.shared.currentSleep,
            sleepInterval: nil,
            nightlyHrv: nil,
            nightlyRespiratoryRate: nil,
            sleepingWristTemperature: nil,
            sedentaryState: dashboard.sedentaryState,
            sedentarySummary: nil,
            activityPoints: dashboard.todayActivityPoints
        )
        _assistant = State(initialValue: HealthAIViewModel(context: context))
    }

    var body: some View {
        page(title: "AI 情绪助手", subtitle: "基于你的健康数据继续聊") {
            EmotionStressCard(fill: EmotionStressStyle.mintFill) {
                HStack(alignment: .top) {
                    AIInsightIcon()
                    Text(evidence.isEmpty ? "目前数据不足，我不会生成没有依据的结论。" : "我会结合睡眠、压力、运动和情绪记录回答。")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if evidence.isEmpty {
                EmotionStressEmptyState(title: "数据还不够", message: "完成更多情绪记录并同步健康数据后再来问我。")
            } else {
                ForEach(assistant.messages) { message in
                    EmotionStressCard(fill: message.role == .user ? .white : EmotionStressStyle.mintFill) {
                        Text(message.text).font(.subheadline).foregroundStyle(EmotionStressStyle.ink)
                        if message.isLoading { ProgressView().tint(EmotionStressStyle.mint) }
                    }
                    .padding(.leading, message.role == .user ? 54 : 0)
                }
                EmotionStressCard {
                    Text("查看依据数据").font(.headline.weight(.bold))
                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.metric).font(.subheadline.weight(.bold))
                            Text("\(item.value) · \(item.source)").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                        }.padding(.vertical, 4)
                    }
                    Text("这些只是健康数据中的关联，不代表医学诊断。").font(.caption).foregroundStyle(EmotionStressStyle.tertiary)
                }
            }
            Text("快捷追问").font(.headline.weight(.bold))
            ForEach(["睡眠影响情绪吗？", "这周压力为什么高？", "现在适合运动吗？"], id: \.self) { prompt in
                Button(prompt) { Task { await assistant.submitFollowUp(prompt) } }
                    .buttonStyle(BBSecondaryButtonStyle(isFullWidth: true))
            }
            HStack {
                TextField("还有什么想问的？", text: $assistant.inputText).textFieldStyle(.plain)
                Button { Task { await assistant.submitCurrentInput() } } label: {
                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(EmotionStressStyle.ink)
                }
                .accessibilityLabel("发送")
            }.padding(.horizontal, 16).frame(minHeight: 48).background(Theme.Colors.surface, in: Capsule()).overlay(Capsule().stroke(EmotionStressStyle.border))
        }
    }
}

struct EmotionStressReportView: View {
    @State private var isMonthly = false
    private var moods: [MoodEntry] { EmotionStressData.recentMoods(days: isMonthly ? 30 : 7) }
    private var stressPoints: [TimeSeriesPoint] {
        let days = isMonthly ? 30 : 7
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        return EmotionStressData.stress.filter { $0.date >= start }
    }
    private var stability: Int? {
        guard moods.count >= 3 else { return nil }
        let values = moods.map { Double($0.intensity) }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = values.map { abs($0 - mean) }.reduce(0, +) / Double(values.count)
        return max(0, Int((100 - deviation).rounded()))
    }
    private var averageStress: Int? {
        let values = stressPoints.map(\.value)
        return values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    var body: some View {
        page(title: "情绪健康周报", subtitle: periodSubtitle) {
            HStack {
                periodButton("周报", selected: !isMonthly) { isMonthly = false }
                periodButton("月报", selected: isMonthly) { isMonthly = true }
            }
            if moods.count < 3 && stressPoints.isEmpty {
                EmotionStressEmptyState(title: "数据还不够", message: "再记录几天，我才能帮你生成更可靠的报告。")
            } else {
                EmotionStressCard {
                    Text(stability.map { $0 >= 75 ? "这一周期整体较稳定" : "这一周期有一些波动" } ?? "已有部分健康数据")
                        .font(.title2.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                    Text("报告只使用本机已有情绪与压力数据。").font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                }
                HStack(spacing: 10) {
                    reportMetric("情绪稳定度", stability.map(String.init) ?? "--")
                    reportMetric("平均压力", averageStress.map(String.init) ?? "--")
                    reportMetric("情绪记录", "\(moods.count)")
                }
                EmotionStressCard {
                    Text("本期变化").font(.headline.weight(.bold))
                    reportBar("情绪", value: Double(stability ?? 0) / 100, color: EmotionStressStyle.mint)
                    reportBar("压力", value: Double(averageStress ?? 0) / 100, color: EmotionStressStyle.coral.opacity(0.65))
                }
                EmotionStressCard {
                    HStack { AIInsightIcon(); Text("AI 本期总结").font(.headline.weight(.bold)) }
                    Text(summaryText).font(.subheadline).foregroundStyle(EmotionStressStyle.secondary)
                }
            }
            Text("分析用于帮助理解健康趋势，不用于医疗诊断。").font(.caption).foregroundStyle(EmotionStressStyle.tertiary).frame(maxWidth: .infinity)
        }
    }

    private var periodSubtitle: String {
        let days = isMonthly ? 30 : 7
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: .now) ?? .now
        return "\(isMonthly ? "本月" : "本周") · \(start.formatted(.dateTime.month().day()))–\(Date.now.formatted(.dateTime.month().day()))"
    }
    private var summaryText: String {
        guard !moods.isEmpty else { return "已有压力数据，但情绪记录不足，暂不推断生活因素。" }
        return "共整理 \(moods.count) 条情绪记录和 \(stressPoints.count) 个压力样本；相关性不代表医学因果。"
    }
    private func periodButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.caption.weight(.bold)).foregroundStyle(selected ? .white : EmotionStressStyle.secondary)
            .padding(.horizontal, 24).frame(minHeight: 44).background(selected ? EmotionStressStyle.ink : EmotionStressStyle.track, in: Capsule()).buttonStyle(.plain)
    }
    private func reportMetric(_ title: String, _ value: String) -> some View {
        EmotionStressCard(cornerRadius: 20, padding: 12) {
            VStack(spacing: 8) { Text(title).font(.caption2).foregroundStyle(EmotionStressStyle.secondary); Text(value).font(.title2.weight(.bold)) }
                .frame(maxWidth: .infinity)
        }
    }
    private func reportBar(_ title: String, value: Double, color: Color) -> some View {
        HStack { Text(title).font(.caption).frame(width: 44, alignment: .leading); ProgressView(value: value).tint(color) }
    }
}

@ViewBuilder
private func page<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
    ZStack {
        EmotionStressStyle.page.ignoresSafeArea()
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                EmotionStressPageHeader(title: title, subtitle: subtitle)
                content()
            }
            .padding(.horizontal, EmotionStressStyle.pagePadding).padding(.top, 10).padding(.bottom, 36)
        }
    }.navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
}
