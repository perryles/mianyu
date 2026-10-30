import AVFoundation
import Charts
import SwiftUI

struct SnoreAnalysisPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model: SnoreAnalysisViewModel
    @State private var path: [SnoreAnalysisRoute] = []
    @State private var showingScoreExplanation = false

    init(viewModel: SleepViewModel) {
        _model = State(initialValue: SnoreAnalysisViewModel(sleepViewModel: viewModel))
    }

    var body: some View {
        NavigationStack(path: $path) {
            SnoreReportView(
                session: model.selectedSession,
                analysisState: model.state,
                liveEnvironmentRMS: model.liveEnvironmentRMS,
                startDetection: { Task { await model.startDetection() } },
                stopDetection: { Task { await model.stopDetection() } },
                startLiveAudioPolling: model.startLiveAudioPolling,
                stopLiveAudioPolling: model.stopLiveAudioPolling,
                openSettings: openSettings,
                showScoreExplanation: { showingScoreExplanation = true },
                openEvents: { path.append(.events(model.selectedSession?.id)) }
            )
                .navigationDestination(for: SnoreAnalysisRoute.self) { route in destination(for: route) }
                .healthDetailNavigation(title: "鼾声分析")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HealthNavigationDismissButton { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingScoreExplanation = true } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("鼾声评分说明")
                    }
                }
        }
        .tint(Theme.Colors.textPrimary)
        .preferredColorScheme(.light)
        .toolbarBackground(SnorePalette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await model.refresh() }
        .sheet(isPresented: $showingScoreExplanation) {
            SnoreScoreExplanationSheet(breakdown: scoreBreakdown(model.selectedSession))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func destination(for route: SnoreAnalysisRoute) -> some View {
        switch route {
        case .report(let id):
            SnoreReportView(
                session: id.flatMap { id in model.sessions.first(where: { $0.id == id }) },
                analysisState: model.state,
                liveEnvironmentRMS: model.liveEnvironmentRMS,
                startDetection: { Task { await model.startDetection() } },
                stopDetection: { Task { await model.stopDetection() } },
                startLiveAudioPolling: model.startLiveAudioPolling,
                stopLiveAudioPolling: model.stopLiveAudioPolling,
                openSettings: openSettings,
                showScoreExplanation: { showingScoreExplanation = true },
                openEvents: { path.append(.events(id)) }
            )
        case .events(let id):
            SnoreEventsView(session: id.flatMap { id in model.sessions.first(where: { $0.id == id }) })
        case .trend:
            SnoreTrendView(points: model.trendPoints)
        case .history:
            SnoreHistoryView(sessions: model.sessions) { path.append(.report($0)) }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func scoreBreakdown(_ session: SnoreSession?) -> [SnoreScoreBreakdownItem] {
        guard let session else { return [] }
        return [
            .init(title: "频次", weightText: "每小时事件密度", tint: SnorePalette.blue, value: min(100, Int(session.eventsPerHour * 8))),
            .init(title: "时长", weightText: "累计鼾声时间", tint: SnorePalette.amber, value: min(100, Int(session.snoreDurationMinutes * 4))),
            .init(title: "响度", weightText: "相对峰值强度", tint: SnorePalette.coral, value: min(100, (session.events.map(\.loudnessBucket).max() ?? 0) * 8)),
            .init(title: "规律性", weightText: "事件间隔稳定度", tint: SnorePalette.accent, value: session.regularityScore ?? 0)
        ]
    }
}


private enum SnoreAnalysisRoute: Hashable {
    /// 今晚报告：带会话 id 时展示该晚数据，无数据时（nil）报告页以空态呈现。
    case report(String?)
    case events(String?)
    case trend
    case history
}

private enum SnorePalette {
    static let accent = Color(hex: "7965DC")
    static let blue = Color(hex: "6AACE8")
    static let amber = Color(hex: "EE972B")
    static let coral = Color(hex: "EE5A64")
    static let background = Color.white
    static let surface = Color.white
    static let inset = Color(hex: "F4F1FD")
    static let separator = Color(hex: "EFEDF2")
    static let ink = Color(hex: "25243A")
    static let muted = Color(hex: "858394")

    static func color(for severity: SnoreSeverity) -> Color {
        switch severity {
        case .quiet, .mild: Color(hex: "24AE83")
        case .noticeable: amber
        case .loud: coral
        }
    }
}

private struct SnoreHomeView: View {
    @Bindable var model: SnoreAnalysisViewModel
    let open: (SnoreAnalysisRoute) -> Void
    let openSettings: () -> Void
    @State private var showingEvidence = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.large) {
                tonightHero
                resultContent
                safetyExplanation
            }
            .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
            .padding(.top, HealthDetailDesignSystem.pageTopPadding)
            .padding(.bottom, HealthDetailDesignSystem.pageBottomPadding)
        }
        .background(SnorePalette.background.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .sheet(isPresented: $showingEvidence) { SnoreEvidenceSheet() }
    }

    @ViewBuilder
    private var tonightHero: some View {
        switch model.state {
        case .recording(let startedAt):
            SnoreRecordingStateView(startedAt: startedAt, liveEnvironmentRMS: model.liveEnvironmentRMS) { Task { await model.stopDetection() } }
                .task { model.startLiveAudioPolling() }
        case .processing:
            SnoreStatusCard(symbol: "waveform.badge.magnifyingglass", title: "正在分析今晚声音", message: "正在整理事件、时段和节律，完成后会自动显示报告。", showsProgress: true)
        case .noPermission:
            SnoreStatusCard(symbol: "mic.slash.fill", title: "需要麦克风权限", message: "用于检测夜间环境声音和鼾声片段。", actionTitle: "前往设置", action: openSettings)
        case .failed(let message):
            SnoreStatusCard(symbol: "exclamationmark.triangle.fill", title: "检测未能开始", message: message, actionTitle: "重试") { Task { await model.startDetection() } }
        default:
            SnoreTonightHeroCard(
                tonightSession: model.tonightSession,
                startDetection: { Task { await model.startDetection() } }
            )
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch model.state {
        case .loading:
            SnoreStatusCard(symbol: "moon.stars", title: "正在读取夜间记录", message: "正在整理最新鼾声摘要与历史趋势。", showsProgress: true)
        case .empty:
            SnoreInlineState(symbol: "waveform.path.ecg", title: "尚无鼾声分析结果", message: "完成一次夜间检测后，这里会显示声音时间线与分析结果。")
        case .noSleepData:
            SnoreInlineState(symbol: "bed.double", title: "暂无睡眠数据", message: "保持睡眠权限开启并完成一晚记录后，再回来查看鼾声与睡眠的关系。")
        case .completed, .recording, .processing, .failed, .noPermission:
            if let session = model.sessions.first { resultSections(session) }
        }
    }

    private func resultSections(_ session: SnoreSession) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SnoreTimelineView(session: session, compact: false)
                SnoreAudioEvidenceView(session: session) { open(.events(session.id)) }
            }

            SnoreHomeInsightCard(session: session) {
                open(.report(session.id))
            }

            VStack(alignment: .leading, spacing: 14) {
                SnoreSectionHeading(title: "趋势预览", action: "查看趋势") { open(.trend) }
                SnoreTrendPreview(points: Array(model.trendPoints.suffix(7)))
            }

            VStack(alignment: .leading, spacing: 14) {
                SnoreSectionHeading(title: "历史记录", action: "查看全部") { open(.history) }
                ForEach(model.sessions.prefix(2)) { item in
                    Button { open(.report(item.id)) } label: {
                        SnoreHistoryRow(session: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var safetyExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("安全与说明", systemImage: "lock.shield.fill")
                .font(Theme.Typography.sectionTitle)
            Text("鼾声分析会处理夜间声音。当前实现只保存分析特征和事件摘要，不上传原始音频。")
                .font(Theme.Typography.caption).foregroundStyle(.secondary)
            Text("结果用于个人趋势参考，不属于医疗诊断。")
                .font(Theme.Typography.caption).foregroundStyle(.secondary)
            Button("查看数据依据与分析边界") { showingEvidence = true }
                .font(Theme.Typography.captionBold)
                .foregroundStyle(SnorePalette.accent)
        }
        .snoreCard()
    }
}

private struct SnoreTonightHeroCard: View {
    let tonightSession: SnoreSession?
    let startDetection: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if tonightSession != nil {
                Image(systemName: "waveform.path.ecg")
                    .font(.appSystem(size: 112, weight: .ultraLight))
                    .foregroundStyle(SnorePalette.accent.opacity(0.055))
                    .offset(x: 28, y: 48)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tonightSession == nil ? "今晚" : "鼾声分析")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(SnorePalette.amber)
                        Text(tonightSession == nil ? "记录你的夜间声音" : "鼾声分析")
                            .font(.appSystem(size: 24, weight: .bold, design: .rounded))
                        if let tonightSession {
                            Label {
                                Text("\(tonightSession.date.formatted(.dateTime.month().day().weekday()))  \(tonightSession.startTime.formatted(date: .omitted, time: .shortened)) 至 \(tonightSession.endTime.formatted(date: .omitted, time: .shortened))")
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("睡前开启检测，醒来后查看鼾声时段、频次和变化趋势。")
                                .font(Theme.Typography.bodyMedium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: tonightSession == nil ? "moon.stars.fill" : "waveform")
                        .font(.appSystem(size: 23, weight: .semibold))
                        .foregroundStyle(SnorePalette.accent)
                        .frame(width: 46, height: 46)
                        .background(SnorePalette.accent.opacity(0.14), in: Circle())
                }

                if let tonightSession {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("鼾声评分")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(.secondary)
                            Text("\(tonightSession.snoreScore)")
                                .font(.appSystem(size: 50, weight: .black, design: .rounded))
                                .foregroundStyle(SnorePalette.color(for: tonightSession.severity))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(tonightSession.severity.title)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(SnorePalette.color(for: tonightSession.severity))
                            Text("\(durationText(tonightSession.snoreDurationMinutes)) · \(tonightSession.eventCount) 次")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                            Text("约占睡眠 \(percentText(tonightSession.snorePercentage))")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 0) {
                        SnoreHeroMetric(title: "鼾声事件", value: "\(tonightSession.eventCount) 次")
                        Divider().frame(height: 34)
                        SnoreHeroMetric(title: "鼾声时长", value: durationText(tonightSession.snoreDurationMinutes))
                        Divider().frame(height: 34)
                        SnoreHeroMetric(title: "每小时", value: oneDecimal(tonightSession.eventsPerHour))
                    }
                    .padding(.vertical, 4)
                    Text("根据夜间声音特征、持续时间和分布综合评定")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(action: startDetection) {
                        Label("开始检测", systemImage: "mic.fill")
                            .font(Theme.Typography.bodyBold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SnorePalette.accent)
                }

                Label("建议插电，并将手机放在床边保持麦克风无遮挡", systemImage: "battery.100percent")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .snoreCard()
    }
}

private struct SnoreHeroMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(Theme.Typography.bodyBold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct SnoreHomeInsightCard: View {
    let session: SnoreSession
    let openReport: () -> Void

    private var summary: String {
        if let conclusion = timelineConclusion(session) {
            return conclusion
        }
        return "今晚的鼾声事件较分散，暂未形成明显集中时段。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path")
                    .font(.appSystem(size: 19, weight: .semibold))
                    .foregroundStyle(SnorePalette.accent)
                    .frame(width: 40, height: 40)
                    .background(SnorePalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("今晚结论")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(.secondary)
                    Text(session.pattern.title)
                        .font(Theme.Typography.cardTitle)
                    Text(summary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Button(action: openReport) {
                HStack {
                    Text("查看完整报告")
                        .font(Theme.Typography.bodyBold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.captionBold)
                }
                .foregroundStyle(SnorePalette.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .snoreCard()
    }
}

private struct SnoreRecordingStateView: View {
    let startedAt: Date
    let liveEnvironmentRMS: Double
    let stop: () -> Void

    private var ambienceTitle: String {
        switch liveEnvironmentRMS {
        case ..<0.008: String(localized: "环境很安静")
        case ..<0.03: String(localized: "环境正常")
        default: String(localized: "环境较嘈杂")
        }
    }

    private var ambienceSymbol: String {
        switch liveEnvironmentRMS {
        case ..<0.008: "speaker.wave.1"
        case ..<0.03: "speaker.wave.2"
        default: "speaker.wave.3"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("正在检测", systemImage: "waveform.circle.fill").font(Theme.Typography.sectionTitle).foregroundStyle(SnorePalette.accent)
                    Spacer()
                    Text(elapsedClock(elapsed)).font(.appSystem(size: 18, weight: .bold, design: .monospaced))
                }
                Text("麦克风已开启，正在提取设备端声音特征。").font(Theme.Typography.bodyMedium).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: ambienceSymbol).foregroundStyle(SnorePalette.accent)
                    Text(ambienceTitle).font(Theme.Typography.captionBold)
                    Spacer()
                    Text("环境声音实时状态").font(Theme.Typography.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(SnorePalette.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .accessibilityElement(children: .combine)
                Button("停止检测", role: .destructive, action: stop).buttonStyle(.bordered)
            }.snoreCard()
        }
    }
}

private struct SnoreReportView: View {
    let session: SnoreSession?
    let analysisState: SnoreAnalysisScreenState
    let liveEnvironmentRMS: Double
    let startDetection: () -> Void
    let stopDetection: () -> Void
    let startLiveAudioPolling: () -> Void
    let stopLiveAudioPolling: () -> Void
    let openSettings: () -> Void
    let showScoreExplanation: () -> Void
    let openEvents: () -> Void
    @State private var showingEvidence = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let session {
                    SnoreContinuousReportHero(session: session)
                } else {
                    SnoreReportEmptyHero()
                }
                if let session {
                    SnoreContinuousReportDivider()

                    reportSection("音频时间线", trailing: "\(session.eventCount) 次鼾声事件") {
                        SnoreTimelineView(session: session, compact: false)
                    }
                    SnoreContinuousReportDivider()

                    reportSection("综合严重度") {
                        SnoreSeverityView(session: session, showExplanation: showScoreExplanation)
                        SnoreLoadChart(session: session)
                    }
                    SnoreContinuousReportDivider()

                    reportSection("整夜分布") {
                        SnoreNightDistributionView(session: session)
                    }
                    SnoreContinuousReportDivider()
                    reportSection("响度分析") {
                        SnoreLoudnessView(session: session)
                    }
                    SnoreContinuousReportDivider()
                    reportSection("鼾声规律性") {
                        SnoreRhythmView(session: session)
                        SnorePatternCard(pattern: session.pattern)
                    }
                    SnoreContinuousReportDivider()

                    reportSection("证据与睡眠阶段") {
                        SnoreBreathingSignalCard(session: session, showEvidence: { showingEvidence = true })
                        SnoreSleepStageChart(correlations: session.stageCorrelation)
                        SnoreAudioEvidenceView(session: session, openEvents: openEvents)
                    }
                } else {
                    SnoreContinuousReportDivider()
                    reportSection("音频时间线") {
                        ModernReportChartEmptyState(
                            symbol: "waveform",
                            title: String(localized: "等待鼾声样本"),
                            message: String(localized: "完成一次夜间检测后，这里会显示声音时间线与分析结果。"),
                            tint: SnorePalette.accent
                        )
                    }
                    SnoreContinuousReportDivider()
                    reportSection("综合严重度") {
                        ModernReportChartEmptyState(
                            symbol: "chart.xyaxis.line",
                            title: String(localized: "等待鼾声样本"),
                            message: String(localized: "完成一次夜间检测后，这里会显示声音时间线与分析结果。"),
                            tint: SnorePalette.accent
                        )
                    }
                    SnoreContinuousReportDivider()
                    reportSection("整夜分布") {
                        ModernReportChartEmptyState(
                            symbol: "chart.bar.fill",
                            title: String(localized: "等待鼾声样本"),
                            message: String(localized: "完成一次夜间检测后，这里会显示声音时间线与分析结果。"),
                            tint: SnorePalette.accent
                        )
                    }
                }
                SnoreContinuousReportDivider()
                reportSection("主动鼾声分析") {
                    SnoreActiveAnalysisEntry(
                        state: analysisState,
                        liveEnvironmentRMS: liveEnvironmentRMS,
                        startDetection: startDetection,
                        stopDetection: stopDetection,
                        openSettings: openSettings
                    )
                    .onAppear {
                        guard case .recording = analysisState else { return }
                        startLiveAudioPolling()
                    }
                    .onDisappear(perform: stopLiveAudioPolling)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 64)
            .environment(\.snoreSurfaceStyle, .continuous)
        }
        .background(SnorePalette.background.ignoresSafeArea())
        .navigationTitle(reportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEvidence) { SnoreEvidenceSheet() }
    }

    private var reportTitle: String {
        guard let session else { return "鼾声分析" }
        if Calendar.current.isDateInToday(session.date) { return String(localized: "鼾声分析 · 今天") }
        return "鼾声分析 · \(session.date.formatted(.dateTime.month().day()))"
    }

    private func reportSection<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                Text(title)
                    .font(.appSystem(size: 20, weight: .bold))
                    .foregroundStyle(SnorePalette.ink)
                Spacer(minLength: 12)
                if let trailing {
                    Text(trailing)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(.top, 37)
        .padding(.bottom, 28)
    }
}

private struct SnoreReportEmptyHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("鼾声分析")
                .font(.appSystem(size: 28, weight: .bold))
                .foregroundStyle(SnorePalette.ink)
                .padding(.top, 7)
            Text("鼾声评分")
                .font(.appSystem(size: 14))
                .foregroundStyle(SnorePalette.muted)
                .padding(.top, 28)
            Text("--")
                .font(.appSystem(size: 84, weight: .heavy))
                .foregroundStyle(SnorePalette.accent)
                .padding(.vertical, 2)
            Text("等待鼾声样本")
                .font(.appSystem(size: 15, weight: .semibold))
                .foregroundStyle(SnorePalette.accent)
            Text("完成一次夜间检测后，这里会生成整晚的声音时间线和分析报告。")
                .font(.appSystem(size: 12))
                .foregroundStyle(SnorePalette.muted)
                .lineSpacing(4)
                .padding(.top, 9)
            HStack(alignment: .top, spacing: 12) {
                SnoreContinuousMetric(title: "鼾声事件", value: "--", unit: "次")
                SnoreContinuousMetric(title: "鼾声时长", value: "--", unit: "分")
                SnoreContinuousMetric(title: "峰值强度", value: "--")
            }
            .padding(.top, 28)
        }
        .padding(.bottom, 28)
    }
}

