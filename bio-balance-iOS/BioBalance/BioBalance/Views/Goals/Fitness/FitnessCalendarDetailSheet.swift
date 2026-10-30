/// FitnessCalendarDayDetailSheet 由健身日历点击日期调用，作为「当日训练详情」编辑弹层。
/// 负责编辑当天训练模式、时长、距离、强度、心情备注并同步到 HealthKit。

import SwiftUI
import Charts

struct FitnessCalendarDayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: ActionDayDetailModel
    var onShareChanged: ((Bool) -> Void)? = nil
    var onSaveFitnessDetail: ((FitnessDayDetailDraft) -> Void)? = nil
    /// 提供训练深度分析（爬升/分段）的数据源；为 nil 时报告页不渲染分析区块。
    var analysisSource: FitnessCalendarViewModel? = nil

    @State private var selectedMode: FitnessCheckinMode?
    @State private var workoutMinutes: Double
    @State private var workoutDistanceKm: Double
    @State private var effort: WorkoutEffortLevel?
    @State private var mood: DailyMoodLevel?
    @State private var note: String
    @State private var isShared: Bool
    @State private var syncToHealthApp = true
    @State private var isConfirmingDiscard = false

    init(
        model: ActionDayDetailModel,
        analysisSource: FitnessCalendarViewModel? = nil,
        onShareChanged: ((Bool) -> Void)? = nil,
        onSaveFitnessDetail: ((FitnessDayDetailDraft) -> Void)? = nil
    ) {
        self.model = model
        self.analysisSource = analysisSource
        self.onShareChanged = onShareChanged
        self.onSaveFitnessDetail = onSaveFitnessDetail
        _selectedMode = State(initialValue: model.checkinMode)
        _workoutMinutes = State(initialValue: Double(model.manualWorkoutMinutes))
        _workoutDistanceKm = State(initialValue: model.manualWorkoutDistanceKm)
        _effort = State(initialValue: model.manualWorkoutEffort)
        _mood = State(initialValue: model.dailyMood)
        _note = State(initialValue: model.fitnessNote)
        _isShared = State(initialValue: model.isShared)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "F9F9FD"), Color(hex: "F3F4FA")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        detailSections
                    }
                    .padding(Theme.Layout.padding)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeSheet()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.appSystem(size: 15, weight: .bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveAndDismiss()
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .disabled(!canSave)
                }
            }
        }
        .confirmationDialog("放弃未保存的修改？", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) {
                dismiss()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("当前选择的状态、时长、距离、心情或备注还没有保存。")
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    @ViewBuilder
    private var detailSections: some View {
        if let swimmingReport = model.swimmingReport {
            SwimmingWorkoutReportView(report: swimmingReport)
            // Pool swimming already has a dedicated report; avoid a second HealthKit sample pass.
            // Open water keeps the generic analyzer for GPS route and segment data.
            if swimmingReport.location == .openWater, let analysisSource {
                WorkoutDeepAnalysisContainer(
                        viewModel: analysisSource,
                        date: model.date,
                        accent: Color(hex: "168FA3"),
                        preferredWorkoutID: swimmingReport.workoutID
                    )
            }
            editingCard
        } else if let reportKind = model.workoutReportKind {
            WorkoutActivityReportView(model: model, kind: reportKind)
            if let analysisSource {
                WorkoutDeepAnalysisContainer(viewModel: analysisSource, date: model.date, accent: Color(hex: reportKind.accentHex))
            }
            editingCard
        } else {
            // 编辑区提到最前，用户打开即可快速记录
            editingCard
            headerCard
            statsCard
            trainingAnalysisCard
            trendCard
            achievementCard
        }
    }

    private var canSave: Bool {
        selectedMode != nil
    }

    private var hasUnsavedChanges: Bool {
        selectedMode != model.checkinMode ||
        Int(workoutMinutes.rounded()) != model.manualWorkoutMinutes ||
        abs(workoutDistanceKm - model.manualWorkoutDistanceKm) > 0.01 ||
        effort != model.manualWorkoutEffort ||
        mood != model.dailyMood ||
        note != model.fitnessNote ||
        isShared != model.isShared
    }

    private func closeSheet() {
        if hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func saveAndDismiss() {
        guard canSave else { return }
        onShareChanged?(isShared)
        onSaveFitnessDetail?(
            FitnessDayDetailDraft(
                mode: selectedMode,
                minutes: Int(workoutMinutes.rounded()),
                distanceKm: selectedMode == .workout ? (workoutDistanceKm * 10).rounded() / 10 : 0,
                effort: effort,
                mood: mood,
                note: note,
                isShared: isShared,
                syncToHealthApp: syncToHealthApp
            )
        )
        dismiss()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 10) {
                Text(primaryWorkoutValue)
                    .font(.appSystem(size: 68, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Image(systemName: workoutSymbol)
                    .font(.appSystem(size: 34, weight: .black))
                    .foregroundColor(Color(hex: "34C759"))
                    .padding(.bottom, 10)
                Spacer(minLength: 0)
                Text("KCAL")
                    .font(.appSystem(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary.opacity(0.13))
                    .padding(.bottom, 7)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.workoutTitle)
                    .font(.appSystem(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "17215A"))
                Label(model.title, systemImage: "clock")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if !model.statusTags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.statusTags.prefix(3)) { tag in
                        statusTag(tag)
                    }
                }
            }

            Text(model.movementSummary)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var primaryWorkoutValue: String {
        if let energy = model.statItems.first(where: { $0.title == "消耗" })?.valueText,
           let value = energy.split(separator: " ").first,
           value != "暂无" {
            return String(value)
        }
        return "--"
    }

    private var workoutSymbol: String {
        let title = model.workoutTitle
        if title.contains("走路") || title.contains("步行") || title.contains("徒步") { return "figure.walk" }
        if title.contains("骑行") { return "figure.outdoor.cycle" }
        if title.contains("游泳") { return "figure.pool.swim" }
        if title.contains("力量") { return "dumbbell.fill" }
        if title.contains("瑜伽") { return "figure.yoga" }
        return "figure.run"
    }

    private var achievementCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.appSystem(size: 24, weight: .black))
                .foregroundColor(Color(hex: "F5B82E"))

            VStack(alignment: .leading, spacing: 5) {
                Text(achievementTitle)
                    .font(.appSystem(size: 21, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "C18A13"))
                Text(achievementDetail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color(hex: "FFF8E8"), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var achievementTitle: String {
        if let count = model.workoutCount, count > 1 { return String(localized: "🏆 当天第 \(count) 次运动") }
        if model.distanceKilometers != nil { return String(localized: "🏆 完成一次有距离记录的运动") }
        return String(localized: "🏆 完成今天的运动记录")
    }

    private var achievementDetail: String {
        if model.workoutTitle.contains("户外") {
            return String(localized: "已从 HealthKit 识别为\(model.workoutTitle)，距离、配速和消耗均使用设备写入的真实记录。")
        }
        return String(localized: "这次\(model.workoutTitle)已经进入你的训练节奏，继续积累记录后可获得更完整的趋势对比。")
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("运动数据")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if model.isShared {
                    Label("已共享给好友", systemImage: "person.2.fill")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "2AA7A1"))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                metricGridItem(title: "动态消耗", value: statValue(named: "消耗"))
                metricGridItem(title: "运动时间", value: statValue(named: "训练"))
                metricGridItem(title: "距离", value: model.distanceKilometers.map { String(format: "%.2f km", $0) } ?? "暂无")
                metricGridItem(title: "平均配速", value: model.averagePaceText.map { "\($0)/km" } ?? "暂无")
                metricGridItem(title: "训练负荷", value: model.trainingLoadScore.map { "\($0) 分" } ?? "暂无")
                metricGridItem(title: "恢复状态", value: model.recoveryScore.map { "\($0) 分" } ?? "暂无")
            }

            if model.checkedInAt != nil || model.isShared {
                VStack(alignment: .leading, spacing: 8) {
                    if let checkedInAt = model.checkedInAt {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(Color(hex: "73C8E8"))
                            Text("记录时间：\(checkedInAt.formatted(date: .omitted, time: .shortened))")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    if model.isShared {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(Color(hex: "2AA7A1"))
                            Text("这一天的摘要已经共享给好友，但备注和原始流水仍然只对你自己可见。")
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.Colors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func statValue(named title: String) -> String {
        model.statItems.first(where: { $0.title == title })?.valueText ?? "暂无"
    }

    private func metricGridItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "17215A"))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(title)
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("运动趋势")
                Spacer()
                Text("近 7 天 · 分钟")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            if model.trendPoints.isEmpty {
                Text("这段时间还没有足够的训练样本")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(Theme.Colors.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                Chart(model.trendPoints) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("分钟", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "58CC6A").opacity(0.25), Color(hex: "58CC6A").opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("分钟", point.value)
                    )
                    .foregroundStyle(Color(hex: "58CC6A"))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("分钟", point.value)
                    )
                    .foregroundStyle(Color(hex: "58CC6A"))
                    .symbolSize(28)
                }
                .frame(height: 180)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(model.trendPoints.count, 5))) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Theme.Colors.textTertiary.opacity(0.12))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text("\(Int(minutes))")
                            }
                        }
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .padding(14)
                .background(Theme.Colors.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            Text(model.insightText)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var trainingAnalysisCard: some View {
        if model.trainingLoadScore != nil || model.recoveryScore != nil || model.distanceKilometers != nil || model.workoutCount != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("运动强度")
                    Spacer()
                    Text(intensityLabel)
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: intensityTintHex))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(hex: intensityTintHex).opacity(0.12), in: Capsule())
                }
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                VStack(spacing: 13) {
                    intensityZoneRow(title: "高强活动", range: "负荷 76–100", tintHex: "F27B49", threshold: 76)
                    intensityZoneRow(title: "中等强度", range: "负荷 51–75", tintHex: "F5B82E", threshold: 51)
                    intensityZoneRow(title: "轻量活动", range: "负荷 26–50", tintHex: "6DB7F2", threshold: 26)
                    intensityZoneRow(title: "恢复活动", range: "负荷 0–25", tintHex: "9BCFDA", threshold: 0)
                }

                HStack(spacing: 10) {
                    analysisValue(
                        title: "训练次数",
                        value: model.workoutCount.map { "\($0) 次" } ?? "--",
                        symbol: "figure.run",
                        tintHex: "7A8CF0"
                    )
                    analysisValue(
                        title: "距离",
                        value: model.distanceKilometers.map { String(format: "%.2f km", $0) } ?? "--",
                        symbol: "location.fill",
                        tintHex: "73C8E8"
                    )
                    analysisValue(
                        title: "平均配速",
                        value: model.averagePaceText.map { "\($0)/km" } ?? "--",
                        symbol: "speedometer",
                        tintHex: "2AA7A1"
                    )
                }

                Text("强度等级依据当前训练负荷展示；没有设备原始心率时，不生成平均心率、最大心率或心率区间。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private var intensityLabel: String {
        let load = model.trainingLoadScore ?? 0
        if load >= 76 { return String(localized: "高强") }
        if load >= 51 { return String(localized: "中等") }
        if load >= 26 { return String(localized: "轻量") }
        return String(localized: "恢复")
    }

    private var intensityTintHex: String {
        let load = model.trainingLoadScore ?? 0
        if load >= 76 { return "F27B49" }
        if load >= 51 { return "F5B82E" }
        if load >= 26 { return "6DB7F2" }
        return "9BCFDA"
    }

    private func intensityZoneRow(title: String, range: String, tintHex: String, threshold: Int) -> some View {
        let load = model.trainingLoadScore ?? 0
        let isCurrent: Bool
        switch threshold {
        case 76: isCurrent = load >= 76
        case 51: isCurrent = load >= 51 && load < 76
        case 26: isCurrent = load >= 26 && load < 51
        default: isCurrent = load < 26
        }

        return HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: tintHex))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "17215A"))
                Text(range)
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Spacer()
            Capsule()
                .fill(Color(hex: tintHex).opacity(isCurrent ? 0.95 : 0.14))
                .frame(width: isCurrent ? 104 : 38, height: 12)
            Text(isCurrent ? "当前" : "")
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: tintHex))
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func analysisProgressRow(title: String, value: Int, tintHex: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("\(value) 分")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: tintHex))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: tintHex).opacity(0.12))
                    Capsule()
                        .fill(Color(hex: tintHex))
                        .frame(width: proxy.size.width * min(max(CGFloat(value) / 100, 0), 1))
                }
            }
            .frame(height: 7)
        }
    }

    private func analysisValue(title: String, value: String, symbol: String, tintHex: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.appSystem(size: 13, weight: .black))
                .foregroundColor(Color(hex: tintHex))
            Text(value)
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(12)
        .background(Color(hex: tintHex).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var editingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.checkinMode == nil ? "选择当天状态" : "补充记录")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Toggle("共享", isOn: $isShared)
                    .labelsHidden()
                    .tint(Color(hex: "58CC6A"))
            }

            // 训练/恢复/休息 三选一
            HStack(spacing: 10) {
                ForEach(FitnessCheckinMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        if mode != .workout {
                            effort = nil
                            workoutMinutes = 0
                            workoutDistanceKm = 0
                            note = ""
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.symbol)
                            Text(mode.shortTitle)
                        }
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(selectedMode == mode ? .white : Color(hex: mode.tintHex))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selectedMode == mode ? Color(hex: mode.tintHex) : Color(hex: mode.tintHex).opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedMode == .workout {
                // 训练时长 — 紧凑 stepper + 快捷
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("训练时长")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                        HStack(spacing: 10) {
                            Button { workoutMinutes = max(0, workoutMinutes - 5) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.appSystem(size: 22))
                                    .foregroundColor(Color(hex: "58CC6A"))
                            }
                            Text("\(Int(workoutMinutes.rounded())) 分")
                                .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(hex: "58CC6A"))
                                .frame(minWidth: 60)
                            Button { workoutMinutes = min(180, workoutMinutes + 5) } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.appSystem(size: 22))
                                    .foregroundColor(Color(hex: "58CC6A"))
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach([15, 30, 45, 60], id: \.self) { preset in
                            Button {
                                workoutMinutes = Double(preset)
                            } label: {
                                Text("\(preset)分")
                                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Int(workoutMinutes.rounded()) == preset ? .white : Color(hex: "58CC6A"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(
                                        Int(workoutMinutes.rounded()) == preset
                                            ? Color(hex: "58CC6A")
                                            : Color(hex: "58CC6A").opacity(0.10),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 运动距离 — 紧凑 stepper
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("运动距离")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                        HStack(spacing: 10) {
                            Button { workoutDistanceKm = max(0, workoutDistanceKm - 0.5) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.appSystem(size: 22))
                                    .foregroundColor(Color(hex: "73C8E8"))
                            }
                            Text(workoutDistanceKm > 0 ? String(format: "%.1f km", workoutDistanceKm) : "不记录")
                                .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(hex: "73C8E8"))
                                .frame(minWidth: 70)
                            Button { workoutDistanceKm = min(30, workoutDistanceKm + 0.5) } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.appSystem(size: 22))
                                    .foregroundColor(Color(hex: "73C8E8"))
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { preset in
                            Button {
                                workoutDistanceKm = preset
                            } label: {
                                Text(String(format: "%.0fkm", preset))
                                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(abs(workoutDistanceKm - preset) < 0.01 ? .white : Color(hex: "73C8E8"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(
                                        abs(workoutDistanceKm - preset) < 0.01
                                            ? Color(hex: "73C8E8")
                                            : Color(hex: "73C8E8").opacity(0.10),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 强度 — 单行
                HStack(spacing: 8) {
                    Text("强度")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    ForEach(WorkoutEffortLevel.allCases) { level in
                        Button {
                            effort = level
                        } label: {
                            Text(level.title)
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(effort == level ? .white : Color(hex: level.tintHex))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(effort == level ? Color(hex: level.tintHex) : Color(hex: level.tintHex).opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 备注 — 紧凑
                VStack(alignment: .leading, spacing: 6) {
                    Text("备注")
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    TextField("例如：跑步 30 分钟", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .padding(12)
                        .frame(minHeight: 64, alignment: .topLeading)
                        .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else if selectedMode != nil {
                Text("恢复和休息日会保留节奏连续，但不会计入训练连续。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // 当日心情 — 紧凑单行
            moodSection

            if selectedMode != nil {
                Toggle(isOn: $syncToHealthApp) {
                    Text("同步到健康 App")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                }
                .tint(Color(hex: "58CC6A"))
            }
        }
        .padding(20)
        .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// 当日心情：紧凑单行，再次点击同一档可取消。
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当日心情")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if let mood {
                    Text("\(mood.emoji) \(mood.title)")
                        .font(.appSystem(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: mood.tintHex))
                }
            }

            HStack(spacing: 6) {
                ForEach(DailyMoodLevel.allCases) { level in
                    Button {
                        mood = mood == level ? nil : level
                    } label: {
                        VStack(spacing: 2) {
                            Text(level.emoji)
                                .font(.appSystem(size: 18))
                            Text(level.title)
                                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(mood == level ? .white : Color(hex: level.tintHex))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            mood == level ? Color(hex: level.tintHex) : Color(hex: level.tintHex).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statusTag(_ tag: ActionDayDetailStatusTag) -> some View {
        Text(tag.title)
            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: tag.tintHex))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(hex: tag.tintHex).opacity(0.12), in: Capsule())
    }
}
