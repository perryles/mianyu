/// PregnancyRecordView 由生理健康模块调用，作为「孕期记录」页面。
/// 负责路由孕期设置、体重、胎动、胎动历史等子页面。

import Charts
import CloudKit
import SwiftUI
import UIKit

private enum PregnancyRecordSheet: String, Identifiable {
    case settings
    case weight
    case fetalMovement
    case fetalMovementHistory

    var id: String { rawValue }
}

struct PregnancyRecordView: View {
    @State private var viewModel: PregnancyViewModel
    private let isEmbedded: Bool
    @State private var chartRange: PregnancyChartRange = .week
    @State private var activeSheet: PregnancyRecordSheet?
    @State private var weightPendingDeletion: PregnancyWeightEntry?
    @State private var movementPendingDeletion: FetalMovementEntry?
    @State private var showsWeightDeleteConfirmation = false
    @State private var showsMovementDeleteConfirmation = false
    @State private var operationError: String?

    private let rose = Color(hex: "F35F9B")
    private let deepRose = Color(hex: "C63F78")
    private let mint = Color(hex: "42BE9B")
    private let ink = Color(hex: "35383F")
    private let secondaryInk = Color(hex: "777C86")

    @MainActor
    init(isEmbedded: Bool = false) {
        _viewModel = State(initialValue: PregnancyViewModel())
        self.isEmbedded = isEmbedded
    }