private struct SnoreActiveAnalysisEntry: View {
    let state: SnoreAnalysisScreenState
    let liveEnvironmentRMS: Double
    let startDetection: () -> Void
    let stopDetection: () -> Void
    let openSettings: () -> Void

    var body: some View {
        switch state {
        case .recording(let startedAt):
            SnoreRecordingStateView(
                startedAt: startedAt,
                liveEnvironmentRMS: liveEnvironmentRMS,
                stop: stopDetection
            )
        case .processing:
            SnoreStatusCard(
                symbol: "waveform.badge.magnifyingglass",
                title: "正在分析今晚声音",
                message: "正在整理事件、时段和节律，完成后会自动显示报告。",
                showsProgress: true
            )
        case .noPermission:
            SnoreStatusCard(
                symbol: "mic.slash.fill",
                title: "需要麦克风权限",
                message: "用于检测夜间环境声音和鼾声片段。",
                actionTitle: "前往设置",
                action: openSettings
            )
        case .failed(let message):
            SnoreStatusCard(
                symbol: "exclamationmark.triangle.fill",
                title: "检测未能开始",
                message: message,
                actionTitle: "重试",
                action: startDetection
            )
        case .loading:
            SnoreStatusCard(
                symbol: "moon.stars",
                title: "正在读取夜间记录",
                message: "正在整理最新鼾声摘要与历史趋势。",
                showsProgress: true
            )
        case .empty, .noSleepData, .completed:
            VStack(alignment: .leading, spacing: 12) {
                Text("睡前开启检测，醒来后可在本页查看鼾声时段、频次和变化趋势。")
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(.secondary)
                Button(action: startDetection) {
                    Label("开始主动鼾声分析", systemImage: "mic.fill")
                        .font(Theme.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(SnorePalette.accent)
                Label("建议插电，并将手机放在床边保持麦克风无遮挡", systemImage: "battery.100percent")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SnoreContinuousReportHero: View {
    let session: SnoreSession

    private var timeFormat: Date.FormatStyle {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return session.endTime.timeIntervalSince(session.startTime) < 120 ? format.second(.twoDigits) : format
    }

    private var peakLoudness: String {
        session.events.max(by: { $0.loudnessBucket < $1.loudnessBucket })?.estimatedLoudnessText ?? "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("鼾声分析")
                .font(.appSystem(size: 28, weight: .bold, design: .rounded))
            Label {
                Text("\(session.date.formatted(.dateTime.year().month().day()))  \(session.startTime.formatted(timeFormat)) 至 \(session.endTime.formatted(timeFormat))")
            } icon: {
                Image(systemName: "clock")
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 7)

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("鼾声评分")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(.secondary)
                    Text("\(session.snoreScore)")
                        .font(.appSystem(size: 84, weight: .heavy))
                        .foregroundStyle(SnorePalette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.severity.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(SnorePalette.color(for: session.severity))
                    Text("根据整晚声音事件、持续时间与分布综合评定")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 25)

            HStack(alignment: .top, spacing: 0) {
                SnoreContinuousMetric(title: "鼾声事件", value: "\(session.eventCount)", unit: "次")
                SnoreContinuousMetric(title: "鼾声时长", value: durationText(session.snoreDurationMinutes))
                SnoreContinuousMetric(title: "峰值强度", value: peakLoudness)
            }
            .padding(.top, 22)

            Divider().padding(.vertical, 24)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                SnoreContinuousMetric(title: "鼾声占比", value: percentText(session.snorePercentage))
                SnoreContinuousMetric(title: "每小时频率", value: oneDecimal(session.eventsPerHour), unit: "次")
                SnoreContinuousMetric(title: "最长单次", value: secondsText(session.longestEventDuration))
                SnoreContinuousMetric(title: "睡眠时长", value: minutesText(session.sleepDurationMinutes))
            }
        }
        .padding(.bottom, 28)
        .accessibilityElement(children: .combine)
    }
}

private struct SnoreContinuousMetric: View {
    let title: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 12))
                .foregroundStyle(SnorePalette.muted)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 23, weight: .bold))
                    .foregroundStyle(SnorePalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SnoreContinuousReportDivider: View {
    var body: some View {
        Divider().overlay(SnorePalette.separator)
    }
}

private struct SnoreResultHero: View {
    let session: SnoreSession
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("鼾声评分").font(Theme.Typography.captionBold).foregroundStyle(.secondary)
                    Text("\(session.snoreScore)")
                        .font(.appSystem(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(SnorePalette.color(for: session.severity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text(session.severity.title).font(Theme.Typography.bodyBold).foregroundStyle(SnorePalette.color(for: session.severity))
                    Text("\(durationText(session.snoreDurationMinutes)) · \(session.eventCount) 次").font(Theme.Typography.caption).foregroundStyle(.secondary)
                    Text("约占睡眠 \(percentText(session.snorePercentage))").font(Theme.Typography.caption).foregroundStyle(.tertiary)
                }
            }
            Text("根据夜间声音特征、持续时间和分布综合评定").font(Theme.Typography.caption).foregroundStyle(.secondary)
        }
        .snoreCard()
        .accessibilityElement(children: .combine)
    }
}

private struct SnoreMetricGrid: View {
    @Environment(\.snoreSurfaceStyle) private var surfaceStyle
    let metrics: [(String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.0).font(Theme.Typography.captionBold).foregroundStyle(.secondary)
                    Text(metric.1)
                        .font(.appSystem(size: surfaceStyle == .continuous ? 22 : 16, weight: .bold))
                        .foregroundStyle(SnorePalette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(surfaceStyle == .continuous ? 0 : 14)
                .frame(maxWidth: .infinity, minHeight: surfaceStyle == .continuous ? 64 : 76, alignment: .leading)
                .background {
                    if surfaceStyle == .card {
                        RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                            .fill(SnorePalette.inset)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SnoreTimelineView: View {
    @Environment(\.snoreSurfaceStyle) private var surfaceStyle
    let session: SnoreSession
    let compact: Bool
    @State private var selectedDate: Date?

    private var timelineDomain: ClosedRange<Date> {
        session.startTime...max(session.endTime, session.startTime.addingTimeInterval(1))
    }

    private var axisDates: [Date] {
        let start = timelineDomain.lowerBound
        let end = timelineDomain.upperBound
        return [start, start.addingTimeInterval(end.timeIntervalSince(start) / 2), end]
    }

    private var axisTimeFormat: Date.FormatStyle {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return timelineDomain.upperBound.timeIntervalSince(timelineDomain.lowerBound) < 120
            ? format.second(.twoDigits)
            : format
    }

    private var selectedEvent: SnoreEvent? {
        guard let selectedDate else { return nil }
        return session.events.min(by: { abs($0.startTime.timeIntervalSince(selectedDate)) < abs($1.startTime.timeIntervalSince(selectedDate)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if surfaceStyle == .card {
                HStack {
                    Text("音频时间线").font(Theme.Typography.cardTitle)
                    Spacer()
                    Text("\(session.eventCount) 个事件").font(Theme.Typography.captionBold).foregroundStyle(SnorePalette.amber)
                }
            }
            Chart(session.events) { event in
                RuleMark(
                    x: .value("开始", event.startTime),
                    yStart: .value("基线", 0),
                    yEnd: .value("相对强度", min(12, max(1, event.loudnessBucket)))
                )
                .foregroundStyle(SnorePalette.color(for: event.severity))
                .lineStyle(StrokeStyle(lineWidth: compact ? 1.7 : 2.5, lineCap: .round))
                if !compact, let selectedEvent, selectedEvent.id == event.id {
                    RuleMark(x: .value("选择", event.startTime)).foregroundStyle(.secondary).lineStyle(.init(lineWidth: 1, dash: [3]))
                }
            }
            .chartXScale(domain: timelineDomain, range: .plotDimension(startPadding: 4, endPadding: 4))
            .chartYScale(domain: 0...12)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: axisDates) {
                    AxisValueLabel(format: axisTimeFormat)
                        .font(.appSystem(size: 10, weight: .medium))
                        .foregroundStyle(SnorePalette.muted)
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(alignment: .bottom) {
                        Rectangle().fill(SnorePalette.separator).frame(height: 1)
                    }
                    .clipped()
            }
            .frame(height: compact ? 86 : 112)
            .chartXSelection(value: $selectedDate)

            if !compact {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(SnoreSeverity.allCases, id: \.self) { severity in
                        HStack(spacing: 4) {
                            Circle().fill(SnorePalette.color(for: severity)).frame(width: 6, height: 6)
                            Text(severity.title).font(Theme.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            }

            if !compact, let event = selectedEvent {
                HStack {
                    Text(event.startTime.formatted(date: .omitted, time: .shortened)).font(Theme.Typography.captionBold)
                    Text(event.severity.title).font(Theme.Typography.caption).foregroundStyle(SnorePalette.color(for: event.severity))
                    Spacer()
                    Text(event.estimatedLoudnessText).font(Theme.Typography.caption).foregroundStyle(.secondary)
                }.padding(10).background(SnorePalette.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            } else if let conclusion = timelineConclusion(session) {
                Text(conclusion).font(Theme.Typography.caption).foregroundStyle(.secondary)
            }
        }.snoreCard()
    }
}

private struct SnoreSeverityView: View {
    @Environment(\.snoreSurfaceStyle) private var surfaceStyle
    let session: SnoreSession
    let showExplanation: () -> Void
    private var dimensions: [SnoreRadarDimension] {
        [
            .init(label: "频次", value: min(100, Int(session.eventsPerHour * 8))),
            .init(label: "负荷", value: min(100, Int(session.snoreDurationMinutes * 4))),
            .init(label: "响度", value: min(100, session.peakLoudnessBucket * 8)),
            .init(label: "规律", value: session.regularityScore ?? 0),
            .init(label: "间隔", value: min(100, Int((session.averageIntervalSeconds ?? 0) / 2)))
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if surfaceStyle == .card {
                        Text("复合严重度").font(Theme.Typography.cardTitle)
                    }
                    Text("综合频次、负荷、响度、规律与事件间隔").font(Theme.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(max(0, 100 - session.snoreScore))")
                    .font(.appSystem(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(SnorePalette.coral)
            }
            SnoreRadarChart(dimensions: dimensions)
                .frame(height: 250)
            Button("了解评分方式", action: showExplanation).font(Theme.Typography.captionBold)
        }.snoreCard()
    }
}

private struct SnoreRadarDimension: Identifiable {
    let label: String
    let value: Int
    var id: String { label }
}

private struct SnoreRadarChart: View {
    let dimensions: [SnoreRadarDimension]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.34
            ZStack {
                Canvas { context, _ in
                    for level in 1...4 {
                        let scale = CGFloat(level) / 4
                        context.stroke(polygon(center: center, radius: radius * scale, count: dimensions.count), with: .color(SnorePalette.separator), lineWidth: 1)
                    }
                    for index in dimensions.indices {
                        var spoke = Path()
                        spoke.move(to: center)
                        spoke.addLine(to: point(center: center, radius: radius, index: index, count: dimensions.count))
                        context.stroke(spoke, with: .color(SnorePalette.separator), lineWidth: 1)
                    }
                    var valuePath = Path()
                    for (index, dimension) in dimensions.enumerated() {
                        let scaledRadius = radius * CGFloat(max(0, min(100, dimension.value))) / 100
                        let vertex = point(center: center, radius: scaledRadius, index: index, count: dimensions.count)
                        index == 0 ? valuePath.move(to: vertex) : valuePath.addLine(to: vertex)
                    }
                    valuePath.closeSubpath()
                    context.fill(valuePath, with: .color(SnorePalette.accent.opacity(0.23)))
                    context.stroke(valuePath, with: .color(SnorePalette.accent), lineWidth: 2.2)
                    for (index, dimension) in dimensions.enumerated() {
                        let scaledRadius = radius * CGFloat(max(0, min(100, dimension.value))) / 100
                        let vertex = point(center: center, radius: scaledRadius, index: index, count: dimensions.count)
                        context.fill(Path(ellipseIn: CGRect(x: vertex.x - 3.5, y: vertex.y - 3.5, width: 7, height: 7)), with: .color(SnorePalette.accent))
                    }
                }

                ForEach(Array(dimensions.enumerated()), id: \.element.id) { index, dimension in
                    let labelPoint = point(center: center, radius: radius + 24, index: index, count: dimensions.count)
                    VStack(spacing: 1) {
                        Text(dimension.label).font(Theme.Typography.caption)
                        Text("\(dimension.value)%").font(Theme.Typography.captionBold).foregroundStyle(SnorePalette.accent)
                    }
                    .position(labelPoint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dimensions.map { "\($0.label) \($0.value)%" }.joined(separator: "，"))
    }

    private func polygon(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        var path = Path()
        for index in 0..<count {
            let vertex = point(center: center, radius: radius, index: index, count: count)
            index == 0 ? path.move(to: vertex) : path.addLine(to: vertex)
        }
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(max(count, 1))
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

private struct SnoreLoadChart: View {
    struct Point: Identifiable { let date: Date; let load: Double; var id: Date { date } }
    let session: SnoreSession
    private var timeFormat: Date.FormatStyle {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return session.endTime.timeIntervalSince(session.startTime) < 120 ? format.second(.twoDigits) : format
    }
    private var points: [Point] {
        var load = 0.0
        var result = [Point(date: session.startTime, load: 0)]
        for event in session.events.sorted(by: { $0.startTime < $1.startTime }) {
            if event.startTime > (result.last?.date ?? session.startTime) {
                result.append(Point(date: event.startTime, load: load))
            }
            load += max(0, event.duration) * Double(max(event.loudnessBucket, 1))
            let end = max(event.endTime, event.startTime)
            if end == result.last?.date {
                result[result.count - 1] = Point(date: end, load: load)
            } else {
                result.append(Point(date: end, load: load))
            }
        }
        if session.endTime > (result.last?.date ?? session.startTime) {
            result.append(Point(date: session.endTime, load: load))
        }
        return result
    }
    var body: some View {
        let chartPoints = points
        VStack(alignment: .leading, spacing: 12) {
            Text("鼾声负荷").font(Theme.Typography.cardTitle)
            Text("观察鼾声在整晚睡眠中的累计情况").font(Theme.Typography.caption).foregroundStyle(.secondary)
            Chart(chartPoints) { point in
                AreaMark(x: .value("时间", point.date), y: .value("负荷", point.load)).foregroundStyle(SnorePalette.accent.opacity(0.16))
                LineMark(x: .value("时间", point.date), y: .value("负荷", point.load))
                    .foregroundStyle(SnorePalette.accent)
                    .lineStyle(.init(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                if chartPoints.count <= 8 {
                    PointMark(x: .value("时间", point.date), y: .value("负荷", point.load))
                        .foregroundStyle(SnorePalette.accent)
                        .symbolSize(12)
                }
            }
            .chartYScale(domain: 0...max(1, (chartPoints.last?.load ?? 0) * 1.15))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel(format: timeFormat)
                        .font(.appSystem(size: 10))
                        .foregroundStyle(SnorePalette.muted)
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(alignment: .bottom) {
                        Rectangle().fill(SnorePalette.separator).frame(height: 1)
                    }
                    .clipped()
            }
            .frame(height: 130)
            SnoreMetricGrid(metrics: [("鼾声时长", durationText(session.snoreDurationMinutes)), ("占睡眠", percentText(session.snorePercentage)), ("平均单次", secondsText(session.averageEventDuration)), ("最长单次", secondsText(session.longestEventDuration))])
        }.snoreCard()
    }
}

private struct SnoreNightDistributionView: View {
    @Environment(\.snoreSurfaceStyle) private var surfaceStyle
    let session: SnoreSession
    private struct Bucket: Identifiable {
        let index: Int
        let label: String
        let count: Int
        var id: Int { index }
    }
    private var buckets: [Bucket] {
        let duration = max(1, session.endTime.timeIntervalSince(session.startTime))
        return session.histogram.enumerated().map { index, count in
            let date = session.startTime.addingTimeInterval(duration * Double(index) / 6)
            let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            let label = date.formatted(duration < 120 ? format.second(.twoDigits) : format)
            return Bucket(index: index, label: label, count: count)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if surfaceStyle == .card {
                Text("整夜分布").font(Theme.Typography.cardTitle)
            }
            Chart(buckets) { bucket in
                BarMark(x: .value("时段", bucket.index), y: .value("事件", bucket.count), width: .fixed(14))
                    .foregroundStyle(SnorePalette.accent.gradient)
                    .cornerRadius(3)
            }
            .chartXScale(domain: -0.5...Double(max(5, buckets.count - 1)) + 0.5)
            .chartYScale(domain: 0...max(3, (buckets.map(\.count).max() ?? 0) + 1))
            .chartXAxis {
                AxisMarks(values: buckets.enumerated().compactMap { index, bucket in
                    index == 0 || index == buckets.count / 2 || index == buckets.count - 1 ? bucket.index : nil
                }) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self), buckets.indices.contains(index) {
                            Text(buckets[index].label)
                                .font(.appSystem(size: 9, weight: .medium))
                                .foregroundStyle(SnorePalette.muted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(SnorePalette.separator)
                    AxisValueLabel().font(.appSystem(size: 9)).foregroundStyle(SnorePalette.muted)
                }
            }
            .frame(height: 150)
            if let busiest = buckets.max(by: { $0.count < $1.count }), busiest.count >= 2 {
                Text("鼾声在 \(busiest.label) 附近更集中。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }.snoreCard()
    }
}

private struct SnoreLoudnessView: View {
    let session: SnoreSession
    private var counts: [(SnoreSeverity, Int)] { SnoreSeverity.allCases.map { severity in (severity, session.events.filter { $0.severity == severity }.count) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("响度分布").font(Theme.Typography.cardTitle)
            Text("当前设备未做声压级校准，因此用相对等级表达，不将特征桶误标为 dB。").font(Theme.Typography.caption).foregroundStyle(.secondary)
            // 单条横向分布条：按事件占比分段着色，替代多行进度条。
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(counts, id: \.0) { severity, count in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(count > 0 ? SnorePalette.color(for: severity) : SnorePalette.separator)
                            .frame(width: max(0, proxy.size.width * CGFloat(count) / CGFloat(max(session.eventCount, 1)) - 1))
                    }
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(counts.map { "\($0.0.title) \($0.1) 个" }.joined(separator: "，")))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 7) {
                ForEach(counts, id: \.0) { severity, count in
                    HStack(spacing: 4) {
                        Circle().fill(count > 0 ? SnorePalette.color(for: severity) : SnorePalette.separator).frame(width: 6, height: 6)
                        Text("\(severity.title) \(count)").font(Theme.Typography.caption).foregroundStyle(.secondary)
                    }
                }
            }
            let loudest = counts.filter { $0.0 == .loud || $0.0 == .noticeable }.map(\.1).reduce(0, +)
            if session.eventCount > 0 {
                Text("偏响事件占比 \(percentText(Double(loudest) / Double(session.eventCount) * 100))").font(Theme.Typography.captionBold)
            }
        }.snoreCard()
    }
}

private struct SnoreRhythmView: View {
    struct Gap: Identifiable { let index: Int; let seconds: Double; var id: Int { index } }
    let session: SnoreSession
    private var gaps: [Gap] { zip(session.events, session.events.dropFirst()).enumerated().map { index, pair in Gap(index: index, seconds: min(300, max(0, pair.1.startTime.timeIntervalSince(pair.0.endTime)))) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("鼾声节律").font(Theme.Typography.cardTitle)
            HStack { rhythmMetric("规律程度", regularityText(session.regularityScore)); rhythmMetric("平均间隔", secondsText(session.averageIntervalSeconds)); rhythmMetric("成组鼾声平均", groupAverageText(session)) }
            if gaps.count >= 2 {
                Chart(gaps) { gap in LineMark(x: .value("事件", gap.index), y: .value("间隔", gap.seconds)).foregroundStyle(SnorePalette.blue); PointMark(x: .value("事件", gap.index), y: .value("间隔", gap.seconds)).foregroundStyle(SnorePalette.blue) }
                    .chartXAxis(.hidden).chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(SnorePalette.separator); AxisValueLabel().font(Theme.Typography.caption) } }.frame(height: 105)
            } else { Text("事件数量不足，暂时无法判断节律。").font(Theme.Typography.caption).foregroundStyle(.secondary) }
        }.snoreCard()
    }
    private func rhythmMetric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(Theme.Typography.caption).foregroundStyle(.secondary); Text(value).font(Theme.Typography.captionBold).lineLimit(1).minimumScaleFactor(0.75) }.frame(maxWidth: .infinity, alignment: .leading) }
}

private struct SnorePatternCard: View {
    let pattern: SnorePattern
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "waveform.path").font(.title2).foregroundStyle(SnorePalette.accent).frame(width: 42, height: 42).background(SnorePalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) { Text("今晚的鼾声模式").font(Theme.Typography.captionBold).foregroundStyle(.secondary); Text(pattern.title).font(Theme.Typography.cardTitle); Text(pattern.explanation).font(Theme.Typography.caption).foregroundStyle(.secondary) }
        }.snoreCard()
    }
}

private struct SnoreBreathingSignalCard: View {
    private struct GapPoint: Identifiable {
        let date: Date
        let seconds: Double
        var id: Date { date }
    }

    let session: SnoreSession
    let showEvidence: () -> Void
    private var gaps: [GapPoint] {
        zip(session.events, session.events.dropFirst()).compactMap { previous, next in
            let seconds = max(0, next.startTime.timeIntervalSince(previous.endTime))
            guard seconds <= 300 else { return nil }
            return GapPoint(date: next.startTime, seconds: seconds)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("静默间隔观察").font(Theme.Typography.cardTitle); Spacer(); Text("仅供参考").font(Theme.Typography.captionBold).foregroundStyle(SnorePalette.amber) }
            if gaps.isEmpty {
                Text("事件数量不足，暂时无法绘制间隔分布。").font(Theme.Typography.bodyMedium)
            } else {
                Chart {
                    ForEach(gaps) { gap in
                        PointMark(x: .value("时间", gap.date), y: .value("间隔", gap.seconds))
                            .foregroundStyle(gap.seconds >= 10 ? SnorePalette.coral : SnorePalette.accent)
                            .symbolSize(gap.seconds >= 10 ? 28 : 16)
                    }
                    RuleMark(y: .value("观察线", 10))
                        .foregroundStyle(SnorePalette.amber.opacity(0.75))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                }
                .chartXScale(domain: session.startTime...session.endTime)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel(format: .dateTime.hour().minute()).font(Theme.Typography.caption) } }
                .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(SnorePalette.separator); AxisValueLabel().font(Theme.Typography.caption) } }
                .frame(height: 130)
            }
            Text("红点仅表示相邻鼾声事件之间超过 10 秒的间隔，不等同于呼吸暂停，也不用于计算医学风险。").font(Theme.Typography.caption).foregroundStyle(.secondary)
            Text("该结果不能用于诊断睡眠呼吸暂停等疾病。如长期出现明显异常或伴随白天嗜睡等症状，请考虑咨询专业医疗人员。").font(Theme.Typography.caption).foregroundStyle(.secondary)
            Button("数据来源与分析依据", action: showEvidence).font(Theme.Typography.captionBold)
        }.snoreCard()
    }
}

private struct SnoreSleepStageChart: View {
    let correlations: [SnoreStageCorrelation]
    /// 与睡眠详情页头卡一致的阶段色（Deep/Core/REM/Awake）。
    private func stageColor(_ stage: String) -> Color {
        switch stage {
        case "深睡": Color(hex: "77CFDA")
        case "浅睡": Color(hex: "A9D990")
        case "REM": Color(hex: "F2D15D")
        default: Color(hex: "AEB6C7")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("与睡眠阶段的关系").font(Theme.Typography.cardTitle)
            if correlations.isEmpty {
                Label("暂无睡眠阶段关联数据", systemImage: "bed.double")
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(.secondary)
                Text("需要带起止时间的 HealthKit 睡眠阶段样本，才能把鼾声事件归入具体阶段。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(correlations) { item in
                    BarMark(x: .value("阶段", item.stage), y: .value("事件", item.eventCount))
                        .foregroundStyle(stageColor(item.stage).gradient)
                        .cornerRadius(5)
                }
                .chartXAxis { AxisMarks { AxisValueLabel().font(Theme.Typography.caption) } }
                .chartYAxis(.hidden)
                .frame(height: 130)
                if let conclusion = stageConclusion(correlations) {
                    Text(conclusion).font(Theme.Typography.caption).foregroundStyle(.secondary)
                }
                Text("柱高为阶段内鼾声事件数；阶段时长仅用于计算发生率，不会被当作鼾声量。").font(Theme.Typography.caption).foregroundStyle(.secondary)
            }
        }.snoreCard()
    }

    /// 只有阶段覆盖足够时长且事件数量有区分度时才生成结论，避免把噪声说成规律。
    private func stageConclusion(_ items: [SnoreStageCorrelation]) -> String? {
        let withRate = items.compactMap { item -> (String, Double)? in
            guard let rate = item.eventsPerHour else { return nil }
            return (item.stage, rate)
        }
        guard withRate.count >= 2 else { return nil }
        let top = withRate.max(by: { $0.1 < $1.1 })
        let total = withRate.reduce(0) { $0 + $1.1 }
        guard let top, top.1 > 0, top.1 / max(total, 0.001) >= 0.4 else { return nil }
        return String(localized: "今晚鼾声更多出现在\(top.0)阶段。")
    }
}

private struct SnoreAudioEvidenceView: View {
    let session: SnoreSession
    let openEvents: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("代表性鼾声").font(Theme.Typography.cardTitle)
            if session.hasAudio {
                ForEach(session.events.filter { $0.audioURL != nil }.prefix(5)) { event in SnoreEventRow(event: event) }
                Button("查看全部录音片段", action: openEvents).font(Theme.Typography.captionBold)
            } else {
                Label("暂无录音片段", systemImage: "waveform.slash")
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(.secondary)
                Text("当前隐私模式只保存设备端分析特征与事件摘要，没有保留可播放的原始声音。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                Button("查看全部鼾声事件", action: openEvents).font(Theme.Typography.captionBold)
            }
        }.snoreCard()
    }
}

private struct SnoreEventsView: View {
    let session: SnoreSession?
    @State private var filter: SnoreEventFilter = .all
    var body: some View {
        List {
            if let session {
                Section { Picker("筛选", selection: $filter) { ForEach(SnoreEventFilter.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                let events = session.events.filter { filter.severity == nil || $0.severity == filter.severity }
                if events.isEmpty { SnoreInlineState(symbol: "line.3.horizontal.decrease.circle", title: "没有符合条件的事件", message: "可以切换筛选条件查看其他事件。") }
                ForEach(events) { SnoreEventRow(event: $0) }
            } else { SnoreInlineState(symbol: "waveform", title: "暂无鼾声事件", message: "检测结果生成后，会按发生时间列在这里。") }
        }
        .scrollContentBackground(.hidden).background(SnorePalette.background)
        .navigationTitle("鼾声记录").navigationBarTitleDisplayMode(.inline)
    }
}

private enum SnoreEventFilter: String, CaseIterable, Identifiable {
    case all, mild, noticeable, loud
    var id: String { rawValue }
    var title: String { switch self { case .all: String(localized: "全部"); case .mild: String(localized: "轻微"); case .noticeable: String(localized: "明显"); case .loud: String(localized: "响亮") } }
    var severity: SnoreSeverity? { switch self { case .all: nil; case .mild: .mild; case .noticeable: .noticeable; case .loud: .loud } }
}

private struct SnoreEventRow: View {
    let event: SnoreEvent
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    // 波形进度在播放期间由 CADisplayLink 式定时器刷新，离开行时回收。
    @State private var progressTimer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(SnorePalette.color(for: event.severity)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.startTime.formatted(date: .omitted, time: .shortened)).font(Theme.Typography.bodyBold)
                Text("\(secondsText(event.duration)) · \(event.severity.title) · \(event.estimatedLoudnessText)").font(Theme.Typography.caption).foregroundStyle(.secondary)
                SnoreWaveformView(values: event.waveform, progress: playbackProgress)
            }
            if event.audioURL != nil {
                Button(action: togglePlayback) { Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title2) }
                    .accessibilityLabel(isPlaying ? "暂停录音" : "播放录音")
            } else { Text("无录音").font(Theme.Typography.caption).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 6)
        .onDisappear { stopPlaybackProgressTracking() }
    }

    private func togglePlayback() {
        guard let url = event.audioURL else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
            stopPlaybackProgressTracking()
            return
        }
        if player == nil { player = try? AVAudioPlayer(contentsOf: url) }
        player?.play()
        isPlaying = player?.isPlaying == true
        if isPlaying { startPlaybackProgressTracking() }
    }

    private func startPlaybackProgressTracking() {
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                guard let player, player.isPlaying else {
                    isPlaying = false
                    stopPlaybackProgressTracking()
                    return
                }
                playbackProgress = min(1, player.currentTime / max(player.duration, 0.01))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopPlaybackProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
        playbackProgress = 0
    }
}

private struct SnoreWaveformView: View {
    let values: [Double]
    let progress: Double
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule().fill(Double(index) / Double(max(values.count - 1, 1)) <= progress ? SnorePalette.accent : Color.secondary.opacity(0.25)).frame(width: 2, height: 4 + 18 * value)
            }
        }.frame(height: 24).accessibilityHidden(true)
    }
}

private struct SnoreTrendView: View {
    let points: [SnoreTrendPoint]
    @State private var dayRange = 7
    @State private var metric: SnoreTrendMetric = .score
    private var visible: [SnoreTrendPoint] { Array(points.suffix(dayRange)) }
    private var visibleAverage: Double {
        let values = visible.map(metric.value)
        return values.reduce(0, +) / Double(max(values.count, 1))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("周期", selection: $dayRange) { Text("7天").tag(7); Text("30天").tag(30); Text("90天").tag(90) }.pickerStyle(.segmented)
                Picker("指标", selection: $metric) { ForEach(SnoreTrendMetric.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                if visible.count >= 2 {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(metric.title).font(Theme.Typography.cardTitle)
                            Spacer()
                            Text("监测覆盖 \(visible.count)/\(dayRange) 晚").font(Theme.Typography.caption).foregroundStyle(.secondary)
                        }
                        Chart {
                            ForEach(visible) { point in
                                BarMark(x: .value("日期", point.date, unit: .day), y: .value(metric.title, metric.value(point)))
                                    .foregroundStyle(SnorePalette.blue.gradient)
                                    .cornerRadius(4)
                            }
                            RuleMark(y: .value("平均", visibleAverage))
                                .foregroundStyle(SnorePalette.accent)
                                .lineStyle(.init(lineWidth: 2, dash: [6, 4]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("平均 \(visibleAverage.formatted(.number.precision(.fractionLength(1))))")
                                        .font(Theme.Typography.captionBold)
                                        .foregroundStyle(SnorePalette.accent)
                                }
                        }
                        .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(SnorePalette.separator); AxisValueLabel().font(Theme.Typography.caption) } }
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(7, visible.count))) { AxisValueLabel(format: .dateTime.month().day()).font(Theme.Typography.caption) } }
                        .frame(height: 220)
                        SnoreTrendSummary(points: visible, metric: metric)
                    }.snoreCard()
                } else { SnoreInlineState(symbol: "chart.line.uptrend.xyaxis", title: "趋势仍在积累", message: "至少需要 2 晚鼾声记录，才能比较变化方向。") }
            }.padding(HealthDetailDesignSystem.pageHorizontalPadding)
        }.background(SnorePalette.background.ignoresSafeArea()).navigationTitle("鼾声趋势").navigationBarTitleDisplayMode(.inline)
    }
}

