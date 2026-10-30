/// MoodLogView 由健康首页与记录入口调用，作为「心理恢复」详情页。
/// 负责按月展示情绪日历、查看当天记录，并提供心理负荷、睡眠压力联动和问卷入口。

import SwiftUI
import HealthKit
import Charts

/// MoodLogView 由健康首页与记录入口调用，作为「心理恢复」详情页。
/// 负责按月展示情绪日历、查看当天记录，并提供心理负荷、睡眠压力联动和问卷入口。
struct MoodLogView: View {
    @Environment(\.openURL) private var openURL
    @State private var displayedMonth = MoodLogView.moodCalendar.startOfMonth(for: Date())
    @State private var selectedDate = MoodLogView.moodCalendar.startOfDay(for: Date())
    @State private var localEntries: [MoodEntry] = []
    @State private var mentalRecoverySnapshot: MentalRecoverySnapshot?
    @State private var showingComposer = false
    @State private var activeAssessmentKind: MentalAssessmentKind?
    @State private var latestGAD7Result: MentalAssessmentResult?
    @State private var latestPHQ9Result: MentalAssessmentResult?
    @State private var gad7History: [MentalAssessmentResult] = []
    @State private var phq9History: [MentalAssessmentResult] = []
    @State private var gad7SyncStatus: String?
    @State private var phq9SyncStatus: String?
    @State private var gad7SyncBadge: String?
    @State private var phq9SyncBadge: String?
    @State private var showingAssessmentEducation = false
    @State private var isLoadingRecovery = false
    /// 心理恢复快照加载代际：日期快速切换时只允许最新一次加载写入结果。
    @State private var recoveryLoadID = UUID()

    private let assessmentStore = MentalAssessmentStore()
    private let recoveryAnalyzer = MentalRecoveryAnalyzer()

    private static let moodCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let chineseLocale = Locale.autoupdatingCurrent

    private static let weekdaySymbols = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    calendarSection
                    selectedDayOverviewCard
                    if !selectedDayEntries.isEmpty {
                        selectedDayTimelineCard
                    }
                    monthlyInsightsSection
                    mentalRecoverySection
                    mentalAssessmentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("心理恢复")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openCurrentMoodCapture()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("记录此刻")
            }
        }
        .fullScreenCover(isPresented: $showingComposer, onDismiss: loadEntries) {
            MoodCaptureSheet(selectedDate: selectedDate, onSaved: refreshMoodContent)
        }
        .sheet(item: $activeAssessmentKind, onDismiss: {
            Task { await loadAssessmentResults() }
        }) { kind in
            MentalAssessmentSheet(kind: kind) { result in
                saveAssessment(result)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingAssessmentEducation) {
            MentalAssessmentEducationSheet()
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .task {
            loadEntries()
            await loadAssessmentResults()
            await loadMentalRecoverySnapshot()
        }
        .onChange(of: selectedDate) { _, _ in
            recoveryLoadID = UUID()
            Task { await loadMentalRecoverySnapshot() }
        }
    }
}

private extension MoodLogView {
    var calendar: Calendar { Self.moodCalendar }

    var pageHeroSection: some View {
        VStack(spacing: 13) {
            Text(heroDateText)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "586171"))

            MoodHeroAnimatedFace(level: heroMoodLevel)
                .frame(width: 210, height: 176)

            MoodSpeechBubble(title: heroMoodTitle)