    @MainActor
    init(viewModel: PregnancyViewModel, isEmbedded: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.isEmbedded = isEmbedded
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pregnancyBackground

            VStack(spacing: 0) {
                Color(hex: "FCE8F4")
                    .frame(height: 180)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    heroSection
                    quickActionsCard
                    stageGuidanceCard
                    weightCard
                    fetalMovementCard
                    dateSection
                    iCloudStatusCard
                    disclaimerCard
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
            .refreshable {
                await viewModel.load()
            }
        }
        .modifier(PregnancyRecordNavigationChrome(isEmbedded: isEmbedded))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.appSystem(size: 15, weight: .bold))
                        .foregroundColor(ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.surface, in: Circle())
                }
                .accessibilityLabel("孕期设置")
                .disabled(!viewModel.canMutate)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                PregnancySettingsSheet(
                    profile: viewModel.activeProfile,
                    viewModel: viewModel
                )
            case .weight:
                PregnancyWeightEntrySheet(viewModel: viewModel)
            case .fetalMovement:
                FetalMovementEntrySheet(
                    viewModel: viewModel,
                    earliestDate: viewModel.activeProfile?.lastMenstrualPeriod
                )
            case .fetalMovementHistory:
                FetalMovementHistorySheet(viewModel: viewModel)
            }
        }
        .confirmationDialog(
            "删除这条体重记录？",
            isPresented: $showsWeightDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let entry = weightPendingDeletion else { return }
                Task {
                    if !(await viewModel.deleteWeight(id: entry.id)) {
                        operationError = viewModel.errorMessage
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "删除这条胎动记录？",
            isPresented: $showsMovementDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let entry = movementPendingDeletion else { return }
                Task {
                    if !(await viewModel.deleteFetalMovement(id: entry.id)) {
                        operationError = viewModel.errorMessage
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(operationError ?? "请稍后重试。")
        }
        .task {
            if !viewModel.hasLoadedSnapshot {
                await viewModel.load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSUbiquityIdentityDidChange)) { _ in
            handleICloudAccountChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            handleICloudAccountChange()
        }
    }

    private var pregnancyBackground: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }

    private var progress: PregnancyProgress? {
        viewModel.activeProfile.map { PregnancyDateCalculator.progress(for: $0) }
    }

    private var heroSection: some View {
        VStack(spacing: 15) {
            Text(gestationalAgeText)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "586171"))

            PregnancyHeroVisual(
                progress: progress?.fractionComplete ?? 0,
                weekText: progress.map { "第\($0.completedWeeks)周" } ?? "等待设置",
                dayText: progress.map { "+\($0.remainingDaysInWeek)天" } ?? "",
                accent: deepRose,
                isLoading: viewModel.syncStatus.isBusy
            )
            .frame(width: 210, height: 176)

            Label(trimesterText, systemImage: "heart.fill")
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white, lineWidth: 1)
                }

            VStack(spacing: 7) {
                Text("\(countdownPrefix) \(countdownValue)")
                    .font(.appSystem(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("孕期进度 \(progressCaption)，记录会保存在你的私人 iCloud。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(
            Color(hex: "FCE8F4"),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .padding(.horizontal, -18)
        .padding(.top, -16)
    }

    private var quickActionsCard: some View {
        pregnancyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今天记录什么？")
                            .font(.appSystem(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(ink)
                        Text("按需要记录，不要求每天完成")
                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill")
                        .font(.appSystem(size: 23, weight: .bold))
                        .foregroundColor(rose)
                }

                HStack(spacing: 10) {
                    quickActionButton(
                        title: "记录体重",
                        value: latestWeightText,
                        icon: "scalemass.fill",
                        tint: deepRose
                    ) { activeSheet = .weight }

                    quickActionButton(
                        title: "记录胎动",
                        value: todayMovementSummary,
                        icon: "hand.tap.fill",
                        tint: Color(hex: "6B77C8")
                    ) { activeSheet = .fetalMovement }
                }
            }
        }
    }

    private func quickActionButton(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: icon)
                    .font(.appSystem(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Text(value)
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canMutate)
        .opacity(viewModel.canMutate ? 1 : 0.62)
    }

    private var stageGuidanceCard: some View {
        let guidance = PregnancyStageGuidance(trimester: progress?.trimester ?? 1)
        return pregnancyCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: guidance.symbol)
                    .font(.appSystem(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "2F8069"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "E5F5EF"), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(guidance.title)
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "2F8069"))
                    Text(guidance.headline)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Text(guidance.detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var latestWeightText: String {
        guard let weight = viewModel.weights.max(by: { $0.measuredAt < $1.measuredAt }) else {
            return "还没有记录"
        }
        return "最近 \(weight.weightKg.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var todayMovementSummary: String {
        let count = viewModel.fetalMovements.filter { Calendar.current.isDateInToday($0.occurredAt) }.count
        return count == 0 ? "今天还没有记录" : "今天已记 \(count) 次"
    }

    private var dateSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                pregnancyDateCard(
                    title: "预产期",
                    value: viewModel.activeProfile.map { Self.dayFormatter.string(from: $0.dueDate) } ?? "--",
                    icon: "calendar.badge.clock"
                )
                pregnancyDateCard(
                    title: "最后月经日期",
                    value: viewModel.activeProfile.map { Self.dayFormatter.string(from: $0.lastMenstrualPeriod) } ?? "--",
                    icon: "calendar"
                )
            }

            VStack(spacing: 10) {
                pregnancyDateCard(
                    title: "预产期",
                    value: viewModel.activeProfile.map { Self.dayFormatter.string(from: $0.dueDate) } ?? "--",
                    icon: "calendar.badge.clock"
                )
                pregnancyDateCard(
                    title: "最后月经日期",
                    value: viewModel.activeProfile.map { Self.dayFormatter.string(from: $0.lastMenstrualPeriod) } ?? "--",
                    icon: "calendar"
                )
            }
        }
    }

    private func pregnancyDateCard(title: String, value: String, icon: String) -> some View {
        Button {
            activeSheet = .settings
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .foregroundColor(secondaryInk)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 4)
                    Image(systemName: "pencil.line")
                        .foregroundColor(secondaryInk.opacity(0.8))
                }
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))

                Text(value)
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(ink)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .padding(15)
            .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(hex: "DDE8E8"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(value)，点按编辑")
        .disabled(!viewModel.canMutate)
    }

    private var weightCard: some View {
        pregnancyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    sectionIcon("scalemass.fill")
                    Text("体重统计")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Spacer(minLength: 8)
                    Picker("体重统计范围", selection: $chartRange) {
                        ForEach(PregnancyChartRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 112)
                }

                weightChart

                if !recentWeights.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(recentWeights) { entry in
                            weightRow(entry)
                            if entry.id != recentWeights.last?.id {
                                Divider().padding(.leading, 30)
                            }
                        }
                    }
                }

                recordButton(
                    title: "记录体重",
                    icon: "square.and.pencil"
                ) {
                    activeSheet = .weight
                }
            }
        }
    }

    @ViewBuilder
    private var weightChart: some View {
        if visibleWeights.isEmpty {
            ZStack {
                Chart {
                    RuleMark(y: .value("体重基线", 0))
                        .foregroundStyle(.clear)
                }
                .chartXScale(domain: chartDateDomain)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: chartRange == .week ? 7 : 5)) { _ in
                        AxisGridLine().foregroundStyle(Color(hex: "E8E8EC"))
                        AxisValueLabel(format: chartRange == .week ? .dateTime.weekday(.narrow) : .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color(hex: "E4E5E9"))
                        AxisValueLabel()
                    }
                }

                Text(chartRange == .week ? "本周还没有体重记录" : "近 30 天还没有体重记录")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(secondaryInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.surface.opacity(0.88), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 205)
            .accessibilityLabel(chartRange == .week ? "本周还没有体重记录" : "近三十天还没有体重记录")
        } else {
            Chart(visibleWeights) { entry in
                LineMark(
                    x: .value("日期", entry.measuredAt),
                    y: .value("体重", entry.weightKg)
                )
                .foregroundStyle(rose)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("日期", entry.measuredAt),
                    y: .value("体重", entry.weightKg)
                )
                .foregroundStyle(rose)
                .symbolSize(52)
            }
            .chartXScale(domain: chartDateDomain)
            .chartYScale(domain: chartWeightDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: chartRange == .week ? 7 : 5)) { value in
                    AxisGridLine().foregroundStyle(Color(hex: "E8E8EC"))
                    AxisValueLabel(format: chartRange == .week ? .dateTime.weekday(.narrow) : .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color(hex: "E4E5E9"))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.formatted(.number.precision(.fractionLength(0...1))))
                        }
                    }
                }
            }
            .frame(height: 205)
            .accessibilityLabel("孕期体重趋势图")
        }
    }

    private func weightRow(_ entry: PregnancyWeightEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(secondaryInk)
                .frame(width: 20)
            Text(Self.shortDateFormatter.string(from: entry.measuredAt))
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(ink)
            Spacer(minLength: 8)
            Text("\(entry.weightKg.formatted(.number.precision(.fractionLength(1)))) kg")
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(deepRose)
            Menu {
                Button("删除", systemImage: "trash", role: .destructive) {
                    weightPendingDeletion = entry
                    showsWeightDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(secondaryInk)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("管理 \(Self.shortDateFormatter.string(from: entry.measuredAt)) 的 \(entry.weightKg.formatted(.number.precision(.fractionLength(1)))) 千克体重记录")
            .disabled(!viewModel.canMutate)
        }
        .frame(minHeight: 44)
    }

    private var fetalMovementCard: some View {
        pregnancyCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    activeSheet = .fetalMovementHistory
                } label: {
                    HStack(spacing: 10) {
                        sectionIcon("list.clipboard.fill")
                        Text("胎动记录")
                            .font(.appSystem(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(ink)
                        Spacer(minLength: 8)
                        Text(viewModel.fetalMovements.isEmpty ? "" : "全部 \(viewModel.fetalMovements.count)")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(secondaryInk)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 12, weight: .black))
                            .foregroundColor(ink)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    viewModel.fetalMovements.isEmpty
                        ? "查看胎动历史，暂无记录"
                        : "查看全部胎动记录，共 \(viewModel.fetalMovements.count) 条"
                )

                if recentMovements.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "hand.tap.fill")
                            .font(.appSystem(size: 24, weight: .semibold))
                            .foregroundColor(rose.opacity(0.58))
                        Text("还没有胎动记录")
                            .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(secondaryInk)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentMovements) { entry in
                            fetalMovementRow(entry)
                            if entry.id != recentMovements.last?.id {
                                Divider().padding(.leading, 30)
                            }
                        }
                    }
                }

                recordButton(
                    title: "记录胎动",
                    icon: "square.and.pencil"
                ) {
                    activeSheet = .fetalMovement
                }
            }
        }
    }

    private func fetalMovementRow(_ entry: FetalMovementEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(secondaryInk)
                .frame(width: 20)
            Text(Self.dateTimeFormatter.string(from: entry.occurredAt))
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(ink)
            Spacer(minLength: 8)
            Menu {
                Button("删除", systemImage: "trash", role: .destructive) {
                    movementPendingDeletion = entry
                    showsMovementDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(secondaryInk)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("管理 \(Self.dateTimeFormatter.string(from: entry.occurredAt)) 的胎动记录")
            .disabled(!viewModel.canMutate)
        }
        .frame(minHeight: 48)
    }

    private var iCloudStatusCard: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                Text(statusDetail)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if case .failed = viewModel.syncStatus {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.appSystem(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.surface, in: Circle())
                }
                .foregroundColor(deepRose)
                .accessibilityLabel("重试 iCloud 同步")
            }
        }
        .padding(14)
        .background(Theme.Colors.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.syncStatus {
        case .loading, .saving:
            ProgressView()
                .tint(mint)
                .frame(width: 28, height: 28)
        case .failed:
            Image(systemName: "icloud.slash.fill")
                .foregroundColor(deepRose)
                .frame(width: 28, height: 28)
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundColor(mint)
                .frame(width: 28, height: 28)
        case .idle:
            Image(systemName: "icloud.fill")
                .foregroundColor(secondaryInk)
                .frame(width: 28, height: 28)
        }
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.case.fill")
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "5A82B8"))
            Text("孕周、体重与胎动记录用于个人健康管理，不替代产检、诊断或紧急医疗建议。出现胎动明显减少或身体不适时，请及时联系专业医护人员。")
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func pregnancyCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(17)
            .background(Theme.Colors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color(hex: "8E7A92").opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private func sectionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.appSystem(size: 13, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 25, height: 25)
            .background(rose, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func recordButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(deepRose)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canMutate)
        .opacity(viewModel.canMutate ? 1 : 0.62)
    }

    private var visibleWeights: [PregnancyWeightEntry] {
        PregnancyAnalytics.weights(viewModel.weights, range: chartRange)
    }

    private var hasSyncFailure: Bool {
        if case .failed = viewModel.syncStatus { return true }
        return false
    }

    private func handleICloudAccountChange() {
        activeSheet = nil
        weightPendingDeletion = nil
        movementPendingDeletion = nil
        showsWeightDeleteConfirmation = false
        showsMovementDeleteConfirmation = false
        operationError = nil
        guard !isEmbedded else { return }
        Task { await viewModel.handleICloudAccountChange() }
    }

    private var recentWeights: [PregnancyWeightEntry] {
        Array(viewModel.weights.sorted { $0.measuredAt > $1.measuredAt }.prefix(3))
    }

    private var recentMovements: [FetalMovementEntry] {
        Array(viewModel.fetalMovements.prefix(3))
    }

    private var chartDateDomain: ClosedRange<Date> {
        PregnancyAnalytics.dateDomain(for: chartRange)
    }

    private var chartWeightDomain: ClosedRange<Double> {
        let values = visibleWeights.map(\.weightKg)
        guard let minimum = values.min(), let maximum = values.max() else { return 40...100 }
        let padding = max(2, (maximum - minimum) * 0.2)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var countdownPrefix: String {
        guard let days = progress?.daysUntilDueDate else { return "距离预产期" }
        if days < 0 { return "超过预产期" }
        if days == 0 { return "今天是" }
        return "距离预产期"
    }

    private var countdownValue: String {
        guard let days = progress?.daysUntilDueDate else { return "--" }
        if days == 0 { return "预产期" }
        return String(localized: "\(abs(days)) 天")
    }

    private var gestationalAgeText: String {
        guard let progress else { return "设置日期后显示孕周" }
        return String(localized: "孕龄：\(progress.completedWeeks)周+\(progress.remainingDaysInWeek)天")
    }

    private var trimesterText: String {
        guard let progress else { return "孕期档案未设置" }
        return "孕\(progress.trimester == 1 ? "早" : progress.trimester == 2 ? "中" : "晚")期"
    }

    private var progressCaption: String {
        guard let progress else { return "0 / 40 周" }
        return String(localized: "\(progress.completedWeeks) / 40 周")
    }

    private var statusTitle: String {
        switch viewModel.syncStatus {
        case .idle: return "等待连接 iCloud"
        case .loading: return "正在从 iCloud 读取"
        case .saving: return "正在保存到 iCloud"
        case .synced: return "已同步到你的私人 iCloud"
        case .failed: return "iCloud 同步未完成"
        }
    }

    private var statusDetail: String {
        switch viewModel.syncStatus {
        case .failed(let message):
            return message
        case .synced(let date):
            return String(localized: "最近同步 \(Self.timeFormatter.string(from: date))，数据不经过 眠屿 后台。")
        default:
            return String(localized: "孕期设置、体重与胎动仅使用当前 Apple ID 的 CloudKit 私有数据库。")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct PregnancyHeroVisual: View {
    let progress: Double
    let weekText: String
    let dayText: String
    let accent: Color
    let isLoading: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.10), lineWidth: 1)
                .frame(width: 174, height: 174)

            Circle()
                .fill(Color.white.opacity(0.62))
                .frame(width: 154, height: 154)

            Circle()
                .stroke(accent.opacity(0.14), lineWidth: 12)
                .frame(width: 132, height: 132)

            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 132, height: 132)
                .animation(.easeInOut(duration: 0.35), value: progress)

            VStack(spacing: 5) {
                Image(systemName: "figure.and.child.holdinghands")
                    .font(.appSystem(size: 19, weight: .black))
                    .foregroundColor(accent)

                Text(weekText)
                    .font(.appSystem(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                if !dayText.isEmpty {
                    Text(dayText)
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 16)

            if isLoading {
                ProgressView()
                    .tint(accent)
                    .offset(y: 62)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayText.isEmpty ? weekText : "\(weekText)，\(dayText)")
    }
}

private struct PregnancyRecordNavigationChrome: ViewModifier {
    let isEmbedded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content
                .healthDetailNavigation(title: HealthPageName.pregnancy)
        }
    }
}