private enum SnoreTrendMetric: String, CaseIterable, Identifiable {
    case score, duration, frequency, loudness
    var id: String { rawValue }
    var title: String { switch self { case .score: String(localized: "评分"); case .duration: String(localized: "时长"); case .frequency: String(localized: "事件/小时"); case .loudness: String(localized: "相对峰值") } }
    func value(_ point: SnoreTrendPoint) -> Double { switch self { case .score: point.score; case .duration: point.durationMinutes; case .frequency: point.eventsPerHour; case .loudness: point.peakLoudnessBucket } }
}

private struct SnoreTrendSummary: View {
    let points: [SnoreTrendPoint]
    let metric: SnoreTrendMetric
    var body: some View {
        let values = points.map(metric.value)
        let average = values.reduce(0, +) / Double(max(values.count, 1))
        VStack(alignment: .leading, spacing: 5) {
            Text("当前周期平均").font(Theme.Typography.caption).foregroundStyle(.secondary)
            Text(average.formatted(.number.precision(.fractionLength(metric == .score ? 0 : 1)))).font(.appSystem(size: 30, weight: .black, design: .rounded))
            if points.count >= 4 {
                let split = points.count / 2
                let previous = Array(values.prefix(split)); let current = Array(values.suffix(points.count - split))
                let previousAverage = previous.reduce(0, +) / Double(previous.count); let currentAverage = current.reduce(0, +) / Double(current.count)
                if previousAverage > 0 { Text("较前半周期 \(((currentAverage - previousAverage) / previousAverage).formatted(.percent.precision(.fractionLength(0))))").font(Theme.Typography.captionBold).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct SnoreTrendPreview: View {
    let points: [SnoreTrendPoint]
    private var average: Double {
        points.map(\.score).reduce(0, +) / Double(max(points.count, 1))
    }
    var body: some View {
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("每日评分", systemImage: "chart.bar.fill").foregroundStyle(SnorePalette.blue)
                    Spacer()
                    Text("平均 \(average.formatted(.number.precision(.fractionLength(1))))")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(SnorePalette.accent)
                }
                .font(Theme.Typography.captionBold)
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("日期", point.date, unit: .day), y: .value("评分", point.score))
                            .foregroundStyle(SnorePalette.blue.gradient)
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("平均", average))
                        .foregroundStyle(SnorePalette.accent)
                        .lineStyle(.init(lineWidth: 2, dash: [5, 4]))
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(7, points.count))) { AxisValueLabel(format: .dateTime.day()).font(Theme.Typography.caption) } }
                .frame(height: 130)
            }
            .snoreCard()
        } else { SnoreInlineState(symbol: "chart.bar", title: "趋势仍在积累", message: "再完成一晚检测后即可开始比较。") }
    }
}

