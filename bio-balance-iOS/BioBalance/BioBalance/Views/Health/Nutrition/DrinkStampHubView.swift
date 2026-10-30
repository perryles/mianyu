/// DrinkStampHubView 由健康首页饮水/咖啡入口调用，作为「饮品记录」Hub 页。
/// 负责展示水/咖啡因/饮品戳三种模式的月度统计、日历与拍照识别记录。

import Combine
import PhotosUI
import SwiftUI

private enum DrinkHubMode: String, CaseIterable, Identifiable {
    case water
    case caffeine
    case stamps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water:
            return String(localized: "喝水")
        case .caffeine:
            return String(localized: "咖啡因")
        case .stamps:
            return String(localized: "饮品")
        }
    }

    var symbol: String {
        switch self {
        case .water:
            return "drop.fill"
        case .caffeine:
            return "cup.and.saucer.fill"
        case .stamps:
            return "seal.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .water:
            return "4B9CEB"
        case .caffeine:
            return "8F6645"
        case .stamps:
            return "FF8B2B"
        }
    }

    var strongAccentHex: String {
        switch self {
        case .water:
            return "2E7BC4"
        case .caffeine:
            return "6F4A2E"
        case .stamps:
            return "F0741F"
        }
    }

    var softHex: String {
        switch self {
        case .water:
            return "E3F0FC"
        case .caffeine:
            return "F3EBE3"
        case .stamps:
            return "FFF0DE"
        }
    }

    var backgroundHex: String {
        switch self {
        case .water:
            return "E3F0FC"
        case .caffeine:
            return "F3EBE3"
        case .stamps:
            return "FFF0DE"
        }
    }

    var valueTitle: String {
        switch self {
        case .water:
            return String(localized: "每日平均")
        case .caffeine:
            return String(localized: "每日平均")
        case .stamps:
            return String(localized: "本月总计")
        }
    }

    var unit: String {
        switch self {
        case .water:
            return "ml"
        case .caffeine:
            return "mg"
        case .stamps:
            return String(localized: "杯")
        }
    }
}

struct DrinkStampHubView: View {
    @Bindable var habitViewModel: HabitViewModel
    private let recognitionService = PhotoRecognitionService.shared
    private let actionRecordStore = ActionRecordStore.shared
    @State private var selectedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedCalendarDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedMode: DrinkHubMode = .water
    @State private var showingQuickRecord = false
    @State private var showingCoffeeRecord = false
    @State private var selectedPreset: DrinkPreset = .water
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingRecognition: PhotoRecognitionResult?
    @State private var workingStoreName = ""
    @State private var workingCityName = ""
    @State private var workingDrinkName = ""
    @State private var workingCapturedAt = Date()
    @State private var isRecognizing = false
    @State private var recognitionError: String?
    @State private var monthlyWaterByDay: [String: Int] = [:]
    @State private var monthlyCaffeineByDay: [String: Int] = [:]
    @State private var isLoadingMonthMetrics = false
    @State private var monthMetricsLoadID = UUID()
    @State private var actionRecordRefreshID = UUID()

    private let store = DrinkExperienceStore.shared