            VStack(spacing: 7) {
                Text("今天感觉怎么样？")
                    .font(.appSystem(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(heroMoodSummary)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: openCurrentMoodCapture) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.appSystem(size: 15, weight: .black))
                    Text("记录此刻")
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                }
                .foregroundColor(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(hex: "316DF4"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(
            Color(hex: heroCaptureLevel.backgroundHex),
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
        .animation(.easeInOut(duration: 0.38), value: heroMoodLevel)
    }

    var heroMoodLevel: Int {
        latestEntry.map(moodLevel(for:)) ?? 3
    }

    func moodLevel(for entry: MoodEntry) -> Int {
        switch entry.moodID {
        case "sad": return 0
        case "lonely", "burnedout": return 1
        case "wronged", "anxious", "drained", "angry": return 2
        case "calm", "confused": return 3
        case "happy": return 4
        case "moved": return 5
        case "excited": return 6
        default:
            switch entry.backendEmotionCode {
            case "sad", "tired", "anxious": return 2
            case "happy": return 5
            default: return 3
            }
        }
    }

    var heroCaptureLevel: MoodCaptureLevel {
        MoodCaptureLevel.levels[heroMoodLevel]
    }

    var heroMoodTitle: String {
        latestEntry?.title ?? "等待记录"
    }

    var heroMoodSummary: String {
        if let latestEntry {
            return String(localized: "最近记录于 \(timeText(latestEntry.loggedAt))，可以继续补充此刻的变化。")
        }
        return String(localized: "滑动选择最接近的感受，让恢复线索从一次真实记录开始。")
    }

    var heroDateText: String {
        Date().formatted(.dateTime.locale(Self.chineseLocale).month().day().weekday(.wide))
    }

    func openCurrentMoodCapture() {
        selectedDate = calendar.startOfDay(for: Date())
        showingComposer = true
    }

    func refreshMoodContent() {
        loadEntries()
        Task { await loadMentalRecoverySnapshot() }
    }

    var monthDays: [Date?] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingEmptyDays = (weekday + 5) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    var moodEntryByDay: [Date: MoodEntry] {
        Dictionary(
            grouping: localEntries.filter { calendar.isDate($0.loggedAt, equalTo: displayedMonth, toGranularity: .month) },
            by: { calendar.startOfDay(for: $0.loggedAt) }
        ).compactMapValues { entries in
            entries.max(by: { $0.loggedAt < $1.loggedAt })
        }
    }

    var selectedDayEntries: [MoodEntry] {
        localEntries
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: selectedDate) }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    var displayedMonthEntries: [MoodEntry] {
        localEntries
            .filter { calendar.isDate($0.loggedAt, equalTo: displayedMonth, toGranularity: .month) }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    var displayedMonthRecordedDays: Int {
        Set(displayedMonthEntries.map { calendar.startOfDay(for: $0.loggedAt) }).count
    }

    var displayedMonthDayCount: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    var selectedDayAverageIntensity: Int? {
        guard !selectedDayEntries.isEmpty else { return nil }
        let total = selectedDayEntries.reduce(0) { $0 + $1.intensity }
        return Int((Double(total) / Double(selectedDayEntries.count)).rounded())
    }

    var displayedMonthAverageIntensity: Int? {
        guard !displayedMonthEntries.isEmpty else { return nil }
        let total = displayedMonthEntries.reduce(0) { $0 + $1.intensity }
        return Int((Double(total) / Double(displayedMonthEntries.count)).rounded())
    }

    var moodDistribution: [(option: MoodOption, title: String, count: Int)] {
        Dictionary(grouping: displayedMonthEntries, by: \.moodID)
            .compactMap { moodID, entries in
                guard let option = MoodCatalog.option(id: moodID) else { return nil }
                let displayTitle = entries.max(by: { $0.loggedAt < $1.loggedAt })?.title ?? option.title
                return (option: option, title: displayTitle, count: entries.count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.title < $1.title
                }
                return $0.count > $1.count
            }
    }

    var dominantMoodOption: MoodOption? {
        moodDistribution.first?.option
    }

    var dominantMoodTitle: String? {
        moodDistribution.first?.title
    }

    var latestEntry: MoodEntry? {
        localEntries.first
    }

    var calendarSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitleText(displayedMonth))
                        .font(.appSystem(.title3, design: .rounded).bold())
                        .foregroundColor(Color(hex: "12141A"))
                    Text("按天回看情绪与压力记录")
                        .font(.appSystem(.caption, design: .rounded))
                        .foregroundColor(Color(hex: "4F5B6B"))
                }
                Spacer(minLength: 0)
                monthNavigationButton(systemImage: "chevron.left", offset: -1)
                monthNavigationButton(systemImage: "chevron.right", offset: 1)
            }
            .padding(18)
            .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(hex: "C9D4DF"), lineWidth: 1)
            )
            .shadow(color: Color(hex: "203047").opacity(0.10), radius: 14, x: 0, y: 7)
            .padding(.bottom, 18)

            weekdayHeader
            monthGrid
        }
    }

    func monthNavigationButton(systemImage: String, offset: Int) -> some View {
        Button { shiftMonth(by: offset) } label: {
            Image(systemName: systemImage)
                .font(.appSystem(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "12141A"))
                .frame(width: 34, height: 34)
                .background(Color(hex: "DCE5ED"), in: Circle())
        }
        .buttonStyle(.plain)
    }

    var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Color(hex: "5E6470"))
                    .frame(width: 26, height: 26)
                    .background(Theme.Colors.secondarySurface, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitleText(displayedMonth))
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1C2231"))

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Color(hex: "5E6470"))
                    .frame(width: 26, height: 26)
                    .background(Theme.Colors.secondarySurface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 12)
    }

    var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                Text(String(symbol.suffix(1)))
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "4F5B6B"))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 12)
    }

    var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                if let date {
                    calendarCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 50)
                }
            }
        }
    }

    func calendarCell(for date: Date) -> some View {
        let dayKey = calendar.startOfDay(for: date)
        let entry = moodEntryByDay[dayKey]
        let option = entry.flatMap { MoodCatalog.option(id: $0.moodID) }
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

        return Button {
            selectedDate = dayKey
        } label: {
            VStack(spacing: 1) {
                Text(dayNumberText(date))
                    .font(.appSystem(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "4F5B6B"))

                calendarMoodBadge(option: option, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                isSelected ? Color(hex: "A9E4CF") : (isToday ? Color(hex: "FFD9E0") : Color(hex: "F7FAFC")),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color(hex: "3D9F7C") : Color(hex: "D4DDE5"), lineWidth: isSelected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    var mentalAssessmentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("心理健康问卷")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "1A2131"))

                Text("和健康 App 一样，把焦虑和抑郁分开做问卷记录。结果按近两周状态生成，更适合按周回看。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }

            Button {
                showingAssessmentEducation = true
            } label: {
                Text("查看问卷说明")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "6C57FF"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "F2EEFF"), in: Capsule())
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                mentalAssessmentCard(kind: .gad7, result: latestGAD7Result, syncStatus: gad7SyncStatus, syncBadge: gad7SyncBadge)
                mentalAssessmentCard(kind: .phq9, result: latestPHQ9Result, syncStatus: phq9SyncStatus, syncBadge: phq9SyncBadge)
            }

            // MARK: - 量表来源引用（Apple 审核要求 1.4.1）
            assessmentCitationRow

            if !gad7History.isEmpty || !phq9History.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("风险趋势")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "232B3A"))

                    riskTrendChart(
                        title: "焦虑风险趋势",
                        kind: .gad7,
                        results: gad7History,
                        accentHex: MentalAssessmentCatalog.accentHex(for: .gad7)
                    )

                    riskTrendChart(
                        title: "抑郁风险趋势",
                        kind: .phq9,
                        results: phq9History,
                        accentHex: MentalAssessmentCatalog.accentHex(for: .phq9)
                    )
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    /// 量表来源引用行（满足 App Store 审核指南 1.4.1 对医学信息引用的要求）。
    var assessmentCitationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("量表来源")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "9098AA"))

            VStack(alignment: .leading, spacing: 4) {
                let gad7 = MentalAssessmentCatalog.citation(for: .gad7)
                Text("\(gad7.authors). \(gad7.journal)")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "848B9A"))
                    .lineSpacing(2)
                Button {
                    openURL(gad7.url)
                } label: {
                    Text("GAD-7 文献原文（PubMed）")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "4B6EF4"))
                        .underline()
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                let phq9 = MentalAssessmentCatalog.citation(for: .phq9)
                Text("\(phq9.authors). \(phq9.journal)")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "848B9A"))
                    .lineSpacing(2)
                Button {
                    openURL(phq9.url)
                } label: {
                    Text("PHQ-9 文献原文（PubMed）")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "4B6EF4"))
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    var mentalRecoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("恢复联动")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "1A2131"))
                    Text("把心理负荷、睡眠恢复和身体压力收成同一条线。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                if isLoadingRecovery {
                    ProgressView()
                        .tint(Color(hex: "6C57FF"))
                } else if let snapshot = mentalRecoverySnapshot {
                    Text(snapshot.band.title)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: snapshot.band.accentHex))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: snapshot.band.accentHex).opacity(0.12), in: Capsule())
                }
            }

            if let snapshot = mentalRecoverySnapshot {
                mentalRecoveryOverviewCard(snapshot)
                mentalRecoveryTrendCard(snapshot)
                mentalRecoveryActionsCard(snapshot)
            } else {
                mentalRecoveryEmptyCard
            }
        }
    }

    var selectedDayOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(weekdayText(selectedDate))
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text(monthDayText(selectedDate))
                        .font(.appSystem(size: 25, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "182131"))
                }

                Spacer(minLength: 0)

                MoodCharacterFace(level: selectedDayMoodLevel)
                    .frame(width: 82, height: 70)
                    .scaleEffect(0.4)

                VStack(alignment: .trailing, spacing: 5) {
                    if let latest = selectedDayEntries.first {
                        Text(latest.title)
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "202838"))
                        Text(timeText(latest.loggedAt))
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    } else {
                        Text("尚未记录")
                            .font(.appSystem(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            if let latest = selectedDayEntries.first {
                HStack(spacing: 10) {
                    Text("\(selectedDayEntries.count) 次记录")
                    Circle().fill(Color(hex: "6B7482").opacity(0.35)).frame(width: 3, height: 3)
                    Text("平均强度 \(selectedDayAverageIntensity ?? latest.intensity)")
                    if let note = latest.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        Circle().fill(Color(hex: "6B7482").opacity(0.35)).frame(width: 3, height: 3)
                        Text("有备注")
                    }
                }
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "5F6978"))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            } else {
                Text("给这一天留下一条真实感受，日历会自动补上心情标记。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "637080"))
                    .lineSpacing(3)
            }

            Button {
                showingComposer = true
            } label: {
                Label(selectedDayEntries.isEmpty ? "为这一天补记" : "再记录一次", systemImage: "plus")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: "2457D6"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(hex: selectedDayCaptureLevel.backgroundHex).opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: "7E98B6").opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color(hex: "203047").opacity(0.12), radius: 16, x: 0, y: 8)
    }

    var selectedDayMoodLevel: Int {
        selectedDayEntries.first.map(moodLevel(for:)) ?? 3
    }

    var selectedDayCaptureLevel: MoodCaptureLevel {
        MoodCaptureLevel.levels[selectedDayMoodLevel]
    }

    var selectedDayTimelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("当天记录")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer(minLength: 0)

                Text("\(selectedDayEntries.count) 条")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "798193"))
            }

            if selectedDayEntries.isEmpty {
                Text("选中某一天后，这里会按时间列出当天所有心情记录。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(selectedDayEntries.enumerated()), id: \.element.id) { index, entry in
                        timelineRow(for: entry, index: index)
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color(hex: "C9D4DF"), lineWidth: 1)
        )
        .shadow(color: Color(hex: "203047").opacity(0.09), radius: 16, x: 0, y: 8)
    }

    var monthlyInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("这个月的情绪节律")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "1A2131"))
                    Text("从日历切换到整月回顾，看看哪些感受出现得更多。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "768093"))
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                insightMetricCard(
                    title: "记录次数",
                    value: "\(displayedMonthEntries.count)",
                    detail: "覆盖 \(displayedMonthRecordedDays) 天",
                    tint: Color(hex: "FF8E6E")
                )
                insightMetricCard(
                    title: "主导情绪",
                    value: dominantMoodTitle ?? "暂无",
                    detail: dominantMoodOption == nil ? "等待记录" : "本月出现最多",
                    tint: dominantMoodOption.map { Color(hex: $0.accentHex) } ?? Color(hex: "A9B0C2")
                )
                insightMetricCard(
                    title: "平均强度",
                    value: displayedMonthAverageIntensity.map(String.init) ?? "--",
                    detail: displayedMonthAverageIntensity == nil ? "暂无样本" : "分值越高越强烈",
                    tint: Color(hex: "18C92F")
                )
                insightMetricCard(
                    title: "记录密度",
                    value: "\(displayedMonthRecordedDays * 100 / max(displayedMonthDayCount, 1))%",
                    detail: "有记录的日期占比",
                    tint: Color(hex: "6C57FF")
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("高频情绪")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "222A3A"))

                if moodDistribution.isEmpty {
                    Text("本月还没有可统计的情绪分布。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                } else {
                    let topCount = moodDistribution.first?.count ?? 1
                    VStack(spacing: 12) {
                        ForEach(Array(moodDistribution.prefix(4).enumerated()), id: \.element.option.id) { _, item in
                            distributionRow(option: item.option, title: item.title, count: item.count, maxCount: topCount)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color(hex: "C9D4DF"), lineWidth: 1)
        )
        .shadow(color: Color(hex: "203047").opacity(0.09), radius: 16, x: 0, y: 8)
    }

    func mentalRecoveryOverviewCard(_ snapshot: MentalRecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("心理负荷评估")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(snapshot.summary)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "677184"))
                        .lineSpacing(3)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(snapshot.overallScore)")
                        .font(.appSystem(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: snapshot.band.accentHex))
                    Text("综合负荷")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "8C95A7"))
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                insightMetricCard(
                    title: "主导感受",
                    value: snapshot.dominantMoodTitle ?? "观察中",
                    detail: snapshot.averageIntensity.map { "平均强度 \($0)" } ?? "继续记录会更准",
                    tint: Color(hex: "39B98A")
                )
                insightMetricCard(
                    title: "连续高负荷",
                    value: "\(snapshot.repeatedHeavyDays) 天",
                    detail: snapshot.repeatedHeavyDays >= 3 ? "已经出现连续累积" : "目前更像短期波动",
                    tint: Color(hex: "F0A43A")
                )
                insightMetricCard(
                    title: "身体压力",
                    value: "\(snapshot.bodyStressLoad)",
                    detail: "结合实时压力、HRV 和静息心率",
                    tint: Color(hex: "F08B57")
                )
                insightMetricCard(
                    title: "主观体感",
                    value: snapshot.selfObservationLoad.map(String.init) ?? "--",
                    detail: snapshot.selfObservationLoad == nil ? "等待健康档案主观体感" : "来自健康档案主观体感",
                    tint: SelfObservationCatalog.assessmentTint
                )
                insightMetricCard(
                    title: "睡眠恢复",
                    value: snapshot.sleepRecoveryScore.map(String.init) ?? "--",
                    detail: snapshot.sleepRecoveryScore == nil ? "等待夜间摘要" : "越高说明夜间恢复越完整",
                    tint: Color(hex: "6C7BFF")
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.linkTitle)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "212938"))
                Text(snapshot.linkBody)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(Color(hex: snapshot.band.accentHex).opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    func mentalRecoveryTrendCard(_ snapshot: MentalRecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("情绪 - 压力 - 睡眠联动")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text("近 7 天")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "8590A3"))
            }

            if snapshot.trend.isEmpty {
                Text("最近一周的数据还不够，继续记录会逐渐连成趋势。")
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                Chart {
                    ForEach(snapshot.trend) { point in
                        AreaMark(
                            x: .value("日期", point.date),
                            y: .value("情绪负荷", point.moodLoad)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: snapshot.band.accentHex).opacity(0.24), Color(hex: snapshot.band.accentHex).opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("情绪负荷", point.moodLoad)
                        )
                        .foregroundStyle(Color(hex: snapshot.band.accentHex))
                        .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

                        if let sleepRecovery = point.sleepRecovery {
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("睡眠恢复", sleepRecovery)
                            )
                            .foregroundStyle(Color(hex: "6C7BFF"))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4]))

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("睡眠恢复", sleepRecovery)
                            )
                            .foregroundStyle(Color(hex: "6C7BFF"))
                        }

                        if let selfObservationLoad = point.selfObservationLoad {
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("档案体感负荷", selfObservationLoad)
                            )
                            .foregroundStyle(SelfObservationCatalog.assessmentTint)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [2, 4]))

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("档案体感负荷", selfObservationLoad)
                            )
                            .foregroundStyle(SelfObservationCatalog.assessmentTint)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(snapshot.trend.count, 4))) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color(hex: "E7EAF2"))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(shortDateText(date))
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color(hex: "E7EAF2"))
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)")
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 200)

                HStack(spacing: 12) {
                    trendLegendChip(title: "情绪负荷", tint: Color(hex: snapshot.band.accentHex))
                    trendLegendChip(title: "睡眠恢复", tint: Color(hex: "6C7BFF"))
                    trendLegendChip(title: "档案体感负荷", tint: SelfObservationCatalog.assessmentTint)
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    func mentalRecoveryActionsCard(_ snapshot: MentalRecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("心理恢复建议")
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            ForEach(snapshot.actions) { action in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color(hex: action.accentHex).opacity(0.14))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: action.icon)
                                .font(.appSystem(size: 16, weight: .bold))
                                .foregroundColor(Color(hex: action.accentHex))
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title)
                            .font(.appSystem(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "222938"))
                        Text(action.detail)
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color(hex: action.accentHex).opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if let cautionText = snapshot.cautionText {
                Text(cautionText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "D85C4F"))
                    .lineSpacing(3)
                    .padding(14)
                    .background(Color(hex: "FFE8E4"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    var mentalRecoveryEmptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还在等更多恢复线索")
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1E2737"))

            Text("补几条心情记录，或者等睡眠与压力数据同步后，这里会开始把最近一周的心理恢复节律连起来。")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "758093"))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    func calendarMoodBadge(option: MoodOption?, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.secondaryBackground)
                .frame(width: 40, height: 40)

            Circle()
                .stroke(Color(hex: "D7DCE4"), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 36, height: 36)

            VStack(spacing: 2) {
                Image(systemName: moodSymbol(for: option))
                    .font(.appSystem(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "A3A9B4"))

                Circle()
                    .fill(option.map { Color(hex: $0.accentHex) } ?? Color(hex: "C8CDD6"))
                    .frame(width: 4, height: 4)
                    .opacity(option == nil ? 0.55 : 0.92)
            }
        }
        .overlay(
            Circle()
                .stroke(isSelected ? Color(hex: "18C92F") : Color.clear, lineWidth: 3)
        )
    }

    func moodSymbol(for option: MoodOption?) -> String {
        guard let option else { return "face.smiling" }
        switch option.backendEmotionCode {
        case "happy":
            return "face.smiling"
        case "neutral":
            return "face.dashed"
        case "tired":
            return "moon.zzz"
        case "anxious":
            return "bolt.heart"
        case "sad":
            return "cloud.drizzle"
        default:
            return "face.smiling"
        }
    }

    func shiftMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = calendar.startOfMonth(for: month)
        if !calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
            selectedDate = displayedMonth
        }
    }

    func loadEntries() {
        localEntries = MoodStore.shared.allEntries()
    }

    @MainActor
    func loadMentalRecoverySnapshot() async {
        // 捕获发起时的日期：await 期间 selectedDate 可能已变化，避免用旧日期序列 + 新日期基准计算。
        let referenceDate = selectedDate
        let loadID = recoveryLoadID
        isLoadingRecovery = true

        let allEntries = MoodStore.shared.allEntries()
        async let sleepTask = try? HealthKitManager.shared.fetchSleepNightSummaries(days: 7, endDate: referenceDate)
        async let hrvTask = try? HealthKitManager.shared.fetchNightlyHRVAverages(days: 7, endDate: referenceDate)
        async let restingTask = try? HealthKitManager.shared.fetchDailyRestingHeartRateAverages(days: 7, endDate: referenceDate)

        let sleepSummaries = await sleepTask ?? []
        let nightlyHrv = await hrvTask ?? []
        let restingSeries = await restingTask ?? []
        let stressValue = HealthDataManager.shared.realtimeHealth?.stress_value ?? HealthDataManager.shared.currentStress?.current_stress
        let selfObservationSummaries = SelfObservationStore.shared.dailySummaries(
            days: 7,
            endingAt: referenceDate,
            scope: .healthProfileAssessments
        )

        // 日期已切换或本次加载已被取代时，丢弃过期结果，避免旧日期覆盖新日期。
        guard !Task.isCancelled, loadID == recoveryLoadID else { return }

        mentalRecoverySnapshot = recoveryAnalyzer.analyze(
            referenceDate: referenceDate,
            moodEntries: allEntries,
            sleepSummaries: sleepSummaries,
            nightlyHrv: nightlyHrv,
            restingHeartRateSeries: restingSeries,
            selfObservationSummaries: selfObservationSummaries,
            currentStress: stressValue,
            latestGAD7: latestGAD7Result,
            latestPHQ9: latestPHQ9Result
        )
        isLoadingRecovery = false
    }

    func timeText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Self.chineseLocale)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    func monthTitleText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Self.chineseLocale)
                .year()
                .month(.wide)
        )
    }

    func monthDayText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Self.chineseLocale)
                .month()
                .day()
        )
    }

    func dayNumberText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Self.chineseLocale)
                .day(.twoDigits)
        )
    }

    func weekdayText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Self.chineseLocale)
                .weekday(.wide)
        )
    }

    func displayOption(for entry: MoodEntry) -> MoodOption? {
        MoodCatalog.option(id: entry.moodID) ?? MoodCatalog.option(id: MoodCatalog.defaultOption(for: entry.backendEmotionCode).id)
    }

    @MainActor
    func loadAssessmentResults() async {
        let localGAD7 = assessmentStore.latestResult(for: .gad7)
        let localPHQ9 = assessmentStore.latestResult(for: .phq9)
        let localGAD7History = assessmentStore.results(for: .gad7)
        let localPHQ9History = assessmentStore.results(for: .phq9)

        latestGAD7Result = localGAD7
        latestPHQ9Result = localPHQ9
        gad7History = localGAD7History
        phq9History = localPHQ9History
        gad7SyncBadge = badgeText(for: localGAD7, usedHealthKit: false)
        phq9SyncBadge = badgeText(for: localPHQ9, usedHealthKit: false)
        gad7SyncStatus = healthKitStatusText(kind: .gad7, result: localGAD7, usedHealthKit: false)
        phq9SyncStatus = healthKitStatusText(kind: .phq9, result: localPHQ9, usedHealthKit: false)

        do {
            if let healthResult = try await HealthKitManager.shared.fetchLatestMentalAssessmentResult(for: .gad7) {
                latestGAD7Result = healthResult
                gad7History = mergedAssessmentHistory(localGAD7History, appending: healthResult)
                gad7SyncBadge = badgeText(for: healthResult, usedHealthKit: true)
                gad7SyncStatus = healthKitStatusText(kind: .gad7, result: healthResult, usedHealthKit: true)
            } else {
                gad7SyncBadge = badgeText(for: localGAD7, usedHealthKit: false)
                gad7SyncStatus = healthKitStatusText(kind: .gad7, result: localGAD7, usedHealthKit: false)
            }
        } catch {
            gad7SyncBadge = badgeText(for: localGAD7, usedHealthKit: false)
            gad7SyncStatus = healthKitStatusText(kind: .gad7, result: localGAD7, usedHealthKit: false)
        }

        do {
            if let healthResult = try await HealthKitManager.shared.fetchLatestMentalAssessmentResult(for: .phq9) {
                latestPHQ9Result = healthResult
                phq9History = mergedAssessmentHistory(localPHQ9History, appending: healthResult)
                phq9SyncBadge = badgeText(for: healthResult, usedHealthKit: true)
                phq9SyncStatus = healthKitStatusText(kind: .phq9, result: healthResult, usedHealthKit: true)
            } else {
                phq9SyncBadge = badgeText(for: localPHQ9, usedHealthKit: false)
                phq9SyncStatus = healthKitStatusText(kind: .phq9, result: localPHQ9, usedHealthKit: false)
            }
        } catch {
            phq9SyncBadge = badgeText(for: localPHQ9, usedHealthKit: false)
            phq9SyncStatus = healthKitStatusText(kind: .phq9, result: localPHQ9, usedHealthKit: false)
        }

        await loadMentalRecoverySnapshot()
    }

    @MainActor
    func saveAssessment(_ result: MentalAssessmentResult) {
        let storedResult = MentalAssessmentResult(
            kind: result.kind,
            recordedAt: result.recordedAt,
            answers: result.answers,
            score: result.score,
            source: .local,
            syncedToHealthKitAt: nil
        )
        assessmentStore.save(storedResult)

        Task {
            var finalResult = storedResult
            do {
                let syncedAt = try await HealthKitManager.shared.saveMentalAssessmentResult(storedResult)
                finalResult = MentalAssessmentResult(
                    kind: storedResult.kind,
                    recordedAt: storedResult.recordedAt,
                    answers: storedResult.answers,
                    score: storedResult.score,
                    source: .healthKit,
                    syncedToHealthKitAt: syncedAt
                )
                assessmentStore.save(finalResult)
            } catch {
                assessmentStore.save(storedResult)
            }
            await loadAssessmentResults()
        }
    }

    func healthKitStatusText(kind: MentalAssessmentKind, result: MentalAssessmentResult?, usedHealthKit: Bool) -> String {
        let identifier: HKScoredAssessmentTypeIdentifier = kind == .gad7 ? .GAD7 : .PHQ9
        let status = HealthKitManager.shared.authorizationStatus(for: identifier)
        switch status {
        case .sharingAuthorized:
            if usedHealthKit || result?.source == .healthKit {
                return String(localized: "当前展示的是健康 App 里的最近一次结果")
            }
            if result?.syncedToHealthKitAt != nil {
                return String(localized: "这次结果已同步到健康 App")
            }
            return String(localized: "健康 App 已授权，下一次填写会自动同步")
        case .sharingDenied:
            return String(localized: "仅保存在本地，健康 App 权限已关闭")
        case .notDetermined:
            return String(localized: "仅保存在本地，可授权同步到健康 App")
        case .none:
            return String(localized: "仅保存在本地")
        @unknown default:
            return String(localized: "仅保存在本地")
        }
    }

    func badgeText(for result: MentalAssessmentResult?, usedHealthKit: Bool) -> String? {
        guard let result else { return nil }
        if usedHealthKit || result.source == .healthKit {
            return "健康 App"
        }
        if result.syncedToHealthKitAt != nil {
            return "已同步"
        }
        return String(localized: "本地")
    }

    func badgeAccentHex(_ badge: String) -> String {
        switch badge {
        case "健康 App":
            return "18A44A"
        case "已同步":
            return "1E88E5"
        default:
            return "8E95A7"
        }
    }

    func mergedAssessmentHistory(_ history: [MentalAssessmentResult], appending result: MentalAssessmentResult) -> [MentalAssessmentResult] {
        var merged = history
        if !merged.contains(where: { $0.kind == result.kind && $0.recordedAt == result.recordedAt && $0.score == result.score }) {
            merged.append(result)
        }
        return merged.sorted { $0.recordedAt < $1.recordedAt }
    }

    func mentalAssessmentCard(kind: MentalAssessmentKind, result: MentalAssessmentResult?, syncStatus: String?, syncBadge: String?) -> some View {
        let accentHex = MentalAssessmentCatalog.accentHex(for: kind)
        let levelText = result.map { MentalAssessmentCatalog.levelText(for: kind, score: $0.score) } ?? "尚未填写"
        let isElevated = result.map { elevatedAssessmentScore(kind: kind, score: $0.score) } ?? false
        let summaryText: String
        let detailText: String
        let actionText: String
        if let result {
            summaryText = MentalAssessmentCatalog.summary(for: result)
            detailText = MentalAssessmentCatalog.detail(for: result)
            actionText = MentalAssessmentCatalog.actionText(for: result)
        } else {
            summaryText = String(localized: "先完成一次近两周问卷，这里会显示和健康 App 一致的量表结果。")
            detailText = String(localized: "问卷不会替代专业诊断，但能帮你更稳定地观察最近两周的焦虑或低落变化。")
            actionText = String(localized: "点按开始填写")
        }

        return Button {
            activeAssessmentKind = kind
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(kind.title)
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)

                            if let syncBadge {
                                Text(syncBadge)
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: badgeAccentHex(syncBadge)))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: badgeAccentHex(syncBadge)).opacity(0.12), in: Capsule())
                            }
                        }

                        Text(levelText)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(result == nil ? Color(hex: "8E95A7") : Color(hex: accentHex))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((result == nil ? Color(hex: "D8DCE5") : Color(hex: accentHex)).opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(result.map { "\($0.score)" } ?? "--")
                            .font(.appSystem(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "1B2231"))
                        Text("总分")
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "9098AA"))
                    }
                }

                if let result {
                    Text("最近填写 \(relativeDateText(result.recordedAt)) · 建议 7 天后复测")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Text(summaryText)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineSpacing(3)

                Text(detailText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "6A7487"))
                    .lineSpacing(3)

                if let syncStatus {
                    Text(syncStatus)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "6C57FF"))
                }

                Text(actionText)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isElevated ? Color(hex: "D94F45") : Color(hex: accentHex))

                if let result, isElevated {
                    Text(highRiskSupportText(kind: kind, result: result))
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "D94F45"))
                        .lineSpacing(3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .padding(16)
            .background((isElevated ? Color(hex: "FFE8E4") : Color(hex: accentHex).opacity(0.08)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isElevated ? Color(hex: "F29B92") : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    func riskTrendChart(title: String, kind: MentalAssessmentKind, results: [MentalAssessmentResult], accentHex: String) -> some View {
        let points = Array(results.suffix(8))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "2A3241"))

                Spacer(minLength: 0)

                if let latest = points.last {
                    Text("最近 \(latest.score) 分")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: accentHex))
                }
            }

            if points.isEmpty {
                Text("还没有足够的问卷历史。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "7B8394"))
            } else {
                Chart {
                    ForEach(points) { item in
                        AreaMark(
                            x: .value("日期", item.recordedAt),
                            y: .value("分数", item.score)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: accentHex).opacity(0.24), Color(hex: accentHex).opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("日期", item.recordedAt),
                            y: .value("分数", item.score)
                        )
                        .foregroundStyle(Color(hex: accentHex))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("日期", item.recordedAt),
                            y: .value("分数", item.score)
                        )
                        .foregroundStyle(Color(hex: accentHex))
                    }
                }
                .chartYScale(domain: 0...maxYScale(for: kind))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(points.count, 4))) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color(hex: "E8EBF2"))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(shortDateText(date))
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color(hex: "E8EBF2"))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)")
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 168)

                if let latest = points.last {
                    Text("当前等级：\(MentalAssessmentCatalog.levelText(for: kind, score: latest.score))")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "667183"))
                }
            }
        }
        .padding(14)
        .background(Color(hex: accentHex).opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func maxYScale(for kind: MentalAssessmentKind) -> Int {
        switch kind {
        case .gad7:
            return 21
        case .phq9:
            return 27
        }
    }

    func shortDateText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Self.chineseLocale)
                .month(.defaultDigits)
                .day(.defaultDigits)
        )
    }

    func elevatedAssessmentScore(kind: MentalAssessmentKind, score: Int) -> Bool {
        switch kind {
        case .gad7:
            return score >= 10
        case .phq9:
            return score >= 10
        }
    }

    func highRiskSupportText(kind: MentalAssessmentKind, result: MentalAssessmentResult) -> String {
        if kind == .phq9, result.answers.indices.contains(8), result.answers[8] > 0 {
            return String(localized: "如果第 9 题也让你感到困扰，请尽快联系信任的人、专业支持或使用健康 App 中的心理健康资源。")
        }
        return String(localized: "建议尽快寻求专业支持，也可以先联系信任的人，或在健康 App 中继续查看心理健康资源。")
    }

    func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Self.chineseLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func insightMetricCard(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "7C8495"))

            Text(value)
                .font(.appSystem(size: 24, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1C2231"))

            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "667183"))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func distributionRow(option: MoodOption, title: String, count: Int, maxCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(moodIconAssetName(for: option))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "202838"))

                Spacer(minLength: 0)

                Text("\(count) 次")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "768093"))
            }

            GeometryReader { proxy in
                let ratio = CGFloat(count) / CGFloat(max(maxCount, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.secondaryBackground)
                    Capsule()
                        .fill(Color(hex: option.accentHex))
                        .frame(width: max(proxy.size.width * ratio, 10))
                }
            }
            .frame(height: 10)
        }
    }

    func trendLegendChip(title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(tint)
                .frame(width: 18, height: 6)
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.secondarySurface, in: Capsule())
    }

    func timelineRow(for entry: MoodEntry, index: Int) -> some View {
        let option = displayOption(for: entry)

        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(option.map { Color(hex: $0.accentHex) } ?? Color(hex: "C9CFDA"))
                    .frame(width: 10, height: 10)

                if index != selectedDayEntries.count - 1 {
                    Rectangle()
                        .fill(Color(hex: "E4E8EF"))
                        .frame(width: 2, height: 40)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 12) {
                Image(moodIconAssetName(for: option))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .padding(3)
                    .background(Color(.systemBackground), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "1E2635"))

                    Text("\(timeText(entry.loggedAt)) · 强度 \(entry.intensity)")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)

                    if let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        Text(note)
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "5E687A"))
                            .lineLimit(2)
                    }

                    Text(entry.backendRecordedAt == nil ? "本地已记录" : "已整理进历史记录")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(entry.backendRecordedAt == nil ? Color(hex: "FF8E6E") : Color(hex: "18A44A"))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    func moodIconAssetName(for option: MoodOption?) -> String {
        guard let option else { return "EmotionNeutral" }
        switch option.backendEmotionCode {
        case "happy": return "EmotionHappy"
        case "neutral": return "EmotionNeutral"
        case "anxious": return "EmotionAnxious"
        case "sad": return "EmotionLow"
        case "tired": return "EmotionTired"
        default: return "EmotionCalm"
        }
    }

}

