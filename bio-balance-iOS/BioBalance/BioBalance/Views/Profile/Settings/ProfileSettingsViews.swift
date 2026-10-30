/// GoalsSettingsView 由设置页目标入口调用，作为「目标设置」页面。
/// 负责以滚轮选择器管理每日步数、活动时间与睡眠时长目标。

import SwiftUI

// MARK: - 目标设置

private enum GoalPickerKind: String, Identifiable {
    case steps
    case activeMinutes
    case sleep

    var id: String { rawValue }
}

/// Goals视图 由上级页面或路由调用，作为个人资料模块里的界面或内容组件。
/// 负责个人资料与账户入口。
struct GoalsSettingsView: View {
    @AppStorage("daily_steps_goal") private var dailyStepsGoal: Int = 8000
    @AppStorage("daily_active_minutes_goal") private var dailyActiveMinutesGoal: Int = 30
    @AppStorage("daily_sleep_goal_hours") private var sleepHoursGoal: Double = 8
    @State private var activePicker: GoalPickerKind?
    @State private var showingResetConfirmation = false

    var body: some View {
        ProfileWellnessSettingsPage(
            title: "目标",
            eyebrow: "你的健康节奏",
            headline: "把目标定在\n每天够得着的地方",
            summary: "从活动到恢复，选择适合当下生活的节奏。每次调整都会自动同步到 Widget 和 Watch。",
            symbol: "target",
            tint: Theme.Colors.mintGreen,
            background: Color(hex: "E6F7ED"),
            items: [
                .init(value: dailyStepsGoal.formatted(), label: "每日步数"),
                .init(value: "\(dailyActiveMinutesGoal) 分", label: "活动"),
                .init(value: String(format: String(localized: "%.1f 小时"), sleepHoursGoal), label: "睡眠")
            ]
        ) {
            ProfileSection(title: "目标数值") {
                ProfileWheelSelectorRow(
                    title: "每日步数",
                    subtitle: "点按后用滚轮选择步数目标。",
                    icon: "shoeprints.fill",
                    tint: Theme.Colors.mintGreen,
                    valueText: "\(dailyStepsGoal) 步"
                ) {
                    activePicker = .steps
                }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "活动时间",
                    subtitle: "点按后用滚轮选择活动时长。",
                    icon: "figure.walk",
                    tint: Theme.Colors.accentBlue,
                    valueText: "\(dailyActiveMinutesGoal) 分钟"
                ) {
                    activePicker = .activeMinutes
                }
            }

            ProfileSection(title: "恢复目标") {
                ProfileWheelSelectorRow(
                    title: "睡眠目标",
                    subtitle: "点按后用滚轮选择睡眠时长。",
                    icon: "bed.double.fill",
                    tint: Color(hex: "7D8BFF"),
                    valueText: String(format: String(localized: "%.1f 小时"), sleepHoursGoal)
                ) {
                    activePicker = .sleep
                }
            }

            ProfileSection(title: "目标状态") {
                ProfileStatusRow(
                    title: "当前目标强度",
                    subtitle: goalIntensityDetail,
                    icon: "gauge.with.dots.needle.50percent",
                    value: goalIntensityTitle,
                    tint: goalIntensityTint
                )
                Divider().padding(.leading, 70)
                ProfileStatusRow(
                    title: "设备同步",
                    subtitle: "修改后会同步到手机、Widget 和 Watch 的目标进度。",
                    icon: "applewatch.and.arrow.forward",
                    value: "自动",
                    tint: Theme.Colors.mintGreen
                )
            }

            ProfileHintCard(
                title: "设置建议",
                rows: [
                    .init(label: "每日步数", value: "多数人可先从 6,000–10,000 步开始，再按实际活动能力调整。"),
                    .init(label: "活动时间", value: "建议先选择大多数日子都能完成的分钟数，连续性比单日冲高更重要。"),
                    .init(label: "睡眠目标", value: "成年人通常可从 7–9 小时区间选择，并结合自身恢复感受调整。")
                ]
            )

            ProfileSection(title: "重置") {
                ProfileActionRow(
                    title: "恢复默认目标",
                    subtitle: "恢复为 8,000 步、30 分钟活动和 8 小时睡眠。",
                    icon: "arrow.counterclockwise",
                    tint: Theme.Colors.accentRed
                ) {
                    showingResetConfirmation = true
                }
            }
        }
        .onAppear(perform: syncGoalPreferences)
        .onChange(of: dailyStepsGoal) { _, _ in syncGoalPreferences() }
        .onChange(of: dailyActiveMinutesGoal) { _, _ in syncGoalPreferences() }
        .onChange(of: sleepHoursGoal) { _, _ in syncGoalPreferences() }
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .steps:
                ProfileWheelPickerSheet(
                    title: "每日步数",
                    subtitle: "滚动选择一个你大多数日子都能稳定完成的档位。",
                    valueSummary: "\(dailyStepsGoal) 步",
                    tint: Theme.Colors.mintGreen,
                    options: stepGoalOptions,
                    selection: $dailyStepsGoal
                )
            case .activeMinutes:
                ProfileWheelPickerSheet(
                    title: "活动时间",
                    subtitle: "滚动选择每天计划留给活动或训练的分钟数。",
                    valueSummary: "\(dailyActiveMinutesGoal) 分钟",
                    tint: Theme.Colors.accentBlue,
                    options: activeMinuteOptions,
                    selection: $dailyActiveMinutesGoal
                )
            case .sleep:
                ProfileWheelPickerSheet(
                    title: "睡眠目标",
                    subtitle: "滚动选择你希望长期维持的睡眠时长。",
                    valueSummary: String(format: String(localized: "%.1f 小时"), sleepHoursGoal),
                    tint: Color(hex: "7D8BFF"),
                    options: sleepGoalOptions,
                    selection: $sleepHoursGoal
                )
            }
        }
        .confirmationDialog("恢复默认目标？", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("恢复默认值", role: .destructive) { resetGoals() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会覆盖当前步数、活动和睡眠目标，并同步到 Widget 与 Watch。")
        }
    }

    private enum GoalIntensity {
        case light
        case balanced
        case advanced
    }

    private var goalIntensity: GoalIntensity {
        let score = Double(dailyStepsGoal) / 8_000 + Double(dailyActiveMinutesGoal) / 30 + sleepHoursGoal / 8
        switch score / 3 {
        case ..<0.8: return .light
        case 0.8...1.2: return .balanced
        default: return .advanced
        }
    }

    private var goalIntensityTitle: String {
        switch goalIntensity {
        case .light: return String(localized: "轻量")
        case .balanced: return String(localized: "均衡")
        case .advanced: return String(localized: "进阶")
        }
    }

    private var goalIntensityDetail: String {
        switch goalIntensity {
        case .light: return String(localized: "目标更容易开始，适合先建立稳定完成节奏。")
        case .advanced: return String(localized: "目标高于默认水平，请结合近期状态逐步推进。")
        case .balanced: return String(localized: "当前目标接近默认建议，兼顾活动与恢复。")
        }
    }

    private var goalIntensityTint: Color {
        switch goalIntensity {
        case .light: return Theme.Colors.accentBlue
        case .advanced: return Color(hex: "FFB340")
        case .balanced: return Theme.Colors.mintGreen
        }
    }

    private func resetGoals() {
        dailyStepsGoal = 8_000
        dailyActiveMinutesGoal = 30
        sleepHoursGoal = 8
        syncGoalPreferences()
    }

    private func syncGoalPreferences() {
        AppGroupManager.shared.save(value: dailyStepsGoal, forKey: AppGroupManager.Keys.stepsGoal)
        AppGroupManager.shared.save(value: dailyActiveMinutesGoal, forKey: AppGroupManager.Keys.exerciseMinutesGoal)
        AppGroupManager.shared.save(value: Int(sleepHoursGoal * 60.0), forKey: AppGroupManager.Keys.sleepGoalMinutes)
    }

    private var stepGoalOptions: [ProfileWheelPickerOption<Int>] {
        Array(stride(from: 1000, through: 30000, by: 500)).map {
            ProfileWheelPickerOption(value: $0, label: "\($0) 步")
        }
    }

    private var activeMinuteOptions: [ProfileWheelPickerOption<Int>] {
        Array(stride(from: 5, through: 180, by: 5)).map {
            ProfileWheelPickerOption(value: $0, label: "\($0) 分钟")
        }
    }

    private var sleepGoalOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 4.0, through: 10.0, by: 0.5)).map {
            ProfileWheelPickerOption(value: $0, label: String(format: String(localized: "%.1f 小时"), $0))
        }
    }
}