private struct SnoreHistoryView: View {
    let sessions: [SnoreSession]
    let open: (String) -> Void
    private var grouped: [(String, [SnoreSession])] {
        Dictionary(grouping: sessions) { $0.date.formatted(.dateTime.year().month(.wide)) }.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }.sorted { ($0.1.first?.date ?? .distantPast) > ($1.1.first?.date ?? .distantPast) }
    }
    var body: some View {
        List {
            if sessions.isEmpty { SnoreInlineState(symbol: "clock.arrow.circlepath", title: "暂无历史记录", message: "完成夜间检测后，历史结果会按日期显示。") }
            ForEach(grouped, id: \.0) { group in Section(group.0) { ForEach(group.1) { session in Button { open(session.id) } label: { SnoreHistoryRow(session: session) }.buttonStyle(.plain) } } }
        }.scrollContentBackground(.hidden).background(SnorePalette.background).navigationTitle("鼾声历史").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SnoreHistoryRow: View {
    let session: SnoreSession
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(SnorePalette.color(for: session.severity)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.date.formatted(.dateTime.month().day().weekday())).font(Theme.Typography.bodyBold)
                Text("\(session.eventCount) 次鼾声 · \(durationText(session.snoreDurationMinutes))").font(Theme.Typography.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.snoreScore)").font(.appSystem(size: 22, weight: .black, design: .rounded)).foregroundStyle(SnorePalette.color(for: session.severity))
                Text(session.severity.title).font(Theme.Typography.caption).foregroundStyle(SnorePalette.color(for: session.severity))
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}

private struct SnoreStatusCard: View {
    let symbol: String
    let title: String
    let message: String
    var showsProgress = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: symbol).font(.title2).foregroundStyle(SnorePalette.accent); Text(title).font(Theme.Typography.sectionTitle); Spacer(); if showsProgress { ProgressView().tint(SnorePalette.accent) } }
            Text(message).font(Theme.Typography.bodyMedium).foregroundStyle(.secondary)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(SnorePalette.accent) }
        }.snoreCard()
    }
}

