/// FitnessTrainingWeekStrip 由健身日历页调用，作为「周训练条带」共享组件。
/// 负责渲染周日期翻页、今日定位与每日打卡点交互。

import SwiftUI

enum FitnessVisualStyle {
    static let pageBackground = Theme.Colors.pageBackground
    static let surface = Theme.Colors.surface
    static let primary = Color(hex: "246B57")
    static let primarySoft = Color(hex: "E6EFEA")
    static let recovery = Color(hex: "527583")
    static let warning = Color(hex: "8A5726")
    static let risk = Color(hex: "B64A59")
    static let cycle = Color(hex: "8E5C57")
    static let ink = Theme.Colors.textPrimary
    static let muted = Theme.Colors.textSecondary
    static let divider = Theme.Colors.surfaceBorder
    static let cardRadius: CGFloat = Theme.Radius.card
    static let controlRadius: CGFloat = Theme.Radius.control

    static func semanticColor(for hex: String) -> Color {
        switch hex.uppercased() {
        case "F06A7B", "EF6A8A":
            return risk
        case "F3A34A", "F4B46B", "B77938":
            return warning
        case "2AA7A1", "2DA8A1", "3B8EF7", "527583", "5578F6", "73C8E8", "7B74F5":
            return recovery
        case "94A3C3":
            return muted
        case "C47C74":
            return cycle
        default:
            return primary
        }
    }
}

struct FitnessHomeHeroCard: View {
    let context: FitnessAIInsightContext
    let achievement: FitnessAchievementCardModel
    let performance: FitnessPerformanceTrackModel
    let nextStep: FitnessNextStepModel
    let onOpenCalendar: () -> Void
    let onOpenHistory: () -> Void
    let onNextStepPrimary: () -> Void
    let onNextStepSecondary: () -> Void

    private var accent: Color {
        FitnessVisualStyle.semanticColor(for: performance.accentHex)
    }

    private var scoreProgress: Double {
        guard let score = Double(performance.scoreText) else { return 0 }
        return max(0, min(1, score / 100))
    }

    private var nextStepAccent: Color {
        FitnessVisualStyle.semanticColor(for: nextStep.accentHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本周训练")
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(accent)
                        .tracking(1.2)
                    Text(performance.statusText)
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.ink)
                    Text(performance.detailText)
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.13), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: scoreProgress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(performance.scoreText)
                            .font(.appSystem(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(FitnessVisualStyle.ink)
                            .minimumScaleFactor(0.72)
                        Text("表现")
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(FitnessVisualStyle.muted)
                    }
                }
                .frame(width: 78, height: 78)
            }

            HStack(spacing: 0) {
                summaryMetric(
                    title: String(localized: "训练"),
                    value: "\(achievement.weeklyTrainingDays)/\(achievement.weeklyGoal) 天",
                    symbol: "figure.run"
                )
                metricDivider
                summaryMetric(
                    title: String(localized: "时长"),
                    value: "\(context.recentMinutes) 分钟",
                    symbol: "clock.fill"
                )
                metricDivider
                summaryMetric(
                    title: String(localized: "恢复"),
                    value: context.currentRecoveryScore.map { "\($0)" } ?? "--",
                    symbol: "heart.text.square.fill"
                )
            }

            Divider()
                .overlay(FitnessVisualStyle.divider.opacity(0.7))

            nextStepContent

            heroActions
        }
        .padding(18)
        .bbLiquidGlassSurface(
            tint: accent,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous),
            tintStrength: 0.13
        )
        .accessibilityElement(children: .contain)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(FitnessVisualStyle.divider.opacity(0.7))
            .frame(width: 1, height: 42)
    }

    private func summaryMetric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.appSystem(size: 9, weight: .black, design: .rounded))
                .foregroundColor(FitnessVisualStyle.muted)
                .lineLimit(1)
            Text(value)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(FitnessVisualStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var nextStepContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: nextStep.symbol)
                    .font(.appSystem(size: 18, weight: .black))
                    .foregroundColor(nextStepAccent)
                    .frame(width: 42, height: 42)
                    .bbTintedChip(tint: nextStepAccent, in: Circle(), tintOpacity: 0.10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(nextStep.title)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(nextStepAccent)
                    Text(nextStep.headline)
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.ink)
                    Text(nextStep.detailText)
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if nextStep.primaryMode != nil {
                    Button(action: onNextStepSecondary) {
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 11, weight: .black))
                            .foregroundColor(nextStepAccent)
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(nextStep.secondaryActionTitle)
                }
            }

            nextStepPrimaryButton
        }
    }

    @ViewBuilder
    private var nextStepPrimaryButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onNextStepPrimary) {
                nextStepPrimaryLabel
            }
            .buttonStyle(.glassProminent)
            .tint(nextStepAccent)
        } else {
            Button(action: onNextStepPrimary) {
                nextStepPrimaryLabel
                    .background(nextStepAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var nextStepPrimaryLabel: some View {
        Label(nextStep.primaryActionTitle, systemImage: nextStep.primaryMode?.symbol ?? "square.and.pencil")
            .font(.appSystem(size: 12, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var heroActions: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    heroAction(title: String(localized: "训练日历"), symbol: "calendar", action: onOpenCalendar)
                    heroAction(title: String(localized: "训练报告"), symbol: "doc.text.magnifyingglass", action: onOpenHistory)
                }
            }
        } else {
            HStack(spacing: 10) {
                legacyHeroAction(title: String(localized: "训练日历"), symbol: "calendar", action: onOpenCalendar)
                legacyHeroAction(title: String(localized: "训练报告"), symbol: "doc.text.magnifyingglass", action: onOpenHistory)
            }
        }
    }

    @available(iOS 26.0, *)
    private func heroAction(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            heroActionLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.glass)
        .tint(accent.opacity(0.16))
    }

    private func legacyHeroAction(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            heroActionLabel(title: title, symbol: symbol)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func heroActionLabel(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.appSystem(size: 12, weight: .black, design: .rounded))
            .foregroundColor(accent)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
    }
}