// MARK: - 阈值设置

private enum ThresholdPickerKind: String, Identifiable {
    case highHeartRate
    case lowHeartRate
    case stress

    var id: String { rawValue }
}

/// Threshold视图 由上级页面或路由调用，作为个人资料模块里的界面或内容组件。
/// 负责个人资料与账户入口。
struct ThresholdSettingsView: View {
    @AppStorage("high_heart_rate_alert_bpm") private var highHeartRateBpm: Double = 120
    @AppStorage("low_heart_rate_alert_bpm") private var lowHeartRateBpm: Double = 45
    @AppStorage("stress_alert_threshold") private var stressAlertThreshold: Double = 75
    @State private var activePicker: ThresholdPickerKind?
    @State private var showingResetConfirmation = false

    var body: some View {
        ProfileWellnessSettingsPage(
            title: "阈值",
            eyebrow: "守护身体信号",
            headline: "只在值得留意时\n轻轻提醒你",
            summary: "根据自己的基础状态设定提醒边界。阈值用于辅助关注变化，不代替医疗判断。",
            symbol: "waveform.path.ecg",
            tint: Theme.Colors.accentRed,
            background: Color(hex: "FFECE8"),
            items: [
                .init(value: "\(Int(lowHeartRateBpm))", label: "心率下限"),
                .init(value: "\(Int(highHeartRateBpm))", label: "心率上限"),
                .init(value: "\(Int(stressAlertThreshold))%", label: "压力阈值")
            ]
        ) {
            ProfileSection(title: "提醒阈值") {
                ProfileWheelSelectorRow(
                    title: "高心率提醒",
                    subtitle: "点按后用滚轮调整高心率阈值。",
                    icon: "heart.fill",
                    tint: Theme.Colors.accentRed,
                    valueText: "\(Int(highHeartRateBpm)) 次/分"
                ) {
                    activePicker = .highHeartRate
                }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "低心率提醒",
                    subtitle: "点按后用滚轮调整低心率阈值。",
                    icon: "heart.text.square.fill",
                    tint: Theme.Colors.accentBlue,
                    valueText: "\(Int(lowHeartRateBpm)) 次/分"
                ) {
                    activePicker = .lowHeartRate
                }
                Divider().padding(.leading, 74)
                ProfileWheelSelectorRow(
                    title: "压力警报阈值",
                    subtitle: "点按后用滚轮调整压力阈值。",
                    icon: "brain.head.profile",
                    tint: Color(hex: "FFB340"),
                    valueText: "\(Int(stressAlertThreshold))%"
                ) {
                    activePicker = .stress
                }
            }

            ProfileSection(title: "触发状态") {
                ProfileStatusRow(
                    title: "心率提醒区间",
                    subtitle: "低于下限或高于上限时，系统会结合可用数据判断是否提醒。",
                    icon: "waveform.path.ecg",
                    value: "\(Int(lowHeartRateBpm))–\(Int(highHeartRateBpm))",
                    tint: heartRateRangeIsValid ? Theme.Colors.mintGreen : Theme.Colors.accentRed
                )
                Divider().padding(.leading, 70)
                ProfileStatusRow(
                    title: "压力提醒灵敏度",
                    subtitle: stressSensitivityDetail,
                    icon: "brain.head.profile",
                    value: stressSensitivityTitle,
                    tint: Color(hex: "FFB340")
                )
            }

            ProfileHintCard(
                title: "阈值说明",
                rows: [
                    .init(label: "心率", value: "阈值只决定提醒触发范围，不用于诊断；运动、药物和个体差异都会影响读数。"),
                    .init(label: "压力", value: "数值越低越容易触发提醒，数值越高则只在压力更明显时提醒。"),
                    .init(label: "异常情况", value: "如出现持续胸痛、呼吸困难、晕厥或明显不适，请及时寻求专业医疗帮助。")
                ]
            )

            ProfileSection(title: "重置") {
                ProfileActionRow(
                    title: "恢复默认阈值",
                    subtitle: "恢复为高心率 120、低心率 45、压力 75%。",
                    icon: "arrow.counterclockwise",
                    tint: Theme.Colors.accentRed
                ) {
                    showingResetConfirmation = true
                }
            }
        }
        .onAppear {
            normalizeHeartRateRange()
        }
        .onChange(of: highHeartRateBpm) { _, _ in normalizeHeartRateRange(changedHighValue: true) }
        .onChange(of: lowHeartRateBpm) { _, _ in normalizeHeartRateRange(changedHighValue: false) }
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .highHeartRate:
                ProfileWheelPickerSheet(
                    title: "高心率提醒",
                    subtitle: "滚动选择当心率升到什么程度时，系统应该开始提醒你留意。",
                    valueSummary: "\(Int(highHeartRateBpm)) 次/分",
                    tint: Theme.Colors.accentRed,
                    options: highHeartRateOptions,
                    selection: $highHeartRateBpm
                )
            case .lowHeartRate:
                ProfileWheelPickerSheet(
                    title: "低心率提醒",
                    subtitle: "滚动选择当心率低到什么程度时，系统应该开始提醒你留意。",
                    valueSummary: "\(Int(lowHeartRateBpm)) 次/分",
                    tint: Theme.Colors.accentBlue,
                    options: lowHeartRateOptions,
                    selection: $lowHeartRateBpm
                )
            case .stress:
                ProfileWheelPickerSheet(
                    title: "压力警报阈值",
                    subtitle: "滚动选择压力分数达到多少时，系统更适合提醒你暂停一下。",
                    valueSummary: "\(Int(stressAlertThreshold))%",
                    tint: Color(hex: "FFB340"),
                    options: stressThresholdOptions,
                    selection: $stressAlertThreshold
                )
            }
        }
        .confirmationDialog("恢复默认阈值？", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("恢复默认值", role: .destructive) { resetThresholds() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会覆盖当前心率和压力提醒范围。")
        }
    }

    private var heartRateRangeIsValid: Bool { lowHeartRateBpm < highHeartRateBpm }

    private enum StressSensitivity {
        case sensitive
        case balanced
        case conservative
    }

    private var stressSensitivity: StressSensitivity {
        switch stressAlertThreshold {
        case ..<65: return .sensitive
        case 65..<82: return .balanced
        default: return .conservative
        }
    }

    private var stressSensitivityTitle: String {
        switch stressSensitivity {
        case .sensitive: return String(localized: "较灵敏")
        case .balanced: return String(localized: "均衡")
        case .conservative: return String(localized: "较保守")
        }
    }

    private var stressSensitivityDetail: String {
        switch stressSensitivity {
        case .sensitive: return String(localized: "较早提醒，适合希望主动打断压力累积的情况。")
        case .conservative: return String(localized: "仅在压力分数较高时提醒，可减少通知频率。")
        case .balanced: return String(localized: "提醒频率与压力强度之间保持平衡。")
        }
    }

    private func normalizeHeartRateRange(changedHighValue: Bool? = nil) {
        guard lowHeartRateBpm >= highHeartRateBpm else { return }
        if changedHighValue == false {
            highHeartRateBpm = min(200, lowHeartRateBpm + 10)
        } else {
            lowHeartRateBpm = max(30, highHeartRateBpm - 10)
        }
    }

    private func resetThresholds() {
        highHeartRateBpm = 120
        lowHeartRateBpm = 45
        stressAlertThreshold = 75
    }

    private var highHeartRateOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 100.0, through: 200.0, by: 1.0)).map {
            ProfileWheelPickerOption(value: $0, label: "\(Int($0)) 次/分")
        }
    }

    private var lowHeartRateOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 30.0, through: 60.0, by: 1.0)).map {
            ProfileWheelPickerOption(value: $0, label: "\(Int($0)) 次/分")
        }
    }

    private var stressThresholdOptions: [ProfileWheelPickerOption<Double>] {
        Array(stride(from: 50.0, through: 95.0, by: 1.0)).map {
            ProfileWheelPickerOption(value: $0, label: "\(Int($0))%")
        }
    }
}