private struct SnoreInlineState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.appSystem(size: 25, weight: .semibold))
                .foregroundStyle(SnorePalette.accent)
                .frame(width: 48, height: 48)
                .background(SnorePalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.inset))
            Text(title).font(Theme.Typography.cardTitle).foregroundStyle(.primary)
            Text(message).font(Theme.Typography.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(SnorePalette.surface, in: RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous)
                .stroke(SnorePalette.separator, lineWidth: 1)
        }
    }
}

private struct SnoreSectionHeading: View {
    let title: String
    let action: String
    let perform: () -> Void
    var body: some View { HStack { Text(title).font(Theme.Typography.sectionTitle); Spacer(); Button(action, action: perform).font(Theme.Typography.captionBold) } }
}

private struct SnoreEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("数据来源").font(Theme.Typography.sectionTitle)
                    Text("鼾声事件来自 iPhone 麦克风在设备端提取的声音特征；睡眠阶段来自 HealthKit。原始音频不会上传。")
                    Text("分析边界").font(Theme.Typography.sectionTitle)
                    Text("现有摘要不足以可靠识别长静默与鼾声恢复序列，所以页面不会输出呼吸异常次数或医学风险等级。")
                    Text("健康提示").font(Theme.Typography.sectionTitle)
                    Text("鼾声分析仅用于个人健康趋势参考，不属于医疗诊断。如存在持续响亮鼾声、目击呼吸中断或明显日间嗜睡，请咨询专业医疗人员。")
                }.font(Theme.Typography.body).padding(20)
            }.background(SnorePalette.background).navigationTitle("数据依据").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private enum SnoreSurfaceStyle: Equatable {
    case card
    case continuous
}

