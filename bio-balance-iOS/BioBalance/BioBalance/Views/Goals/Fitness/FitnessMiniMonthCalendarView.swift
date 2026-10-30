/// FitnessMiniMonthCalendarView 训练记录列表上方的迷你月历卡。
/// 参考 Grow 的「迷你运动月历」：按月渲染 7 列日历格，锻炼过的日期按训练时长染色，
/// 点击日期打开该日详情；无训练日显示小圆点底色，一眼看出本月努力了几天。

import SwiftUI

struct FitnessMiniMonthCalendarView: View {
    /// 60 天滑动窗口的全部日历日（含跨月）。
    let days: [HabitFitnessCalendarDay]
    /// 迷你月历正在展示的月份锚点。
    let displayedMonth: Date
    let selectedDate: Date
    let tint: Color

    let onShiftMonth: (Int) -> Void
    let onSelectDay: (HabitFitnessCalendarDay) -> Void

    @State private var monthTitle: String = ""
    @State private var monthCells: [Cell] = []
    @State private var monthTrainingDays = 0
    @State private var monthTrainingMinutes = 0

    private let calendar = Calendar.current

    struct Cell: Identifiable {
        let day: HabitFitnessCalendarDay?
        let date: Date
        let numberLabel: String
        let isInMonth: Bool
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack {
                ForEach(weekdaySymbols, id: \.self) { label in
                    Text(label)
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 7) {
                ForEach(monthCells) { cell in
                    dayCell(cell)
                }
            }

            summaryLine
        }
        .padding(16)
        .bbLiquidGlassSurface(
            tint: tint,
            in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
            tintStrength: 0.08
        )
        .onAppear(perform: rebuild)
        .onChange(of: displayedMonth) { _, _ in rebuild() }
        .onChange(of: days) { _, _ in rebuild() }
    }

    // MARK: 构建月格

    private func rebuild() {
        monthTitle = Self.monthTitle(for: displayedMonth)
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            monthCells = []
            return
        }
        let monthStart = monthInterval.start
        // 周一为一周起点，与项目其他月历保持一致。
        let leadingEmpty = (calendar.component(.weekday, from: monthStart) + 5) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0

        var cells: [Cell] = []
        cells.reserveCapacity(leadingEmpty + daysInMonth)
        for _ in 0..<leadingEmpty {
            cells.append(Cell(day: nil, date: monthStart, numberLabel: "", isInMonth: false))
        }
        for dayOffset in 0..<daysInMonth {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: monthStart) ?? monthStart
            let normalized = calendar.startOfDay(for: date)
            let day = days.first { calendar.isDate($0.date, inSameDayAs: normalized) }
            cells.append(Cell(day: day, date: normalized, numberLabel: "\(dayOffset + 1)", isInMonth: true))
        }
        monthCells = cells

        let inMonth = cells.compactMap(\.day).filter(\.isInDisplayedMonth)
        monthTrainingDays = inMonth.filter { $0.displayWorkoutMinutes > 0 || $0.checkinMode == .workout }.count
        monthTrainingMinutes = inMonth.reduce(0) { $0 + $1.displayWorkoutMinutes }
    }

    // MARK: 子视图

    private var header: some View {
        HStack(spacing: 8) {
            Button { onShiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(FitnessVisualStyle.primarySoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(monthTitle)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.ink)
                Text(String(localized: "本月训练 \(monthTrainingDays) 天 · \(monthTrainingMinutes) 分钟"))
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { onShiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(FitnessVisualStyle.primarySoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func dayCell(_ cell: Cell) -> some View {
        let minutes = cell.day?.displayWorkoutMinutes ?? 0
        let hasWorkout = minutes > 0 || cell.day?.checkinMode == .workout
        let isRecovery = cell.day?.checkinMode == .recovery || cell.day?.checkinMode == .rest
        let isToday = calendar.isDateInToday(cell.date)
        let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDate)
        let intensity = hasWorkout ? Self.trainingIntensity(for: minutes) : 0

        return Button {
            if let day = cell.day {
                onSelectDay(day)
            }
        } label: {
            VStack(spacing: 0) {
                Text(cell.numberLabel)
                    .font(.appSystem(size: 11, weight: hasWorkout ? .black : .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(numberColor(cell: cell, hasWorkout: hasWorkout, isSelected: isSelected))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(cellBackground(cell: cell, hasWorkout: hasWorkout, isRecovery: isRecovery, isSelected: isSelected, intensity: intensity))
                    )
                    .overlay {
                        if isToday, !isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(tint, lineWidth: 1.2)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(cell.day == nil)
        .accessibilityLabel(cellAccessibilityLabel(cell, hasWorkout: hasWorkout, minutes: minutes))
    }

    private func cellBackground(
        cell: Cell,
        hasWorkout: Bool,
        isRecovery: Bool,
        isSelected: Bool,
        intensity: Double
    ) -> Color {
        if isSelected { return tint }
        if hasWorkout {
            return tint.opacity(0.12 + 0.5 * intensity)
        }
        if isRecovery, cell.day?.isInDisplayedMonth == true {
            return FitnessVisualStyle.recovery.opacity(0.14)
        }
        return FitnessVisualStyle.divider.opacity(0.22)
    }

    private func numberColor(cell: Cell, hasWorkout: Bool, isSelected: Bool) -> Color {
        guard cell.isInMonth else { return FitnessVisualStyle.divider }
        if isSelected { return .white }
        return hasWorkout ? FitnessVisualStyle.ink : Theme.Colors.textTertiary
    }

    private var summaryLine: some View {
        HStack(spacing: 12) {
            legend(color: tint.opacity(0.42), label: String(localized: "训练"))
            legend(color: FitnessVisualStyle.recovery.opacity(0.24), label: String(localized: "恢复 / 休息"))
            legend(color: FitnessVisualStyle.divider.opacity(0.4), label: String(localized: "未锻炼"))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    private func cellAccessibilityLabel(_ cell: Cell, hasWorkout: Bool, minutes: Int) -> String {
        let dayText = Self.monthTitle(for: cell.date) + cell.numberLabel
        if hasWorkout {
            return String(localized: "\(dayText)，训练 \(minutes) 分钟")
        }
        if let mode = cell.day?.checkinMode {
            return String(localized: "\(dayText)，\(mode.title)")
        }
        return String(localized: "\(dayText)，未锻炼")
    }

    // MARK: 辅助方法

    private var weekdaySymbols: [String] { ["一", "二", "三", "四", "五", "六", "日"] }

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    private static func monthTitle(for date: Date) -> String {
        monthTitleFormatter.string(from: date)
    }

    /// 训练时长 → 染色强度（0…1）。60 分钟以上饱和。
    static func trainingIntensity(for minutes: Int) -> Double {
        guard minutes > 0 else { return 0 }
        return min(Double(minutes) / 60, 1)
    }
}