private struct MoodCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    let onSaved: () -> Void

    @State private var selectedLevel = 3
    @State private var phase: CapturePhase = .selection
    @State private var note = ""
    @State private var savedEntry: MoodEntry?
    @State private var isSubmitting = false
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        Group {
            switch phase {
            case .selection:
                selectionPage
            case .confirmation:
                confirmationPage
            }
        }
        .sensoryFeedback(.selection, trigger: selectedLevel)
        .animation(.easeInOut(duration: 0.34), value: selectedLevel)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var currentLevel: MoodCaptureLevel {
        MoodCaptureLevel.levels[min(max(selectedLevel, 0), MoodCaptureLevel.levels.count - 1)]
    }

    private var selectionPage: some View {
        ZStack {
            Color(hex: currentLevel.backgroundHex)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                captureHeader

                Spacer(minLength: 20)

                MoodCharacterFace(level: selectedLevel)
                    .frame(width: 190, height: 170)

                Spacer(minLength: 28)

                VStack(spacing: 4) {
                    MoodSpeechBubble(title: currentLevel.title)
                        .frame(maxWidth: .infinity, alignment: bubbleAlignment)
                        .padding(.horizontal, bubbleHorizontalPadding)

                    MoodScaleSlider(value: $selectedLevel, range: 0...6)
                        .frame(height: 44)

                    HStack {
                        Text("很难过")
                        Spacer()
                        Text("非常开心")
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "687184"))
                }
                .padding(.horizontal, 48)

                Spacer(minLength: 26)

                Button(action: recordSelection) {
                    Text(isSubmitting ? "记录中..." : "继续")
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(Color(hex: "316DF4"), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .padding(.horizontal, 26)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var confirmationPage: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            Circle()
                .fill(Color(hex: "BEE7F1").opacity(0.9))
                .frame(width: 132, height: 58)
                .blur(radius: 0.2)
                .rotationEffect(.degrees(8))
                .offset(x: 210, y: -150)

            Circle()
                .fill(Color(hex: "A9DDEA").opacity(0.9))
                .frame(width: 150, height: 64)
                .rotationEffect(.degrees(12))
                .offset(x: -205, y: -42)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    captureHeader

                    MoodRecordedMascot(level: selectedLevel)
                        .frame(width: 154, height: 168)
                        .padding(.top, 32)

                    Text("已记录")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "85858A"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: "F2EFEC"), in: Capsule())
                        .padding(.top, 10)

                    Text(recordedDateText)
                        .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "858692"))
                        .padding(.top, 24)

                    Text("“ \(currentLevel.title) ”")
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "151515"))
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        Text(currentLevel.reassurance)
                            .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "4D4E54"))

                        TextField("写下你的心情", text: $note, axis: .vertical)
                            .font(.appSystem(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "34353A"))
                            .multilineTextAlignment(.center)
                            .lineLimit(1...4)
                            .focused($noteIsFocused)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color(hex: "DDD9D5"), lineWidth: 1)
                            )
                    }
                    .padding(20)
                    .background(Color(hex: "F4F1ED"), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 36)
                    .padding(.top, 46)
                    .padding(.bottom, 120)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: finish) {
                Text("完成")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(Color(hex: "316DF4"), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(Theme.Colors.surface.opacity(0.96))
        }
    }

    private var captureHeader: some View {
        HStack {
            Button {
                if savedEntry != nil {
                    onSaved()
                }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.appSystem(size: 14, weight: .black))
                    .foregroundColor(Color(hex: "525866"))
                    .frame(width: 40, height: 40)
                    .background(Theme.Colors.surface.opacity(0.78), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")

            Spacer()

            Text("记录心情")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "444B5A").opacity(0.82))

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var bubbleAlignment: Alignment {
        switch selectedLevel {
        case 0...1: return .leading
        case 5...6: return .trailing
        default: return .center
        }
    }

    private var bubbleHorizontalPadding: CGFloat {
        switch selectedLevel {
        case 0, 6: return 0
        case 1, 5: return 52
        case 2, 4: return 108
        default: return 0
        }
    }

    private var recordedDateText: String {
        let date = savedEntry?.loggedAt ?? Date()
        return date.formatted(
            .dateTime
                .locale(Locale.autoupdatingCurrent)
                .year()
                .month()
                .day()
                .hour()
                .minute()
        )
    }

    private func recordSelection() {
        guard !isSubmitting,
              let option = MoodCatalog.option(id: currentLevel.optionID) else {
            return
        }

        isSubmitting = true

        let loggedAt = mergedDate(baseDate: selectedDate, timeSource: Date())
        let entry = MoodEntry(
            id: UUID().uuidString,
            moodID: option.id,
            title: currentLevel.title,
            backendEmotionCode: option.backendEmotionCode,
            intensity: option.defaultIntensity,
            note: nil,
            loggedAt: loggedAt,
            backendRecordedAt: nil
        )

        MoodStore.shared.save(entry)
        savedEntry = entry
        isSubmitting = false
        phase = .confirmation
    }

    private func finish() {
        if let savedEntry {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedEntry = MoodEntry(
                id: savedEntry.id,
                moodID: savedEntry.moodID,
                title: savedEntry.title,
                backendEmotionCode: savedEntry.backendEmotionCode,
                intensity: savedEntry.intensity,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                loggedAt: savedEntry.loggedAt,
                backendRecordedAt: savedEntry.backendRecordedAt
            )
            MoodStore.shared.save(updatedEntry)
        }
        onSaved()
        dismiss()
    }

    func mergedDate(baseDate: Date, timeSource: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeSource)
        return calendar.date(from: DateComponents(
            year: baseComponents.year,
            month: baseComponents.month,
            day: baseComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute
        )) ?? timeSource
    }
}

