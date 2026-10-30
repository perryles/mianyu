/// SleepStressAnalyticsView 由报告页「深入分析 → 睡眠与压力」入口调用。
/// 负责按天展示睡眠与压力的同步变化趋势。

import SwiftUI
import Charts

/// 负责展示睡眠记录、恢复分析以及睡眠与其他指标的关联。
struct SleepStressAnalyticsView: View {
    @State private var days: Int = 14
    @State private var data: [DailySleepStressAnalytics] = []
    @State private var isLoading = false
    /// 加载代际：快速切换天数时只允许最新一次加载写入结果。
    @State private var loadID = UUID()

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: HealthDetailDesignSystem.sectionSpacing) {
                    Picker("天数", selection: $days) {
                        Text("7天").tag(7)
                        Text("14天").tag(14)
                        Text("30天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.black)

                    if isLoading {
                        ProgressView()
                            .tint(Theme.Colors.textPrimary)
                            .padding(.top, 24)
                    } else if data.isEmpty {
                        Text("暂无分析数据")
                            .font(Theme.Typography.cardTitle)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.top, 24)
                    } else {
                        sleepScoreCard
                        stressHrvCard
                        factorsCard
                    }
                }
                .padding(.horizontal, HealthDetailDesignSystem.pageHorizontalPadding)
                .padding(.top, HealthDetailDesignSystem.pageTopPadding)
                .padding(.bottom, Theme.Spacing.section)
            }
        }
        .navigationTitle("睡眠关联")
        .onAppear { load() }
        .onChange(of: days) { load() }
    }

    private var sleepScoreCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("睡眠得分与效率")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)

            Chart(sortedData) { item in
                if let score = item.sleep_score, let date = parseDate(item.date) {
                    LineMark(
                        x: .value("日期", date),
                        y: .value("睡眠得分", score)
                    )
                    .foregroundStyle(Color(hex: "5E5CE6"))
                    .interpolationMethod(.catmullRom)
                }

                if let eff = item.efficiency, let date = parseDate(item.date) {
                    LineMark(
                        x: .value("日期", date),
                        y: .value("效率", eff * 100.0)
                    )
                    .foregroundStyle(Theme.Colors.mintGreen)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 240)
        }
        .healthDetailSurface()
    }

    private var stressHrvCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("压力与 HRV")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)

            Chart(sortedData) { item in
                if let stress = item.avg_stress, let date = parseDate(item.date) {
                    LineMark(
                        x: .value("日期", date),
                        y: .value("平均压力", stress)
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)

            Chart(sortedData) { item in
                if let hrv = item.avg_hrv, let date = parseDate(item.date) {
                    LineMark(
                        x: .value("日期", date),
                        y: .value("平均HRV", hrv)
                    )
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 180)
        }
        .healthDetailSurface()
    }

    private var factorsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("关键影响因素")
                .font(Theme.Typography.cardTitle)
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(sortedData.suffix(7)) { item in
                HStack(spacing: Theme.Spacing.small) {
                    Text(item.date)
                        .font(.appSystem(.caption, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Spacer()

                    if let waterRate = item.water_completion_rate {
                        Text("喝水 \(localizedPercentRatio(waterRate))")
                            .font(.appSystem(.caption, design: .default))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    if let caffeine = item.caffeine_remained_mg {
                        Text("咖啡因 \(Int(caffeine))mg")
                            .font(.appSystem(.caption, design: .default))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    if let emo = item.top_emotion {
                        Text(emotionTitle(emo))
                            .font(.appSystem(.caption, design: .default))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .healthDetailSurface()
    }

    private var sortedData: [DailySleepStressAnalytics] {
        data.sorted { $0.date < $1.date }
    }

    private func load() {
        let id = UUID()
        loadID = id
        isLoading = true
        Task {
            // 本地优先：无自建后端，睡眠压力分析以本机数据为准。
            guard !Task.isCancelled, id == loadID else { return }
            data = []
            isLoading = false
        }
    }

    private func parseDate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }

    private func emotionTitle(_ code: String) -> String {
        switch code {
        case "happy": "开心"
        case "neutral": "平静"
        case "tired": "疲惫"
        case "anxious": "焦虑"
        case "sad": "悲伤"
        default: code
        }
    }
}
