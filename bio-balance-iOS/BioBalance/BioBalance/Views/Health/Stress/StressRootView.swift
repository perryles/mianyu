import SwiftUI
import OSLog

/// 「个人 · 情绪与压力」模块主页。保留现有 HealthKit、压力算法和 NavigationStack。
struct StressRootView: View {
    private static let logger = Logger(subsystem: "com.boundesu.BioBalance", category: "EmotionStress")
    @State private var dashboard = DashboardViewModel.shared
    @State private var stressPoints: [TimeSeriesPoint] = []
    @State private var respiratoryRate: Double?
    @State private var moodEntries: [MoodEntry] = []
    @State private var isLoading = false

    private var realtime: RealtimeHealth? { dashboard.realtimeHealth }
    private var todayMood: MoodEntry? { moodEntries.first }
    private var emotion: EmotionKind {
        guard let todayMood else { return .calm }
        return .resolve(moodID: todayMood.moodID, backendCode: todayMood.backendEmotionCode)
    }
    private var currentStress: Int? {
        if let score = realtime?.stress_value, score > 0 { return score }
        return stressPoints.last(where: { $0.value > 0 })?.value
    }
    private var stability: Int? {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .distantPast
        let entries = MoodStore.shared.allEntries().filter { $0.loggedAt >= start }
        guard entries.count >= 3 else { return nil }
        let values = entries.map { Double($0.intensity) }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = values.map { abs($0 - mean) }.reduce(0, +) / Double(values.count)
        return max(0, min(100, Int((100 - deviation).rounded())))
    }