private extension MoodCaptureSheet {
    enum CapturePhase {
        case selection
        case confirmation
    }
}

private struct MoodCaptureLevel {
    let optionID: String
    let title: String
    let backgroundHex: String
    let reassurance: String

    static let levels: [MoodCaptureLevel] = [
        MoodCaptureLevel(optionID: "sad", title: "很难过", backgroundHex: "9CB7DC", reassurance: "先照顾好自己，慢慢往前走…"),
        MoodCaptureLevel(optionID: "lonely", title: "不太开心", backgroundHex: "ABC5E6", reassurance: "允许自己停一停，再慢慢出发…"),
        MoodCaptureLevel(optionID: "wronged", title: "有点小情绪", backgroundHex: "B4CDEA", reassurance: "小情绪也值得被认真听见…"),
        MoodCaptureLevel(optionID: "calm", title: "不喜不悲", backgroundHex: "B3DEE8", reassurance: "保持平静，继续前行…"),
        MoodCaptureLevel(optionID: "happy", title: "还不错", backgroundHex: "F9DC8D", reassurance: "把这份轻松留在今天…"),
        MoodCaptureLevel(optionID: "moved", title: "愉快", backgroundHex: "F9C17E", reassurance: "记住这份愉快，继续前行…"),
        MoodCaptureLevel(optionID: "excited", title: "非常开心", backgroundHex: "F6AA8F", reassurance: "把今天的快乐好好收藏…")
    ]
}