    var body: some View {
        ZStack {
            HealthDetailPageBackground(
                topGlow: Color(hex: "AEEBFA"),
                lowerGlow: Color(hex: "CDEFE8")
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    modeSelector
                    referenceStatsGrid
                    drinkAnalyticsCard
                    calendarCard
                    selectedDayDetailCard
                    stampGalleryCard
                    quickActionsSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 120)
            }
        }
        .healthDetailNavigation(title: HealthPageName.hydration)
        .sheet(isPresented: $showingQuickRecord) {
            DrinkCheckinSheet(viewModel: habitViewModel, initialPreset: selectedPreset)
                .adaptiveSheetChrome(style: .page, detents: [.large], dragIndicator: .visible)
        }
        .sheet(isPresented: $showingCoffeeRecord) {
            NavigationStack {
                CoffeeConfirmSheet(viewModel: habitViewModel)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .confirmationDialog("选择图片来源", isPresented: $showingSourcePicker, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照") { showingCamera = true }
            }
            Button("从相册选择") {
                showingPhotoLibrary = true
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingCamera) {
            SystemImagePicker(sourceType: .camera) { image in
                handleCameraImage(image)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $selectedPhotoItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: selectedPhotoItem) { _, item in
            loadSelectedPhoto(item)
        }
        .sheet(item: $pendingRecognition) { recognition in
            NavigationStack {
                DrinkRecognitionConfirmationView(
                    recognition: recognition,
                    storeName: $workingStoreName,
                    cityName: $workingCityName,
                    drinkName: $workingDrinkName,
                    capturedAt: $workingCapturedAt,
                    onConfirm: { confirmRecognition(recognition) }
                )
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .task(id: monthKey(for: selectedMonth)) {
            if await store.synchronizePrivateCloud() {
                actionRecordRefreshID = UUID()
            }
            await loadMonthMetrics()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileVitalityRecordsDidChange)) { _ in
            actionRecordRefreshID = UUID()
            Task {
                await loadMonthMetrics()
            }
        }
    }
}

private extension DrinkStampHubView {
    // 文字与结构色对齐 DietDesignTokens 三级灰
    var card: Color { Color.white }
    var ink: Color { DietDesignTokens.textPrimary }
    var softInk: Color { DietDesignTokens.textSecondary }
    // 数据强调色与饮食页 Token 同源:蓝(水)/棕(咖啡)/绿(达标)/琥珀(提醒)
    var cocoa: Color { DietDesignTokens.accentBlue }
    var latte: Color { Color(hex: "4B9CEB") }
    var sage: Color { DietDesignTokens.accentGreen }
    var butter: Color { Color(hex: "8F6645") }
    var modeAccent: Color { Color(hex: selectedMode.accentHex) }
    var modeStrongAccent: Color { Color(hex: selectedMode.strongAccentHex) }

    var summary: DrinkMonthSummary {
        store.summary(for: selectedMonth)
    }

    var actionRecordsByDay: [String: LocalActionDayRecord] {
        _ = actionRecordRefreshID
        var mapped: [String: LocalActionDayRecord] = [:]
        for record in actionRecordStore.allRecords() {
            mapped[dayKey(for: record.date)] = record
        }
        return mapped
    }

    var currentMonthActionRecords: [LocalActionDayRecord] {
        actionRecordStore.allRecords().filter {
            Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    var selectedModeValues: [Int] {
        switch selectedMode {
        case .water:
            return summary.calendarDays.filter(\.inCurrentMonth).map { metricValue(for: $0) }.filter { $0 > 0 }
        case .caffeine:
            return summary.calendarDays.filter(\.inCurrentMonth).map { metricValue(for: $0) }.filter { $0 > 0 }
        case .stamps:
            return summary.calendarDays.filter(\.inCurrentMonth).map(\.recordCount).filter { $0 > 0 }
        }
    }

    var selectedModeActiveDays: Int {
        selectedModeValues.count
    }

    var selectedModeTotal: Int {
        selectedModeValues.reduce(0, +)
    }

    var selectedModeAverage: Int {
        guard !selectedModeValues.isEmpty else { return 0 }
        return Int((Double(selectedModeTotal) / Double(selectedModeValues.count)).rounded())
    }

    var selectedModeMax: Int {
        selectedModeValues.max() ?? 0
    }

    var selectedModeMin: Int {
        selectedModeValues.min() ?? 0
    }

    var selectedMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy.MM"
        return formatter.string(from: selectedMonth)
    }

    var modeCalendarSubtitle: String {
        switch selectedMode {
        case .water:
            return String(localized: "圆点下方显示当天累计饮水量。")
        case .caffeine:
            return String(localized: "圆点下方显示当天累计咖啡因。")
        case .stamps:
            return String(localized: "圆点下方显示当天饮品印章数量。")
        }
    }

    var todayMetricTitle: String {
        switch selectedMode {
        case .water:
            return String(localized: "今日补水")
        case .caffeine:
            return String(localized: "今日咖啡因")
        case .stamps:
            return String(localized: "今日饮品")
        }
    }

    var todayMetricValue: String {
        switch selectedMode {
        case .water:
            return habitViewModel.hydrationHeadlineText
        case .caffeine:
            return "\(habitViewModel.caffeineAmount)mg"
        case .stamps:
            let count = summary.calendarDays.first { day in
                day.dateKey == dayKey(for: Date())
            }?.recordCount ?? 0
            return String(localized: "\(count)杯")
        }
    }

    var selectedModePrimaryValue: String {
        guard selectedModeActiveDays > 0 else { return "-" }
        switch selectedMode {
        case .water, .caffeine:
            return "\(selectedModeAverage)\(selectedMode.unit)"
        case .stamps:
            return "\(selectedModeTotal)\(selectedMode.unit)"
        }
    }

    var selectedModeMaxTitle: String {
        switch selectedMode {
        case .water:
            return String(localized: "最多的一天")
        case .caffeine:
            return String(localized: "最多的一天")
        case .stamps:
            return String(localized: "最高单日")
        }
    }

    var selectedModeMaxValue: String {
        selectedModeMax > 0 ? "\(selectedModeMax)\(selectedMode.unit)" : "-"
    }

    var selectedModeMinTitle: String {
        switch selectedMode {
        case .water:
            return String(localized: "最少的一天")
        case .caffeine:
            return String(localized: "最少的一天")
        case .stamps:
            return String(localized: "活跃日均")
        }
    }

    var selectedModeMinValue: String {
        guard selectedModeActiveDays > 0 else { return "-" }
        switch selectedMode {
        case .water, .caffeine:
            return "\(selectedModeMin)\(selectedMode.unit)"
        case .stamps:
            return String(format: String(localized: "%.1f杯"), averageCupsPerActiveDay)
        }
    }

    var activeDrinkDays: Int {
        summary.calendarDays.filter { $0.inCurrentMonth && $0.hasRecord }.count
    }

    var currentMonthDayCount: Int {
        max(1, summary.calendarDays.filter(\.inCurrentMonth).count)
    }

    var drinkActiveRate: Double {
        min(1, Double(activeDrinkDays) / Double(currentMonthDayCount))
    }

    var bestDayDrinkCount: Int {
        summary.calendarDays.filter(\.inCurrentMonth).map(\.recordCount).max() ?? 0
    }

    var averageCupsPerActiveDay: Double {
        guard activeDrinkDays > 0 else { return 0 }
        return Double(summary.cupCount) / Double(activeDrinkDays)
    }

    var waterProgress: Double {
        guard habitViewModel.waterTarget > 0 else { return 0 }
        return min(1, Double(habitViewModel.waterAmount) / Double(max(1, habitViewModel.waterTarget)))
    }

    var caffeineLimit: Int { 400 }

    var caffeineProgress: Double {
        min(1, Double(habitViewModel.caffeineAmount) / Double(caffeineLimit))
    }

    var remainingWaterMl: Int {
        max(0, habitViewModel.waterTarget - habitViewModel.waterAmount)
    }

    var monthDrinkBins: [Int] {
        let days = summary.calendarDays.filter(\.inCurrentMonth)
        guard !days.isEmpty else { return [0, 0, 0, 0] }

        return stride(from: 0, to: days.count, by: 7).map { startIndex in
            let endIndex = min(startIndex + 7, days.count)
            return days[startIndex..<endIndex].reduce(0) { $0 + $1.recordCount }
        }
    }

    var selectedCalendarDay: DrinkCalendarDay? {
        let selectedKey = dayKey(for: selectedCalendarDate)
        return summary.calendarDays.first { $0.dateKey == selectedKey && $0.inCurrentMonth }
    }

    var selectedCalendarDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M月d日 E"
        return formatter.string(from: selectedCalendarDate)
    }

    var selectedDayMetricValue: Int {
        guard let selectedCalendarDay else { return 0 }
        return metricValue(for: selectedCalendarDay)
    }

    var selectedDayDetailTitle: String {
        switch selectedMode {
        case .water:
            return "喝水"
        case .caffeine:
            return "咖啡因"
        case .stamps:
            return String(localized: "饮品")
        }
    }

    var selectedDayDetailSubtitle: String {
        switch selectedMode {
        case .water:
            return selectedDayMetricValue > 0 ? "当日累计补水" : "当天暂无喝水记录"
        case .caffeine:
            return selectedDayMetricValue > 0 ? "当日累计咖啡因" : "当天暂无咖啡因记录"
        case .stamps:
            return selectedDayMetricValue > 0 ? "当日饮品印章" : "当天暂无饮品印章"
        }
    }

    var selectedDayMetricText: String {
        guard selectedDayMetricValue > 0 else { return "--" }
        switch selectedMode {
        case .water:
            return "\(selectedDayMetricValue)ml"
        case .caffeine:
            return "\(selectedDayMetricValue)mg"
        case .stamps:
            return String(localized: "\(selectedDayMetricValue)杯")
        }
    }

    var background: some View {
        // 与饮食主页一致的冷灰紫底,页面统一视觉体系
        DietDesignTokens.background.ignoresSafeArea()
    }

    // MARK: Hero（v3：大号当前值 + 幽灵单位 + 目标上下文）

    var heroCard: some View {
        ModernReportHero(
            eyebrow: String(localized: "饮水与习惯"),
            title: selectedMode.title,
            value: heroPrimaryValue,
            unit: heroPrimaryUnit,
            ghostUnit: heroGhostUnit,
            captions: [
                ModernReportCaption(symbol: "calendar", text: selectedMonthTitle),
                ModernReportCaption(symbol: "target", text: heroTargetText)
            ],
            badge: ModernReportBadge(
                symbol: selectedMode.symbol,
                text: String(localized: "今日完成 \(heroProgressPercentText)"),
                tint: modeStrongAccent
            ),
            accent: modeAccent,
            symbol: selectedMode.symbol
        )
    }

    var heroPrimaryValue: String {
        switch selectedMode {
        case .water:
            return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(habitViewModel.waterAmount) / 1000)
        case .caffeine:
            return "\(habitViewModel.caffeineAmount)"
        case .stamps:
            let count = summary.calendarDays.first { day in
                day.dateKey == dayKey(for: Date())
            }?.recordCount ?? 0
            return "\(count)"
        }
    }

    var heroPrimaryUnit: String {
        switch selectedMode {
        case .water: return "L"
        case .caffeine: return "MG"
        case .stamps: return String(localized: "杯")
        }
    }

    var heroGhostUnit: String {
        switch selectedMode {
        case .water: return "L"
        case .caffeine: return "MG"
        case .stamps: return "COUNT"
        }
    }

    var heroTargetText: String {
        switch selectedMode {
        case .water:
            return String(localized: "目标 \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(habitViewModel.waterTarget) / 1000)) L")
        case .caffeine:
            return String(localized: "建议上限 \(caffeineLimit) MG")
        case .stamps:
            return String(localized: "本月 \(summary.cupCount) 杯")
        }
    }

    var todayMetricUnit: String {
        switch selectedMode {
        case .water: return "ml"
        case .caffeine: return "mg"
        case .stamps: return String(localized: "杯")
        }
    }

    var heroProgressFraction: Double {
        switch selectedMode {
        case .water: return waterProgress
        case .caffeine: return caffeineProgress
        case .stamps:
            guard selectedModeActiveDays > 0 else { return 0 }
            return min(1, Double(selectedModeActiveDays) / Double(currentMonthDayCount))
        }
    }

    var heroProgressPercentText: String {
        "\(Int((min(max(heroProgressFraction, 0), 1) * 100).rounded()))%"
    }

    var heroAdviceText: String {
        switch selectedMode {
        case .water:
            if habitViewModel.waterAmount >= habitViewModel.waterTarget {
                return String(localized: "今天已达到饮水目标，后续按口渴感少量补充即可。")
            }
            return String(localized: "今天还差 \(remainingWaterMl)ml，建议分成几次小杯补齐。")
        case .caffeine:
            if habitViewModel.caffeineAmount >= caffeineLimit {
                return String(localized: "今日咖啡因已经接近或超过建议上限，后面适合切换到无咖啡因饮品。")
            }
            return String(localized: "今日还剩约 \(max(0, caffeineLimit - habitViewModel.caffeineAmount))mg 建议额度，下午后尽量少补刺激。")
        case .stamps:
            return String(localized: "本月已留下 \(summary.cupCount) 杯 · \(summary.storeCount) 店铺 · \(summary.cityCount) 城市记录。")
        }
    }

    var modeSelector: some View {
        VStack(spacing: 8) {
            ModernReportSegmentedPicker(
                selection: $selectedMode,
                options: DrinkHubMode.allCases.map {
                    ModernReportPickerOption(value: $0, title: $0.title)
                }
            )

            HStack(spacing: 10) {
                Text(selectedMonthTitle)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(DietDesignTokens.textSecondary)
                Spacer(minLength: 8)
                monthStepper
            }
        }
    }

    func modeButton(_ mode: DrinkHubMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.appSystem(size: 12, weight: .black))
                Text(mode.title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : DietDesignTokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color(hex: mode.strongAccentHex) : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    var monthStepper: some View {
        HStack(spacing: 10) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.appSystem(size: 12, weight: .bold))
            }

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
            }
        }
        .foregroundColor(modeStrongAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: selectedMode.softHex), in: Capsule())
    }

    var referenceStatsGrid: some View {
        ModernReportMetricsPanel(
            title: String(localized: "饮水与习惯"),
            metrics: [
                ModernReportMetric(
                    title: String(localized: "今日饮水"),
                    value: String(format: "%.1f L", locale: Locale(identifier: "en_US_POSIX"), Double(habitViewModel.waterAmount) / 1000),
                    tint: Color(hex: "2E7BC4"),
                    symbol: "drop.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "连续记录"),
                    value: String(localized: "\(selectedModeActiveDays) 天"),
                    tint: Color(hex: "27C768"),
                    symbol: "calendar.badge.checkmark"
                ),
                ModernReportMetric(
                    title: String(localized: "活动消耗"),
                    value: String(localized: "\(habitViewModel.activeEnergy) kcal"),
                    tint: Color(hex: "FF9A32"),
                    symbol: "flame.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "今日步数"),
                    value: String(localized: "\(habitViewModel.stepCount) 步"),
                    tint: Color(hex: "8068FF"),
                    symbol: "shoeprints.fill"
                )
            ]
        )
    }

    func referenceStatCard(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundColor(value == "-" ? DietDesignTokens.textTertiary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(DietDesignTokens.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    var drinkAnalyticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("图表统计")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Text("把今天的补水、咖啡因和本月饮品节律放在一起看")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(softInk)
                }

                Spacer(minLength: 12)

                Text(summary.displayTitle)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(cocoa)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.secondarySurface, in: Capsule())
            }

            HStack(spacing: 12) {
                ringMetric(
                    title: "今日补水",
                    value: "\(Int((waterProgress * 100).rounded()))%",
                    subtitle: remainingWaterMl == 0 ? "已达目标" : "还差 \(remainingWaterMl)ml",
                    progress: waterProgress,
                    accent: latte,
                    symbol: "drop.fill"
                )

                ringMetric(
                    title: "咖啡因",
                    value: "\(habitViewModel.caffeineAmount)mg",
                    subtitle: "建议上限 \(caffeineLimit)mg",
                    progress: caffeineProgress,
                    accent: butter,
                    symbol: "cup.and.saucer.fill"
                )
            }

            monthlyDrinkBarChart

            LazyVGrid(columns: drinkAnalyticsColumns, spacing: 10) {
                analyticsTile(title: "活跃率", value: "\(Int((drinkActiveRate * 100).rounded()))", unit: "%", accent: sage)
                analyticsTile(title: "最高单日", value: "\(bestDayDrinkCount)", unit: "杯", accent: latte)
                analyticsTile(title: "活跃日均", value: String(format: "%.1f", averageCupsPerActiveDay), unit: "杯", accent: butter)
                analyticsTile(title: "本月总计", value: "\(summary.cupCount)", unit: "杯", accent: cocoa)
            }
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
    }

    var monthlyDrinkBarChart: some View {
        let bins = monthDrinkBins
        let maxCount = max(bins.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本月饮品分布")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(softInk)
                Spacer()
                Text("\(summary.cupCount) 杯")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(cocoa)
            }

            HStack(alignment: .bottom, spacing: 9) {
                ForEach(Array(bins.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(count > 0 ? latte.opacity(0.42 + Double(index) * 0.08) : DietDesignTokens.divider)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22 + CGFloat(count) / CGFloat(maxCount) * 58)
                            .overlay(alignment: .top) {
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.appSystem(size: 10, weight: .black, design: .rounded))
                                        .foregroundColor(cocoa)
                                        .padding(.top, 6)
                                }
                            }

                        Text("W\(index + 1)")
                            .font(.appSystem(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(softInk.opacity(0.78))
                    }
                }
            }
            .frame(height: 108, alignment: .bottom)
        }
        .padding(14)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var drinkAnalyticsColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    func ringMetric(
        title: String,
        value: String,
        subtitle: String,
        progress: Double,
        accent: Color,
        symbol: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.16), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(softInk)
                Text(value)
                    .font(.appSystem(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(subtitle)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(softInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func analyticsTile(title: String, value: String, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(softInk)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(softInk)
                    .lineLimit(1)
            }
            Capsule()
                .fill(accent.opacity(0.34))
                .frame(width: 34, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var calendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selectedMode.title)月历")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Text(modeCalendarSubtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(softInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(selectedMonthTitle)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(modeStrongAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(hex: selectedMode.softHex), in: Capsule())
            }

            VStack(spacing: 10) {
                let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
                HStack {
                    ForEach(weekdays, id: \.self) { title in
                        Text(title)
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(softInk)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                    ForEach(summary.calendarDays) { day in
                        calendarCell(day)
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
    }

    func calendarCell(_ day: DrinkCalendarDay) -> some View {
        let value = metricValue(for: day)
        let hasValue = value > 0
        let isSelected = selectedCalendarDay?.dateKey == day.dateKey
        return Button {
            guard day.inCurrentMonth, let date = date(fromDayKey: day.dateKey) else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedCalendarDate = date
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(calendarCircleFill(day: day, hasValue: hasValue))
                        .overlay(
                            Circle()
                                .stroke(isSelected ? modeStrongAccent : (hasValue ? modeStrongAccent.opacity(0.74) : Color.clear), lineWidth: isSelected ? 3 : 2)
                        )
                        .frame(width: 42, height: 42)

                    if selectedMode == .stamps, hasValue, let url = day.thumbnailURL, let resolved = URL(string: url) {
                        AsyncImage(url: resolved) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(7)
                        } placeholder: {
                            Text("\(day.dayNumber)")
                                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("\(day.dayNumber)")
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(calendarDayTextColor(day: day, hasValue: hasValue))
                    }
                }

                Text(calendarValueLabel(day: day, value: value))
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(hasValue ? modeStrongAccent : softInk.opacity(day.inCurrentMonth ? 0.52 : 0.24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(height: 13)
            }
            .frame(height: 62)
            .opacity(day.inCurrentMonth ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .disabled(!day.inCurrentMonth)
    }

    func calendarCircleFill(day: DrinkCalendarDay, hasValue: Bool) -> Color {
        guard day.inCurrentMonth else { return Color(hex: "F0EFF4") }
        return hasValue ? modeAccent : Color(hex: "ECEBF1")
    }

    func calendarDayTextColor(day: DrinkCalendarDay, hasValue: Bool) -> Color {
        if hasValue {
            return .white
        }
        return day.inCurrentMonth ? ink.opacity(0.82) : softInk.opacity(0.36)
    }

    func calendarValueLabel(day: DrinkCalendarDay, value: Int) -> String {
        guard day.inCurrentMonth else { return "" }
        guard value > 0 else { return "-" }
        switch selectedMode {
        case .water:
            return "\(value)ml"
        case .caffeine:
            return "\(value)mg"
        case .stamps:
            return "x\(value)"
        }
    }

    func metricValue(for day: DrinkCalendarDay) -> Int {
        switch selectedMode {
        case .water:
            if let value = monthlyWaterByDay[day.dateKey], value > 0 {
                return value
            }
            return actionRecordsByDay[day.dateKey]?.waterMl ?? 0
        case .caffeine:
            if let value = monthlyCaffeineByDay[day.dateKey], value > 0 {
                return value
            }
            return actionRecordsByDay[day.dateKey]?.caffeineMg ?? 0
        case .stamps:
            return day.recordCount
        }
    }

    var selectedDayDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDayDetailTitle)
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Text("\(selectedCalendarDateTitle) · \(selectedDayDetailSubtitle)")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(softInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    selectedPreset = selectedMode == .caffeine ? .americano : .water
                    showingQuickRecord = true
                } label: {
                    Image(systemName: "plus")
                        .font(.appSystem(size: 16, weight: .black))
                        .foregroundColor(modeStrongAccent)
                        .frame(width: 44, height: 34)
                        .background(Color(hex: selectedMode.softHex), in: Capsule())
                }
                .buttonStyle(.plain)
                .opacity(selectedMode == .stamps ? 0 : 1)
                .disabled(selectedMode == .stamps)
            }

            if selectedMode == .stamps {
                selectedDayStampRows
            } else {
                selectedDayMetricRow
            }
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
    }

    var selectedDayMetricRow: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedMode.symbol)
                .font(.appSystem(size: 18, weight: .black))
                .foregroundColor(modeStrongAccent)
                .frame(width: 42, height: 42)
                .background(Color(hex: selectedMode.softHex), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedDayMetricValue > 0 ? "\(selectedDayDetailTitle) - \(selectedDayMetricText)" : "暂无记录")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                Text(selectedDayMetricValue > 0 ? "来自健康 App 日总量 / 本地记录" : "点击右侧加号记录一杯")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(softInk)
            }

            Spacer(minLength: 8)

            Text(selectedDayMetricText)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(selectedDayMetricValue > 0 ? modeStrongAccent : softInk.opacity(0.62))
        }
        .padding(14)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    var selectedDayStampRows: some View {
        let stamps = summary.stamps.filter { dayKey(for: $0.capturedAt) == dayKey(for: selectedCalendarDate) }
        if stamps.isEmpty {
            selectedDayMetricRow
        } else {
            VStack(spacing: 10) {
                ForEach(stamps.prefix(4)) { stamp in
                    HStack(spacing: 12) {
                        Image(systemName: "seal.fill")
                            .font(.appSystem(size: 16, weight: .black))
                            .foregroundColor(modeStrongAccent)
                            .frame(width: 38, height: 38)
                            .background(Color(hex: selectedMode.softHex), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(stamp.drinkName)
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(ink)
                            Text(stamp.storeName)
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(softInk)
                            if let sourceLabel = stamp.aiSourceLabel {
                                Label(sourceLabel, systemImage: "sparkles")
                                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(modeStrongAccent)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(12)
                    .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    var stampGalleryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("饮品印章")
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                    Text("保留本月值得回看的饮品样本")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(softInk)
                }

                Spacer()
            }

            if summary.stamps.isEmpty {
                emptyStampState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(summary.stamps.prefix(8)) { stamp in
                            stampBadge(stamp)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
    }

    var emptyStampState: some View {
        HStack(spacing: 12) {
            Image(systemName: "seal")
                .font(.appSystem(size: 20, weight: .bold))
                .foregroundColor(latte)
                .frame(width: 42, height: 42)
                .background(Theme.Colors.secondarySurface, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("暂无饮品印章")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                Text("拍照识别后会生成门店、城市和饮品记录。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(softInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func stampBadge(_ stamp: DrinkStampRecord) -> some View {
        VStack(spacing: 9) {
            ZStack {
                WavyStampShape()
                    .stroke(cocoa.opacity(0.85), lineWidth: 2.4)
                    .background(
                        WavyStampShape()
                            .fill(Color(hex: "FFFDFA"))
                    )

                VStack(spacing: 8) {
                    Text(stamp.storeName)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(cocoa)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)

                    if let url = stamp.cutoutURL ?? stamp.photoURL, let remote = URL(string: url) {
                        AsyncImage(url: remote) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.appSystem(size: 28, weight: .bold))
                                .foregroundColor(latte)
                        }
                        .frame(width: 74, height: 74)
                    } else {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.appSystem(size: 28, weight: .bold))
                            .foregroundColor(latte)
                    }

                    Text(stamp.capturedAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year()))
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(cocoa)
                }
                .padding(.vertical, 18)
            }
            .frame(width: 154, height: 178)
        }
    }

    var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recognitionError, !recognitionError.isEmpty {
                Text(recognitionError)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(cocoa)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(hex: "FDECE8"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    actionButton(
                        title: "记录饮水",
                        subtitle: habitViewModel.hydrationHeadlineText,
                        symbol: "drop.circle.fill",
                        accent: sage
                    ) {
                        selectedPreset = .water
                        showingQuickRecord = true
                    }

                    actionButton(
                        title: "记录咖啡因",
                        subtitle: "\(habitViewModel.caffeineAmount) mg",
                        symbol: "cup.and.saucer.fill",
                        accent: butter
                    ) {
                        showingCoffeeRecord = true
                    }
                }

                actionButton(
                    title: isRecognizing ? "识别中" : "拍照识别",
                    subtitle: "生成饮品印章",
                    symbol: "camera.viewfinder",
                    accent: latte,
                    isDisabled: isRecognizing
                ) {
                    showingSourcePicker = true
                }
            }
        }
    }

    func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        accent: Color,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 19, weight: .bold))
                    .foregroundColor(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(softInk)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.appSystem(size: 11, weight: .black))
                        .foregroundColor(accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(15)
            .background(
                LinearGradient(
                    colors: [card, accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    func shiftMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = next
        monthMetricsLoadID = UUID()
        if let monthStart = Calendar.current.dateInterval(of: .month, for: next)?.start {
            selectedCalendarDate = monthStart
        }
    }

    @MainActor
    func loadMonthMetrics() async {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else { return }
        guard monthInterval.start <= Date() else {
            monthlyWaterByDay = [:]
            monthlyCaffeineByDay = [:]
            return
        }

        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
        let endDate = min(lastDay, Date())
        let days = max(1, (calendar.dateComponents([.day], from: monthInterval.start, to: endDate).day ?? 0) + 1)

        isLoadingMonthMetrics = true
        let loadID = monthMetricsLoadID
        async let waterPoints = try? HealthKitManager.shared.fetchDailyDietaryWaterSums(days: days, endDate: endDate)
        async let caffeinePoints = try? HealthKitManager.shared.fetchDailyDietaryCaffeineSums(days: days, endDate: endDate)

        let resolvedWater = await waterPoints ?? []
        let resolvedCaffeine = await caffeinePoints ?? []

        // 月份切换时旧任务被取消/被更新任务取代，取消与过期结果都不允许写入，
        // 避免旧月份任务把空字典覆盖到新月份。
        guard !Task.isCancelled, loadID == monthMetricsLoadID else { return }

        monthlyWaterByDay = metricMap(from: resolvedWater, in: monthInterval)
        monthlyCaffeineByDay = metricMap(from: resolvedCaffeine, in: monthInterval)
        isLoadingMonthMetrics = false
    }

    func metricMap(from points: [TimeSeriesPointDouble], in interval: DateInterval) -> [String: Int] {
        var mapped: [String: Int] = [:]
        for point in points where interval.contains(point.date) {
            let value = Int(point.value.rounded())
            guard value > 0 else { continue }
            mapped[dayKey(for: point.date)] = value
        }
        return mapped
    }

    func monthKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func handleCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            recognitionError = PhotoRecognitionServiceError.compressionFailed.localizedDescription
            return
        }
        handlePickedImageData(data)
    }

    func handlePickedImageData(_ data: Data) {
        isRecognizing = true
        recognitionError = nil
        Task {
            let result = await recognitionService.recognize(imageData: data, useCase: .drinkStamp)
            await MainActor.run {
                isRecognizing = false
                switch result {
                case .success(let payload):
                    pendingRecognition = payload
                    workingStoreName = payload.storeName ?? "未命名门店"
                    // 城市来自设备本地定位结果，不来自也不上传给千问。
                    workingCityName = payload.cityName ?? payload.locationSummary?.label ?? ""
                    workingDrinkName = payload.primaryName
                    workingCapturedAt = payload.capturedAt
                case .failure(let error):
                    recognitionError = error.localizedDescription
                }
            }
        }
    }

    func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isRecognizing = true
        recognitionError = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    throw PhotoRecognitionServiceError.invalidPhotoData
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                    handlePickedImageData(data)
                }
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
                    isRecognizing = false
                    recognitionError = error.localizedDescription
                }
            }
        }
    }

    func confirmRecognition(_ recognition: PhotoRecognitionResult) {
        let cityName = workingCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storeName = workingStoreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let drinkName = workingDrinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storeName.isEmpty, !drinkName.isEmpty else { return }

        let summary = recognition.locationSummary
        let record = DrinkStampRecord(
            id: UUID().uuidString,
            storeName: storeName,
            cityName: cityName.isEmpty ? nil : cityName,
            drinkName: drinkName,
            capturedAt: workingCapturedAt,
            photoFileID: nil,
            photoURL: nil,
            cutoutFileID: nil,
            cutoutURL: nil,
            latitude: summary?.latitude,
            longitude: summary?.longitude,
            locationLabel: summary?.displayText,
            status: summary == nil ? .locationUnavailable : .confirmed,
            isGeneratedFromRecognition: true,
            aiProviderID: recognition.aiProviderID,
            aiModel: recognition.aiModel,
            aiConfidence: recognition.confidence
        )
        store.saveStamp(record)
        pendingRecognition = nil
    }
}