    var body: some View {
        ZStack {
            EmotionStressStyle.page.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    EmotionStressPageHeader(title: String(localized: "情绪与压力"), subtitle: String(localized: "了解今天的状态与身体信号"))
                    statusHero
                    bodySignals
                    if dataReadinessCount < 5 {
                        dataReadinessCard
                    }
                    todayInsight
                    toolGrid
                }
                .padding(.horizontal, EmotionStressStyle.pagePadding)
                .padding(.top, 10)
                // 主导航使用悬浮 Tab Bar，预留完整高度，避免最后一行功能被遮挡。
                .padding(.bottom, 124)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .profileVitalityRecordsDidChange)) { _ in
            moodEntries = MoodStore.shared.entries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthDataManagerRealtimeHealthDidChange)) { _ in
            Task { await refreshStressPoints() }
        }
        .onChange(of: dashboard.history?.stressHistory.count ?? 0) { _, _ in
            Task { await refreshStressPoints() }
        }
    }

    private var statusHero: some View {
        EmotionStressCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if todayMood != nil {
                        EmotionIconView(emotion: emotion, size: 50)
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(EmotionStressStyle.mint)
                            .frame(width: 50, height: 50)
                            .background(EmotionStressStyle.mintFill, in: Circle())
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(todayMood == nil ? String(localized: "还没有情绪记录") : emotion.title)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(EmotionStressStyle.ink)
                        Text(statusSummary).font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 0) {
                    metric(
                        title: "压力",
                        value: currentStress.map(String.init) ?? String(localized: "待同步"),
                        accessibilityValue: currentStress.map { "\($0)，满分 100" } ?? String(localized: "暂无可用数据")
                    )
                    Divider().frame(height: 42)
                    metric(
                        title: "稳定",
                        value: stability.map(String.init) ?? String(localized: "待积累"),
                        accessibilityValue: stability.map { "\($0)，满分 100" } ?? String(localized: "需要至少三次记录")
                    )
                }
                StressMiniTrend(points: stressPoints)
                    .frame(height: 64)
                    .accessibilityLabel(trendAccessibilityLabel)
                if todayMood == nil {
                    NavigationLink {
                        EmotionCaptureView()
                    } label: {
                        Label("记录此刻", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(BBTintedButtonStyle(tint: EmotionStressStyle.mint))
                    .accessibilityHint("记录当前情绪和影响因素")
                }
            }
        }
    }

    private var bodySignals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("身体信号").font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                signal(title: "心率", value: heartRateSignal.value, status: heartRateSignal.status, icon: "heart")
                signal(title: "HRV", value: hrvSignal.value, status: hrvSignal.status, icon: "waveform.path.ecg")
                signal(title: "呼吸", value: respiratorySignal.value, status: respiratorySignal.status, icon: "wind")
                signal(title: "睡眠", value: sleepSignal.value, status: sleepSignal.status, icon: "bed.double")
            }
        }
    }

    private var todayInsight: some View {
        EmotionStressCard(fill: EmotionStressStyle.mintFill) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("今日洞察").font(.subheadline.weight(.bold)).foregroundStyle(EmotionStressStyle.mint)
                    Spacer()
                    insightAction
                }
                Text(insightTitle).font(.subheadline.weight(.semibold)).foregroundStyle(EmotionStressStyle.ink)
                Text(insightDetail).font(.caption).foregroundStyle(EmotionStressStyle.secondary)
            }
        }
    }

    @ViewBuilder
    private var insightAction: some View {
        if !stressPoints.isEmpty {
            NavigationLink("查看分析") { MindBodyCorrelationView() }
                .font(.caption.weight(.bold))
                .foregroundStyle(EmotionStressStyle.mint)
                .frame(minHeight: 44)
        } else if todayMood == nil {
            NavigationLink("记录此刻") { EmotionCaptureView() }
                .font(.caption.weight(.bold))
                .foregroundStyle(EmotionStressStyle.mint)
                .frame(minHeight: 44)
        } else {
            Button("重新同步") {
                Task { await requestHealthDataAndReload() }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(EmotionStressStyle.mint)
            .frame(minHeight: 44)
            .disabled(isLoading)
        }
    }

    private var dataReadinessCard: some View {
        EmotionStressCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("完善今日状态")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(EmotionStressStyle.ink)
                        Text("已准备 \(dataReadinessCount) / 5 项信息")
                            .font(.caption)
                            .foregroundStyle(EmotionStressStyle.secondary)
                    }
                    Spacer()
                    Text("\(dataReadinessCount * 20)%")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(EmotionStressStyle.mint)
                }

                ProgressView(value: Double(dataReadinessCount), total: 5)
                    .tint(EmotionStressStyle.mint)
                    .accessibilityLabel("今日状态资料完成度")
                    .accessibilityValue("已准备五项中的 \(dataReadinessCount) 项")

                if todayMood == nil {
                    readinessRow(icon: "face.smiling", title: "记录现在的情绪", detail: "约 10 秒，可立即开始形成趋势") {
                        EmotionCaptureView()
                    }
                }

                if healthSignalCount < 4 {
                    Button {
                        Task { await requestHealthDataAndReload() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(EmotionStressStyle.mint)
                                .frame(width: 36, height: 36)
                                .background(EmotionStressStyle.mintFill, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("同步身体信号")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(EmotionStressStyle.ink)
                                Text("从健康 App 读取心率、HRV、呼吸与睡眠")
                                    .font(.caption2)
                                    .foregroundStyle(EmotionStressStyle.secondary)
                            }
                            Spacer()
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(EmotionStressStyle.mint)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }

                Text("即使暂时没有设备数据，也可以先记录情绪或开始呼吸练习。")
                    .font(.caption)
                    .foregroundStyle(EmotionStressStyle.tertiary)
            }
        }
    }

    private func readinessRow<Destination: View>(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(EmotionStressStyle.mint)
                    .frame(width: 36, height: 36)
                    .background(EmotionStressStyle.mintFill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(EmotionStressStyle.ink)
                    Text(detail).font(.caption2).foregroundStyle(EmotionStressStyle.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("全部功能").font(.headline.weight(.bold)).foregroundStyle(EmotionStressStyle.ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tool("记录情绪", "square.and.pencil") { EmotionCaptureView() }
                tool("情绪趋势", "chart.line.uptrend.xyaxis") { EmotionTrendView() }
                tool("呼吸放松", "wind") { BalancedBreathingView() }
                tool("压力详情", "waveform.path.ecg") { PressureDetailView(history: dashboard.history) }
                tool("AI 情绪洞察", "sparkles") { EmotionAIInsightView() }
                tool("情绪压力报告", "doc.text") { EmotionStressReportView() }
            }
        }
    }

    private func metric(title: LocalizedStringKey, value: String, accessibilityValue: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(EmotionStressStyle.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(EmotionStressStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private func signal(title: LocalizedStringKey, value: String, status: String, icon: String) -> some View {
        EmotionStressCard(cornerRadius: 20, padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(EmotionStressStyle.mint).frame(width: 24, height: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption).foregroundStyle(EmotionStressStyle.secondary)
                    Text(value)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(EmotionStressStyle.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(EmotionStressStyle.tertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)，\(status)")
    }

    private func tool<Destination: View>(_ title: LocalizedStringKey, _ icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            EmotionStressCard(cornerRadius: 20, padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(EmotionStressStyle.mint)
                        .frame(width: 36, height: 36).background(EmotionStressStyle.mintFill, in: Circle())
                    HStack {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(EmotionStressStyle.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(EmotionStressStyle.tertiary)
                    }
                }
            }
        }
        .accessibilityHint("打开此功能")
        .bbCardButtonStyle()
    }

    private var statusSummary: String {
        if todayMood == nil {
            return String(localized: "花 10 秒记录现在的感觉，趋势会从这里开始")
        }
        guard let peak = stressPoints.max(by: { $0.value < $1.value }), peak.value >= 60 else {
            return stressPoints.isEmpty
                ? String(localized: "已记录今日感受，身体趋势仍在积累")
                : String(localized: "今天的身体信号整体较平稳")
        }
        return String(localized: "\(peak.date.formatted(.dateTime.hour().minute())) 短暂升高，请结合后续数据观察")
    }
    private var insightTitle: String {
        guard let peak = stressPoints.max(by: { $0.value < $1.value }), peak.value >= 60 else {
            return stressPoints.isEmpty ? String(localized: "数据还不够") : String(localized: "今天暂未发现明显压力峰值。")
        }
        return String(localized: "\(peak.date.formatted(.dateTime.hour().minute())) 出现一次压力上升。")
    }
    private var insightDetail: String {
        stressPoints.isEmpty
            ? String(localized: "同步健康数据后，我才能帮你发现更可靠的趋势。")
            : String(localized: "这是根据现有生理信号整理的健康趋势，不代表医学结论。")
    }
    private var trendAccessibilityLabel: String {
        guard let peak = stressPoints.max(by: { $0.value < $1.value }) else { return String(localized: "今天暂无压力趋势数据") }
        return String(localized: "当天压力趋势，最高值 \(peak.value)，时间 \(peak.date.formatted(.dateTime.hour().minute()))")
    }
    private var heroAccessibilityLabel: String {
        let stress = currentStress.map { String(localized: "当前压力 \($0)，满分 100") } ?? String(localized: "当前压力暂无数据")
        return "\(emotion.title)，\(stress)，\(statusSummary)"
    }
    private var sleepDurationText: String {
        guard let minutes = HealthDataManager.shared.currentSleep?.duration_minutes, minutes > 0 else { return "等待同步" }
        return String(localized: "\(minutes / 60)小时\(minutes % 60)分")
    }

    private var heartRateSignal: (value: String, status: String) {
        if let bpm = positive(realtime?.bpm) { return ("\(bpm) bpm", String(localized: "实时数据")) }
        if let bpm = dashboard.history?.bpmHistory.last(where: { $0.heartRate > 0 })?.heartRate {
            return ("\(bpm) bpm", String(localized: "最近记录"))
        }
        return (String(localized: "等待同步"), String(localized: "佩戴设备后自动更新"))
    }

    private var hrvSignal: (value: String, status: String) {
        if let hrv = positive(realtime?.hrv) { return ("\(Int(hrv.rounded())) ms", String(localized: "实时数据")) }
        if let hrv = dashboard.history?.hrvHistory.last(where: { ($0.sdnn ?? 0) > 0 })?.sdnn {
            return ("\(Int(hrv.rounded())) ms", String(localized: "最近记录"))
        }
        return (String(localized: "等待同步"), String(localized: "睡眠或静息时更易采集"))
    }

    private var respiratorySignal: (value: String, status: String) {
        guard let respiratoryRate, respiratoryRate > 0 else {
            return (String(localized: "等待同步"), String(localized: "有记录后显示节律"))
        }
        return ("\(Int(respiratoryRate.rounded())) 次/分", String(localized: "今日最近记录"))
    }

    private var sleepSignal: (value: String, status: String) {
        guard HealthDataManager.shared.currentSleep?.duration_minutes ?? 0 > 0 else {
            return (String(localized: "等待同步"), String(localized: "完成一次睡眠后显示"))
        }
        return (sleepDurationText, String(localized: "昨夜睡眠"))
    }

    private var healthSignalCount: Int {
        [heartRateSignal.value, hrvSignal.value, respiratorySignal.value, sleepSignal.value]
            .filter { $0 != String(localized: "等待同步") }
            .count
    }

    private var dataReadinessCount: Int {
        healthSignalCount + (todayMood == nil ? 0 : 1)
    }
    private func positive<T: BinaryInteger>(_ value: T?) -> T? { value.flatMap { $0 > 0 ? $0 : nil } }
    private func positive<T: BinaryFloatingPoint>(_ value: T?) -> T? { value.flatMap { $0 > 0 ? $0 : nil } }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        moodEntries = MoodStore.shared.entries()
        dashboard.loadData()
        await refreshStressPoints()
        let start = Calendar.current.startOfDay(for: .now)
        respiratoryRate = try? await HealthKitManager.shared.fetchRespiratoryRateSeries(start: start, end: .now).last?.value
        isLoading = false
        Self.logger.info("[EmotionStress] loaded stressSamples=\(self.stressPoints.count, privacy: .public)")
    }

    private func refreshStressPoints() async {
        stressPoints = await HealthStressEstimator.todayStressPoints(
            realtime: dashboard.realtimeHealth,
            history: dashboard.history
        )
    }

    private func requestHealthDataAndReload() async {
        guard !isLoading else { return }
        isLoading = true
        _ = await HealthAuthorizationCoordinator.shared.requestAuthorizationIfNeeded()
        dashboard.loadData(force: true)
        try? await Task.sleep(for: .milliseconds(800))
        await refreshStressPoints()
        let start = Calendar.current.startOfDay(for: .now)
        respiratoryRate = try? await HealthKitManager.shared.fetchRespiratoryRateSeries(start: start, end: .now).last?.value
        isLoading = false
    }
}

private struct StressMiniTrend: View {
    let points: [TimeSeriesPoint]
    var body: some View {
        GeometryReader { proxy in
            if sampled.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<12, id: \.self) { _ in
                            Capsule()
                                .fill(EmotionStressStyle.border)
                                .frame(maxWidth: .infinity)
                                .frame(height: 6)
                        }
                    }
                    Text("同步后显示今天的压力变化")
                        .font(.caption2)
                        .foregroundStyle(EmotionStressStyle.tertiary)
                }
            } else {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(sampled.enumerated()), id: \.offset) { _, point in
                        Capsule()
                            .fill(point.value >= 60 ? EmotionStressStyle.coral.opacity(0.75) : EmotionStressStyle.grayGreen)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(8, proxy.size.height * CGFloat(point.value) / 100))
                    }
                }
            }
        }
    }
    private var sampled: [TimeSeriesPoint] {
        guard points.count > 12 else { return points }
        let step = max(1, points.count / 12)
        return Swift.stride(from: 0, to: points.count, by: step).map { points[$0] }
    }
}

#Preview { NavigationStack { StressRootView() } }