private struct SnoreSurfaceStyleKey: EnvironmentKey {
    static let defaultValue = SnoreSurfaceStyle.card
}

private extension EnvironmentValues {
    var snoreSurfaceStyle: SnoreSurfaceStyle {
        get { self[SnoreSurfaceStyleKey.self] }
        set { self[SnoreSurfaceStyleKey.self] = newValue }
    }
}

private struct SnoreCardStyle: ViewModifier {
    @Environment(\.snoreSurfaceStyle) private var surfaceStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch surfaceStyle {
        case .card:
            content
                .padding(Theme.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SnorePalette.surface, in: RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: TodayVisualTokens.cardCornerRadius, style: .continuous).stroke(SnorePalette.separator, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.025), radius: 10, y: 4)
        case .continuous:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension View {
    /// 与今日页一致的浅色卡片表面、描边和轻投影。
    func snoreCard() -> some View {
        modifier(SnoreCardStyle())
    }
}

private func durationText(_ minutes: Double) -> String {
    guard minutes.isFinite, minutes >= 0 else { return "--" }
    return minutes < 1 ? secondsText(minutes * 60) : String(localized: "\(Int(minutes.rounded())) 分钟")
}
private func elapsedClock(_ interval: TimeInterval) -> String { let seconds = max(0, Int(interval)); return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) }
private func minutesText(_ minutes: Int) -> String { let hours = minutes / 60; let rest = minutes % 60; return hours > 0 ? String(localized: "\(hours) 小时 \(rest) 分") : String(localized: "\(rest) 分钟") }
private func secondsText(_ seconds: Double?) -> String { guard let seconds else { return "--" }; return String(localized: "\(seconds.formatted(.number.precision(.fractionLength(seconds < 10 ? 1 : 0)))) 秒") }
private func oneDecimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
private func percentText(_ value: Double) -> String { (value / 100).formatted(.percent.precision(.fractionLength(0))) }
private func groupAverageText(_ session: SnoreSession) -> String { guard let average = session.averageEventsPerGroup else { return "--" }; return String(localized: "成组鼾声平均 \(average.formatted(.number.precision(.fractionLength(1)))) 次/组") }
private func regularityText(_ score: Int?) -> String { guard let score else { return "--" }; switch score { case 72...: return String(localized: "较规律"); case 42..<72: return String(localized: "有波动"); default: return String(localized: "较不规律") } }
private func timelineConclusion(_ session: SnoreSession) -> String? { guard let busiest = session.histogram.enumerated().max(by: { $0.element < $1.element }), busiest.element >= 2 else { return nil }; let total = session.endTime.timeIntervalSince(session.startTime); let start = session.startTime.addingTimeInterval(total / 6 * Double(busiest.offset)); let end = session.startTime.addingTimeInterval(total / 6 * Double(busiest.offset + 1)); return String(localized: "鼾声主要集中在 \(start.formatted(date: .omitted, time: .shortened))～\(end.formatted(date: .omitted, time: .shortened))") }
private func distributionConclusion(_ values: [(String, Int)]) -> String? { guard let max = values.max(by: { $0.1 < $1.1 }), max.1 >= 2 else { return nil }; return String(localized: "今晚鼾声在\(max.0)更集中。") }