private struct DrinkRecognitionConfirmationView: View {
    let recognition: PhotoRecognitionResult
    @Binding var storeName: String
    @Binding var cityName: String
    @Binding var drinkName: String
    @Binding var capturedAt: Date
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("确认印章信息")
                    .font(.appSystem(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "2C1F18"))

                if let sourceLabel = recognition.aiSourceLabel {
                    Label(sourceLabel, systemImage: "sparkles")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "8A5F4B"))
                }

                VStack(spacing: 12) {
                    inputField(title: "门店", text: $storeName)
                    inputField(title: "城市", text: $cityName)
                    inputField(title: "饮品", text: $drinkName)

                    DatePicker("日期", selection: $capturedAt, displayedComponents: [.date])
                        .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        .tint(Color(hex: "8A5F4B"))

                    if let location = recognition.locationSummary?.displayText {
                        Text("定位：\(location)")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "776B64"))
                    } else {
                        Text("定位：未读取位置")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "9E9289"))
                    }

                    if !recognition.candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("识别候选")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "857971"))
                            ForEach(recognition.candidates) { candidate in
                                Button {
                                    drinkName = candidate.title
                                } label: {
                                    Text(candidate.title)
                                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(drinkName == candidate.title ? .white : Color(hex: "765744"))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            (drinkName == candidate.title ? Color(hex: "9E5D43") : Color.white),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("确认生成印章")
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "915341"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
    }

    func inputField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "8F837A"))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

nonisolated private struct WavyStampShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = 14
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.15
        var path = Path()
        for index in 0...points {
            let angle = (Double(index) / Double(points)) * Double.pi * 2
            let wave = index.isMultiple(of: 2) ? radius : radius * 0.88
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * wave,
                y: center.y + CGFloat(sin(angle)) * wave
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
