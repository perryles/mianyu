import SwiftUI

/// VitalityPeriodRecordView 由 ReproductiveHealthRecordView 嵌入，作为周期健康记录中的经期模式。
/// 负责展示日期切换、记录入口、月经预测提醒与周期校正；具体当天录入内容通过向上弹出的 PeriodSheetView 完成。
///
/// 页面先回答当前处于什么阶段，再提供今日记录、周期概览与月历回看。
struct VitalityPeriodRecordView: View {
    @Bindable var viewModel: PeriodViewModel
    private let isEmbedded: Bool
    private let reloadsOnAppear: Bool
    private let onStartPregnancy: (() -> Void)?
    @State private var showingRecordSheet = false
    @State private var recordSheetFocus: PeriodSheetView.FocusSection = .dayLog
    @State private var quickRecordFeedbackID = 0

    private let periodTint = Color(hex: "F46B5A")
    private let fertileTint = Color(hex: "42BE9B")
    private let inkTint = Color(hex: "35383F")
    private let lineTint = Color(hex: "DDE8E8")

    init(
        viewModel: PeriodViewModel,
        isEmbedded: Bool = false,
        reloadsOnAppear: Bool = true,
        onStartPregnancy: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isEmbedded = isEmbedded
        self.reloadsOnAppear = reloadsOnAppear
        self.onStartPregnancy = onStartPregnancy
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            periodBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    pageHeroSection
                    quickRecordCard
                    rhythmSummaryCard
                    monthCalendarCard

                    if let message = viewModel.errorMessage, !message.isEmpty {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "B85E54"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(hex: "FDECE7"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 80)
            }
        }
        .modifier(VitalityPeriodNavigationChrome(isEmbedded: isEmbedded))
        .toolbarBackground(.hidden, for: .navigationBar)
        .environment(\.locale, Locale.autoupdatingCurrent)
        .sensoryFeedback(.success, trigger: quickRecordFeedbackID)
        .onAppear {
            if reloadsOnAppear {
                viewModel.reload(days: 90)
                viewModel.selectLog(date: viewModel.selectedLogDate)
            }
        }
        .sheet(isPresented: $showingRecordSheet) {
            PeriodSheetView(viewModel: viewModel, focusSection: recordSheetFocus)
        }
    }

    private var pageHeroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label(todayDateText, systemImage: "calendar")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer(minLength: 8)

                startPregnancyButton
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.currentPhaseDisplayText)
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(heroAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(heroAccentColor.opacity(0.10), in: Capsule())

                    Text(heroTitle)
                        .font(.appSystem(size: 27, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(viewModel.currentCycleDayText)
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "667181"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VitalityPeriodHeroVisual(
                    phaseText: viewModel.currentPhaseDisplayText,
                    cycleDayText: viewModel.currentCycleDayText,
                    accent: heroAccentColor,
                    isLoading: viewModel.isLoading
                )
                .frame(width: 116, height: 116)
            }

            Label {
                Text(viewModel.phaseObservationSummary)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(heroAccentColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [heroBackgroundColor, Color(hex: "F2F7F5")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.94), lineWidth: 1)
        )
        .shadow(color: heroAccentColor.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    // MARK: 快速记录

    private var quickRecordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日记录")
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(inkTint)
                    Text(todayPeriodLog == nil ? "还没有今天的经期记录" : "今天已经在记录范围内")
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)

                Button {
                    openEditor(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
                } label: {
                    Label("补记过去", systemImage: "calendar.badge.plus")
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "A9466D"))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .background(periodTint.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    if isTodayMenstruating {
                        openEditor(for: Date())
                    } else {
                        performQuickRecord(.typical)
                    }
                } label: {
                    Label(isTodayMenstruating ? "修改今天" : "今天来了", systemImage: isTodayMenstruating ? "pencil" : "drop.fill")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(periodTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSubmitting)

                Button {
                    openEditor(for: Date(), focus: .symptoms)
                } label: {
                    Label("记录当前症状", systemImage: "waveform.path.ecg")
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "B53368"))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(periodTint.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .periodFlatCard(cornerRadius: 22)
    }

    // MARK: 节律概览

    private var rhythmSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                cardLabel("本月节律")
                Spacer()
                Text(learningState.title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "397BA0"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "E8F5FA"), in: Capsule())
            }

            HStack(spacing: 0) {
                summaryMetric(label: "现在", value: viewModel.currentPhaseDisplayText, tint: periodTint)
                summaryDivider
                summaryMetric(label: "下次", value: nextPeriodSummaryText, tint: Color(hex: "5A9DC1"))
                summaryDivider
                summaryMetric(label: "完整记录", value: "\(completedCycleCount) 个", tint: Color(hex: "8F67AE"))
            }

            cycleProgressBar

            HStack {
                Text("第1天")
                    .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                if let ovulationText = predictedOvulationText {
                    Text(ovulationText)
                        .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                Spacer()
                Text("第\(currentCycleLength)天")
                    .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Label(learningState.detail, systemImage: "checkmark.seal.fill")
                .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "4C8B78"))
        }
        .padding(16)
        .periodFlatCard()
    }

    private func summaryMetric(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Capsule().fill(tint).frame(width: 4, height: 13)
                Text(label)
                    .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Text(value)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(inkTint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle().fill(lineTint).frame(width: 1, height: 38).padding(.horizontal, 8)
    }

    private var completedCycleCount: Int {
        (viewModel.summary?.cycles ?? []).filter { $0.endDate != nil }.count
    }

    private var learningState: PeriodLearningState {
        PeriodLearningState(completedCycleCount: completedCycleCount)
    }

    private var nextPeriodSummaryText: String {
        guard learningState != .learning,
              let next = viewModel.summary?.predictions?.nextPeriodStart else { return "学习中" }
        return viewModel.displayDay(next)
    }

    private var cycleProgressBar: some View {
        let progress = cycleDayProgress
        let indicatorDiameter: CGFloat = 12

        return GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let filledWidth = PeriodProgressGeometry.filledWidth(
                progress: progress,
                availableWidth: availableWidth
            )
            let indicatorOffset = PeriodProgressGeometry.indicatorOffset(
                progress: progress,
                availableWidth: availableWidth,
                indicatorDiameter: indicatorDiameter
            )

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "F0F0F0"))
                    .frame(height: 6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [periodTint, Color(hex: "C63F78")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, filledWidth), height: 6)

                Circle()
                    .fill(Color.white)
                    .frame(width: indicatorDiameter, height: indicatorDiameter)
                    .overlay {
                        Circle()
                            .stroke(periodTint, lineWidth: 2)
                    }
                    .offset(x: indicatorOffset)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
    }

    private var cycleDayProgress: CGFloat {
        let cycleDay = currentCycleDayValue
        guard currentCycleLength > 0 else { return 0 }
        return CGFloat(cycleDay) / CGFloat(currentCycleLength)
    }

    private var currentCycleDayValue: Int {
        if let day = cycleDay(for: Date()) { return day }
        return 1
    }

    private var currentCycleLength: Int {
        guard let cycleLength = viewModel.summary?.predictions?.cycleLength,
              cycleLength > 0 else {
            return 28
        }
        return cycleLength
    }

    private var predictedOvulationText: String? {
        guard let cycleStart = viewModel.summary?.current?.startDate,
              let startDate = Self.dayFormatter.date(from: cycleStart) else { return nil }
        let calendar = Calendar.current
        guard let ovulationDate = calendar.date(byAdding: .day, value: 14, to: startDate) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return "排卵 \(formatter.string(from: ovulationDate))"
    }

    // MARK: 月历

    private var monthCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                cardLabel(currentMonthTitle)
                Spacer()
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            calendarGrid

            HStack(spacing: 12) {
                calendarLegendDot(color: periodTint.opacity(0.15), label: "经期")
                calendarLegendDot(color: fertileTint.opacity(0.12), label: "易孕期")
                calendarLegendDot(color: Color.clear, border: periodTint.opacity(0.25), label: "预测")
            }
        }
        .padding(16)
        .periodFlatCard()
    }

    @State private var calendarMonthAnchor: Date = Date()

    private var currentMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return "\(formatter.string(from: calendarMonthAnchor))周期日历"
    }

    private func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: value, to: calendarMonthAnchor) {
            calendarMonthAnchor = newDate
        }
    }

    private var calendarGrid: some View {
        let weeks = calendarWeeks(for: calendarMonthAnchor)
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { dow in
                    Text(dow)
                        .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                        calendarCell(cell)
                    }
                }
            }
        }
    }

    private func calendarCell(_ cell: CalendarCell) -> some View {
        let dayNumber = cell.dayNumber
        let isToday = cell.isToday
        let phase = cell.phase

        return Button {
            guard let date = cell.date, date <= Date() else { return }
            openEditor(for: date)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(phaseBackground(for: phase, isToday: isToday))
                    .overlay {
                        if phase == .predictedPeriod {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(periodTint.opacity(0.30), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        }
                        if isToday {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(periodTint, lineWidth: 2)
                        }
                    }

                Text(dayNumber)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(textColor(for: phase, isToday: isToday))
            }
        }
        .buttonStyle(.plain)
        .disabled(cell.date == nil || (cell.date ?? .distantFuture) > Date())
        .aspectRatio(1, contentMode: .fit)
    }

    private enum CalendarPhase {
        case none
        case period
        case fertile
        case predictedPeriod
    }

    private struct CalendarCell {
        let date: Date?
        let dayNumber: String
        let isToday: Bool
        let phase: CalendarPhase
    }

    private func calendarWeeks(for month: Date) -> [[CalendarCell]] {
        let calendar = Calendar.current
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        var firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        firstWeekday = (firstWeekday + 5) % 7 // Monday=0

        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"

        var allCells: [CalendarCell] = []

        for _ in 0..<firstWeekday {
            allCells.append(CalendarCell(date: nil, dayNumber: "", isToday: false, phase: .none))
        }

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                let dateString = formatter.string(from: date)
                let isToday = calendar.isDateInToday(date)
                let phase = calendarPhase(for: dateString, date: date)
                allCells.append(CalendarCell(
                    date: date,
                    dayNumber: "\(day)",
                    isToday: isToday,
                    phase: phase
                ))
            }
        }

        while allCells.count % 7 != 0 {
            allCells.append(CalendarCell(date: nil, dayNumber: "", isToday: false, phase: .none))
        }

        return stride(from: 0, to: allCells.count, by: 7).map {
            Array(allCells[$0..<min($0 + 7, allCells.count)])
        }
    }

    private func calendarPhase(for dateString: String, date: Date) -> CalendarPhase {
        let overlayTypes = self.overlayTypes(for: dateString)
        if overlayTypes.contains("PERIOD") { return .period }
        if overlayTypes.contains("FERTILE_WINDOW") || overlayTypes.contains("OVULATION") { return .fertile }
        if overlayTypes.contains("PREDICTED_PERIOD") { return .predictedPeriod }
        return .none
    }

    private func phaseBackground(for phase: CalendarPhase, isToday: Bool) -> Color {
        switch phase {
        case .none: return Color.clear
        case .period: return isToday ? periodTint : periodTint.opacity(0.15)
        case .fertile: return fertileTint.opacity(0.12)
        case .predictedPeriod: return periodTint.opacity(0.05)
        }
    }

    private func textColor(for phase: CalendarPhase, isToday: Bool) -> Color {
        switch phase {
        case .period where isToday: return .white
        case .none, .period, .fertile, .predictedPeriod: return Color(hex: "3A3A3C")
        }
    }

    private func calendarLegendDot(color: Color, border: Color? = nil, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(border, style: StrokeStyle(lineWidth: 1, dash: [2, 1]))
                            .frame(width: 8, height: 8)
                    }
                }
            Text(label)
                .font(.appSystem(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var startPregnancyButton: some View {
        if let onStartPregnancy {
            Button(action: onStartPregnancy) {
                Label("开始孕期", systemImage: "figure.and.child.holdinghands")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "C63F78"))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Theme.Colors.surface.opacity(0.82), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始孕期记录")
        }
    }

    // MARK: 辅助

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
    }

    private func performQuickRecord(_ preset: PeriodQuickRecordPreset) {
        guard viewModel.quickRecordToday(preset) else { return }
        quickRecordFeedbackID += 1
    }

    private func openEditor(
        for date: Date,
        focus: PeriodSheetView.FocusSection = .dayLog
    ) {
        viewModel.selectLog(date: Calendar.current.startOfDay(for: date))
        recordSheetFocus = focus
        showingRecordSheet = true
    }

    private var todayPeriodLog: PeriodDayLog? {
        let dateString = Self.dayFormatter.string(from: Calendar.current.startOfDay(for: Date()))
        return viewModel.summary?.dayLogs?.first(where: { $0.date == dateString })
    }

    private var isTodayMenstruating: Bool {
        (todayPeriodLog?.flowLevel ?? 0) > 0
    }

    private var todayDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MEd")
        return formatter.string(from: Date())
    }

    private var periodBackground: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }

    private var heroAccentColor: Color {
        switch viewModel.currentPhaseDisplayText {
        case "经期": return Color(hex: "E85F56")
        case "卵泡期": return Color(hex: "2FA77A")
        case "排卵期": return Color(hex: "7561D8")
        case "黄体期": return Color(hex: "D78B31")
        default: return Color(hex: "6C8FAE")
        }
    }

    private var heroBackgroundColor: Color {
        switch viewModel.currentPhaseDisplayText {
        case "经期": return Color(hex: "FCE8F4")
        case "卵泡期": return Color(hex: "E3F6EF")
        case "排卵期": return Color(hex: "EEEAFB")
        case "黄体期": return Color(hex: "FBEFD9")
        default: return Color(hex: "EAF1F6")
        }
    }

    private var heroTitle: String {
        viewModel.clinicalHeadline
    }

    private func cycleDay(for date: Date) -> Int? {
        let target = Calendar.current.startOfDay(for: date)
        let cycles = viewModel.summary?.cycles ?? []

        for cycle in cycles {
            guard let startString = cycle.startDate,
                  let startDate = Self.dayFormatter.date(from: startString) else {
                continue
            }
            let start = Calendar.current.startOfDay(for: startDate)
            let end: Date
            if let endString = cycle.endDate,
               let endDate = Self.dayFormatter.date(from: endString) {
                end = Calendar.current.startOfDay(for: endDate)
            } else {
                end = Calendar.current.date(byAdding: .day, value: 60, to: start) ?? start
            }
            guard target >= start && target <= end else { continue }
            let diff = Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
            return diff + 1
        }

        if let startString = viewModel.summary?.current?.startDate,
           let start = Self.dayFormatter.date(from: startString),
           target >= Calendar.current.startOfDay(for: start) {
            let diff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: target).day ?? 0
            return diff + 1
        }

        return nil
    }

    private func overlayTypes(for dateString: String) -> [String] {
        guard let overlays = viewModel.summary?.overlayRanges else { return [] }
        return overlays.compactMap { range in
            guard let start = range.startDate, let end = range.endDate, let type = range.type else { return nil }
            return (start...end).contains(dateString) ? type : nil
        }
    }

    fileprivate static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct VitalityPeriodHeroVisual: View {
    let phaseText: String
    let cycleDayText: String
    let accent: Color
    let isLoading: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.72))

            Circle()
                .stroke(accent.opacity(0.12), lineWidth: 8)
                .padding(8)

            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(8)

            VStack(spacing: 5) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(accent)

                Text(cycleDayText)
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 20)

            if isLoading {
                ProgressView()
                    .tint(accent)
                    .offset(y: 38)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phaseText)，\(cycleDayText)")
    }
}

private struct VitalityPeriodNavigationChrome: ViewModifier {
    let isEmbedded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content
                .navigationTitle("生理周期")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    func periodFlatCard(cornerRadius: CGFloat = 18) -> some View {
        background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(hex: "DDEDE6"), lineWidth: 1)
            )
            .shadow(color: Color(hex: "8E7A92").opacity(0.06), radius: 10, x: 0, y: 6)
    }
}