private struct MoodScaleSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        GeometryReader { proxy in
            let thumbDiameter: CGFloat = 32
            let usableWidth = max(proxy.size.width - thumbDiameter, 1)
            let stepCount = max(range.upperBound - range.lowerBound, 1)
            let progress = CGFloat(value - range.lowerBound) / CGFloat(stepCount)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.09))
                    .frame(height: 34)
                    .padding(.horizontal, thumbDiameter / 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                    .offset(x: progress * usableWidth)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let rawProgress = min(max((gesture.location.x - thumbDiameter / 2) / usableWidth, 0), 1)
                        let rawValue = CGFloat(range.lowerBound) + rawProgress * CGFloat(stepCount)
                        value = Int(rawValue.rounded())
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("心情程度")
        .accessibilityValue(MoodCaptureLevel.levels[value].title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 1, range.upperBound)
            case .decrement:
                value = max(value - 1, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
}

private struct MoodSpeechBubble: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "646A77"))
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .offset(y: 5)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.bottom, 8)
    }
}

private struct MoodHeroAnimatedFace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Int

    @State private var isFloating = false

    var body: some View {
        MoodCharacterFace(level: level)
            .scaleEffect(reduceMotion ? 1 : (isFloating ? 1.02 : 0.98))
            .offset(y: reduceMotion ? 0 : (isFloating ? -4 : 3))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.9).repeatForever(autoreverses: true),
                value: isFloating
            )
            .onAppear {
                isFloating = !reduceMotion
            }
            .onChange(of: reduceMotion) { _, newValue in
                isFloating = !newValue
            }
            .accessibilityHidden(true)
    }
}