struct FitnessTrainingWeekStrip: View {
    let model: HabitFitnessCalendarModel
    let selectedDate: Date
    let onShiftWeek: (Int) -> Void
    let onOpenMonth: () -> Void
    let onSelectDay: (HabitFitnessCalendarDay) -> Void
    let onToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            HStack(spacing: Theme.Spacing.compact) {
                Button { onShiftWeek(-1) } label: {
                    weekArrow("chevron.left")
                }

                Button(action: onOpenMonth) {
                    HStack(spacing: 6) {
                        Text(model.rangeTitle)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "calendar.badge.clock")
                            .font(.appSystem(size: 12, weight: .black))
                            .foregroundColor(FitnessVisualStyle.primary)
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button("今天", action: onToday)
                    .font(Theme.Typography.label)
                    .foregroundColor(FitnessVisualStyle.primary)
                    .frame(minHeight: 40)

                Button { onShiftWeek(1) } label: {
                    weekArrow("chevron.right")
                }
            }

            HStack(spacing: Theme.Spacing.hairline) {
                ForEach(model.days.prefix(7)) { day in
                    weekDay(day)
                }
            }
        }
        .padding(Theme.Spacing.small)
        .bbLiquidGlassSurface(
            tint: FitnessVisualStyle.primary,
            in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
            tintStrength: 0.06,
            shadow: false
        )
        .accessibilityElement(children: .contain)
    }

    private func weekArrow(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.appSystem(size: 11, weight: .black))
            .foregroundColor(Theme.Colors.textSecondary)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private func weekDay(_ day: HabitFitnessCalendarDay) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        let tint = FitnessVisualStyle.semanticColor(
            for: day.checkinMode?.tintHex ?? (day.isInferredWorkoutOnly ? "F3A34A" : "007F79")
        )
        return Button { onSelectDay(day) } label: {
            VStack(spacing: 4) {
                Text(day.dayLabel)
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(day.isSelected ? Color.white.opacity(0.82) : Theme.Colors.textTertiary)

                Text(day.numberLabel)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(day.isSelected ? .white : FitnessVisualStyle.ink)

                Circle()
                    .fill(day.checkinMode != nil || day.isInferredWorkoutOnly ? tint : Color.clear)
                    .frame(width: 5, height: 5)
                    .overlay {
                        if isToday && day.checkinMode == nil && !day.isInferredWorkoutOnly {
                            Circle().stroke(day.isSelected ? Color.white : FitnessVisualStyle.primary, lineWidth: 1.5)
                        }
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                day.isSelected
                    ? FitnessVisualStyle.primary
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(alignment: .bottom) {
                if isToday && !day.isSelected {
                    Rectangle()
                        .fill(FitnessVisualStyle.primary)
                        .frame(width: 18, height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .opacity(day.isFuture ? 0.42 : 1)
        .accessibilityLabel("\(day.dayLabel) \(day.numberLabel) 日，\(day.statusText)")
        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
    }
}

struct FitnessAIInsightCard: View {
    let insight: FitnessAIInsightModel
    let context: FitnessAIInsightContext
    let onOpenAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: insight.symbol)
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundStyle(FitnessVisualStyle.primary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrowText)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.primary)
                    Text("训练数据解读")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Circle()
                        .fill(FitnessVisualStyle.semanticColor(for: insight.accentHex))
                        .frame(width: 7, height: 7)
                    Text(insight.confidence.title)
                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(insight.title)
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.summary)
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.muted)
                    .lineLimit(3)
            }

            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(FitnessVisualStyle.primary)
                        .frame(width: 6, height: 6)
                    Text("数据完整度 \(context.totalSignalDays)/7 天")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(FitnessVisualStyle.muted)
                }

                Spacer(minLength: 8)

                Button(action: onOpenAI) {
                    HStack(spacing: 7) {
                        Text("详细解释")
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 9, weight: .black))
                    }
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .bbLiquidGlassSurface(
            tint: FitnessVisualStyle.primary,
            in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
            tintStrength: 0.08,
            shadow: false
        )
        .accessibilityElement(children: .contain)
    }

    private var eyebrowText: String {
        insight.eyebrow.replacingOccurrences(of: "PULSE AI · ", with: "")
    }
}