private struct MoodCharacterFace: View {
    let level: Int

    private var isLow: Bool { level <= 2 }
    private var isHappy: Bool { level >= 4 }

    var body: some View {
        ZStack {
            if isHappy {
                HStack(spacing: 82) {
                    cheek
                    cheek
                }
                .offset(y: 36)
            }

            HStack(spacing: -5) {
                eye(isLeft: true)
                eye(isLeft: false)
            }
            .offset(y: -12)

            if level != 3 {
                HStack(spacing: 34) {
                    eyebrow(isLeft: true)
                    eyebrow(isLeft: false)
                }
                .offset(y: -58)
            }

            Circle()
                .fill(Color(hex: "F26722"))
                .frame(width: 48, height: 48)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .offset(x: 11, y: 9)
                }
                .offset(y: 21)

            MoodMouth(level: level)
                .stroke(Color(hex: "55433B"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 54, height: 38)
                .offset(y: 62)

            if level == 0 {
                HStack(spacing: 69) {
                    Image(systemName: "drop.fill")
                    Image(systemName: "drop.fill")
                }
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(Theme.Colors.onAccent.opacity(0.88))
                .offset(y: 52)
            }
        }
    }

    private func eye(isLeft: Bool) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 55, height: 68)
            .overlay {
                Circle()
                    .fill(Color(hex: "57443C"))
                    .frame(width: 25, height: 25)
                    .offset(x: pupilOffset(isLeft: isLeft), y: isLow ? 5 : (isHappy ? 4 : 0))
            }
            .rotationEffect(.degrees(isLow ? (isLeft ? 8 : -8) : 0))
    }

    private func pupilOffset(isLeft: Bool) -> CGFloat {
        switch level {
        case 0...2: return isLeft ? 5 : -5
        case 4...6: return isLeft ? 4 : -4
        default: return 0
        }
    }

    private func eyebrow(isLeft: Bool) -> some View {
        Capsule()
            .fill(isLow ? Color.white : Color(hex: "55433B"))
            .frame(width: 25, height: 3)
            .rotationEffect(.degrees(isLow ? (isLeft ? -18 : 18) : (isLeft ? -8 : -8)))
    }

    private var cheek: some View {
        Circle()
            .fill(Color(hex: "F47B2C").opacity(0.78))
            .frame(width: 48, height: 48)
            .blur(radius: 5)
    }
}