struct FitnessPerformanceBento: View {
    let context: FitnessAIInsightContext
    let achievement: FitnessAchievementCardModel
    let recovery: FitnessRecoveryManagementModel
    let performance: FitnessPerformanceTrackModel

    var body: some View {
        if context.totalSignalDays == 0 && context.recentTrainingDays == 0 {
            emptyState
        } else {
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        loadCard
                            .frame(maxWidth: .infinity, minHeight: 190)

                        Rectangle()
                            .fill(FitnessVisualStyle.divider)
                            .frame(width: 1)
                            .padding(.vertical, 16)

                        supportingMetrics
                            .frame(width: 138)
                    }

                    VStack(spacing: 0) {
                        loadCard
                        Divider()
                        supportingMetrics
                    }
                }

                Divider()
                performanceStrip
            }
            .bbLiquidGlassSurface(
                tint: FitnessVisualStyle.primary,
                in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
                tintStrength: 0.055,
                shadow: false
            )
        }
    }

    private var supportingMetrics: some View {
        VStack(spacing: 0) {
            compactMetric(
                title: "恢复",
                value: context.currentRecoveryScore.map(String.init) ?? recovery.scoreText,
                unit: context.currentRecoveryScore == nil ? "" : "/100",
                note: recovery.statusText,
                symbol: "heart.text.square.fill",
                tintHex: "527583"
            )
            Divider()
            compactMetric(
                title: "本周完成",
                value: "\(achievement.weeklyTrainingDays)/\(achievement.weeklyGoal)",
                unit: "天",
                note: achievement.weeklyTrainingDays >= achievement.weeklyGoal ? "目标完成" : "持续积累",
                symbol: "calendar.badge.checkmark",
                tintHex: "246B57"
            )
        }
    }

    private var loadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("训练负荷", systemImage: "bolt.heart.fill")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.primary)
                Spacer()
                Text("近 7 天")
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(context.currentLoadScore.map(String.init) ?? "--")
                    .font(.appSystem(size: 39, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.ink)
                if context.currentLoadScore != nil {
                    Text("/100")
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            ProgressView(value: Double(context.currentLoadScore ?? 0), total: 100)
                .tint(FitnessVisualStyle.primary)

            Spacer(minLength: 0)

            Text("\(context.recentTrainingDays) 天训练 · \(context.recentMinutes) 分钟")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(FitnessVisualStyle.ink)
            Text(loadComparisonText)
                .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(17)
    }

    private func compactMetric(title: String, value: String, unit: String, note: String, symbol: String, tintHex: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol)
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Color(hex: tintHex))
                Spacer()
                Text(title)
                    .font(.appSystem(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 23, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.appSystem(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Text(note)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: tintHex))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(13)
    }

    private var performanceStrip: some View {
        HStack(spacing: 13) {
            Image(systemName: "chart.xyaxis.line")
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(FitnessVisualStyle.primary)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("体能趋势")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(performance.statusText)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(context.performanceScore.map { "\($0) 分" } ?? performance.scoreText)
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(FitnessVisualStyle.primary)
                Text(performance.changeText)
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.appSystem(size: 20, weight: .black))
                .foregroundColor(FitnessVisualStyle.primary)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("建立第一组训练样本")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("完成一次运动或同步活动数据后，这里会生成负荷、恢复与体能趋势。")
                    .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .bbLiquidGlassSurface(
            tint: FitnessVisualStyle.primary,
            in: RoundedRectangle(cornerRadius: FitnessVisualStyle.cardRadius, style: .continuous),
            tintStrength: 0.055,
            shadow: false
        )
    }

    private var loadComparisonText: String {
        let delta = context.recentMinutes - context.previousMinutes
        if context.previousMinutes == 0 { return "与前一阶段的比较正在建立" }
        if delta == 0 { return "训练分钟与前 7 天持平" }
        return delta > 0 ? "比前 7 天多 \(delta) 分钟" : "比前 7 天少 \(abs(delta)) 分钟"
    }

}


struct FitnessTrainingLoadingSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .frame(height: 116)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: "E8EEFA").opacity(0.82))
                .frame(height: 282)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(height: 176)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(height: 176)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("正在整理训练数据")
    }
}