nonisolated private struct MoodMouth: Shape {
    let level: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + 5, y: rect.midY)
        let end = CGPoint(x: rect.maxX - 5, y: rect.midY)
        path.move(to: start)

        if level <= 2 {
            path.addQuadCurve(to: end, control: CGPoint(x: rect.midX, y: rect.minY + CGFloat(level) * 3))
        } else if level == 3 {
            path.addLine(to: end)
        } else {
            path.addQuadCurve(to: end, control: CGPoint(x: rect.midX, y: rect.maxY - CGFloat(6 - level) * 2))
        }
        return path
    }
}

private struct MoodRecordedMascot: View {
    let level: Int

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(Color(hex: "FFD76B"))
                .frame(width: 146, height: 154)
                .overlay {
                    MoodCharacterFace(level: max(level, 4))
                        .scaleEffect(0.62)
                        .offset(y: 10)
                }

            Capsule()
                .stroke(Color(hex: "D5AA31"), lineWidth: 4)
                .frame(width: 74, height: 15)
                .offset(y: 8)
        }
    }
}

private struct MentalAssessmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: MentalAssessmentKind
    let onSaved: (MentalAssessmentResult) -> Void

    @State private var answers: [Int: MentalAssessmentOption] = [:]

    private var questions: [MentalAssessmentQuestion] {
        MentalAssessmentCatalog.questions(for: kind)
    }

    private var allAnswered: Bool {
        answers.count == questions.count
    }

    private var selectedAnswers: [MentalAssessmentOption] {
        questions.compactMap { answers[$0.index] }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind.title)
                            .font(.appSystem(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "151B28"))

                        Text("请回想最近两周的状态，按最接近的频率选择。")
                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                    }

                    VStack(spacing: 14) {
                        ForEach(questions) { question in
                            assessmentQuestionCard(question)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
            .background(
                LinearGradient(
                    colors: [Color(hex: "FFF7F4"), Color(hex: "FFFFFF"), Color(hex: "F7FAFF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    saveAssessment()
                } label: {
                    Text(allAnswered ? "保存问卷结果" : "请先完成全部题目")
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background((allAnswered ? Color(hex: MentalAssessmentCatalog.accentHex(for: kind)) : Color(hex: "B8C0CE")), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!allAnswered)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Theme.Colors.surface.opacity(0.96))
            }
        }
    }

    func assessmentQuestionCard(_ question: MentalAssessmentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(question.index). \(question.prompt)")
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineSpacing(3)

            VStack(spacing: 10) {
                ForEach(MentalAssessmentOption.allCases) { option in
                    Button {
                        answers[question.index] = option
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "2A3241"))

                            Spacer(minLength: 0)

                            Circle()
                                .stroke(Color(hex: answers[question.index] == option ? MentalAssessmentCatalog.accentHex(for: kind) : "CBD1DE"), lineWidth: 2)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .fill(Color(hex: MentalAssessmentCatalog.accentHex(for: kind)))
                                        .frame(width: 10, height: 10)
                                        .opacity(answers[question.index] == option ? 1 : 0)
                                )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background((answers[question.index] == option ? Color(hex: MentalAssessmentCatalog.accentHex(for: kind)).opacity(0.10) : Color.white.opacity(0.92)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    func saveAssessment() {
        guard allAnswered else { return }
        let result = MentalAssessmentResult(
            kind: kind,
            recordedAt: Date(),
            answers: selectedAnswers.map(\.rawValue),
            score: MentalAssessmentCatalog.score(for: selectedAnswers),
            source: .local,
            syncedToHealthKitAt: nil
        )
        onSaved(result)
        dismiss()
    }
}

private struct MentalAssessmentEducationSheet: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("问卷说明")
                    .font(.appSystem(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "171D2A"))

                educationCard(
                    title: "GAD-7 是什么？",
                    body: "GAD-7 用来回看最近两周的焦虑困扰程度，更适合按周观察变化，而不是把一次结果当成最终判断。"
                )

                educationCard(
                    title: "PHQ-9 是什么？",
                    body: "PHQ-9 用来回看最近两周的低落、疲惫和兴趣下降等状态。它能帮助你识别趋势，但不能替代专业诊断。"
                )

                educationCard(
                    title: "怎么看待结果？",
                    body: "结果更适合和睡眠、活动、社交支持以及最近的生活事件放在一起看。如果分数持续偏高，建议尽快寻求专业支持。"
                )

                // MARK: - 量表来源与引用
                VStack(alignment: .leading, spacing: 14) {
                    Text("量表来源")
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "171D2A"))

                    citationCard(for: .gad7)
                    citationCard(for: .phq9)

                    Button {
                        openURL(MentalAssessmentCatalog.phqScreenersURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.appSystem(size: 13, weight: .bold))
                            Text("Pfizer 官方 PHQ 屏查量表页面（含中文版下载）")
                                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "4B6EF4"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "FFF7F4"), Color.white, Color(hex: "F7FAFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    func educationCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appSystem(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1D2433"))

            Text(body)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "647082"))
                .lineSpacing(4)
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    func citationCard(for kind: MentalAssessmentKind) -> some View {
        let citation = MentalAssessmentCatalog.citation(for: kind)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: MentalAssessmentCatalog.accentHex(for: kind)))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: MentalAssessmentCatalog.accentHex(for: kind)).opacity(0.10), in: Capsule())

                Text(citation.title)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "1D2433"))
                    .lineSpacing(2)
            }

            Text(citation.authors)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "647082"))

            Text(citation.journal)
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "647082"))

            Button {
                openURL(citation.url)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.appSystem(size: 12, weight: .bold))
                    Text("查看文献原文（PubMed）")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(hex: "4B6EF4"))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }
}

private extension Calendar {
    func startOfMonth(for referenceDate: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: referenceDate)) ?? startOfDay(for: referenceDate)
    }
}

#Preview {
    MoodLogView()
}
