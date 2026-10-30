/// HealthHubView 由 MainTabView 健康 Tab 调用，作为「健康」首页摘要与分发入口。
/// 负责承载多模块健康概览布局，并导航到对应的详情页或记录页。

import SwiftUI
import Charts
import Combine

/// 健康首页内部统一路由。跨 Tab 的入口仍由 `MainTabView.VitalityRoute` 承接。
enum HealthHubDestination: String, Identifiable {
    case alerts
    case reports
    case dailyReport
    case weeklyReport
    case monthlyReport
    case fitness
    case activeEnergy
    case basalEnergy
    case bodyAge
    case bodyProfile
    case healthProfile
    case wristTemperature
    case walkingAsymmetry
    case dailyAction
    case drink
    case meal
    case mood
    case sedentary
    case environmentNoise
    case medicationSymptoms
    case reproductiveHealth
    case friends
    case pressure
    case restingHeartRate
    case sleep

    var id: String { rawValue }
}

/// 健康首页视图 由上级页面或路由调用，作为健康摘要与分发入口。
/// 负责承载多模块复用的健康概览布局，并导航到对应的详情页或记录页。
struct HealthHubView: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dashboardViewModel = DashboardViewModel.shared
    @State private var habitViewModel = HabitViewModel()
    @State private var reportViewModel = ReportSummaryViewModel()
    @Bindable private var healthDataManager = HealthDataManager.shared
    @Bindable var periodViewModel: PeriodViewModel
    let openReproductiveRecord: () -> Void
    @Binding var route: MainTabView.VitalityRoute?
    let goalLinkedAction: DailyWellnessActionKind?
    let goalLinkedDate: Date?
    @AppStorage("onboarding_age") private var onboardingAge: Int = 25
    @State private var healthAge: Int?
    @State private var hubDestination: HealthHubDestination?
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var healthProfileSummary: HealthProfileSummary?
    @State private var isHealthProfileLoading = false
    /// 只首载执行全量数据加载；Tab 切回/从详情返回不重放重活，定期刷新交给 60s 定时器。
    @State private var didLoadData = false
    @State private var showsAllHealthTools = false
    @State private var bodyProfileHeightCm: Double?
    @State private var bodyProfileWeightKg: Double?
    @State private var bodyProfileMessage: String?
    @AppStorage("body_profile_target_weight_kg") private var targetWeightKg: Double = 58.0

    @Bindable private var socialDataStore = SharedHealthDataStore.shared
    @State private var socialViewModel = SocialViewModel()

    private let sedentaryRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let periodDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let accentBlue = Color(hex: "6B83E8")
    private let accentCoral = Color(hex: "F46B5A")
    private let accentMint = Color(hex: "1B9266") // 与今日页主绿一致
    private let accentAmber = Color(hex: "F3A53B")
    private let accentRose = Color(hex: "FF8FB8")
    private let cardShadow = Color(hex: "84A7D9").opacity(0.10)

    var body: some View {
        ZStack {
            background
            healthReferenceDashboard
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { target in
            Group {
                switch target {
                case .mealHub:
                    MealRecognitionHubView()
                case .drinkHub:
                    DrinkStampHubView(habitViewModel: habitViewModel)
                case .medicationHub:
                    MedicationCenterView()
                case .moodHub:
                    StressRootView()
                case .dailyAction:
                    DailyActionView(
                        periodViewModel: periodViewModel,
                        openReproductiveRecord: openReproductiveRecord,
                        initialDate: selectedDate
                    )
                case .goalAction:
                    DailyActionView(
                        periodViewModel: periodViewModel,
                        openReproductiveRecord: openReproductiveRecord,
                        initialDate: goalLinkedDate ?? selectedDate,
                        linkedActionKind: goalLinkedAction
                    )
                case .reproductiveRecord:
                    ReproductiveHealthRecordView(
                        periodViewModel: periodViewModel,
                        initialSection: .period
                    )
                case .pregnancyRecord:
                    ReproductiveHealthRecordView(
                        periodViewModel: periodViewModel,
                        initialSection: .pregnancy
                    )
                case .bodyAge:
                    BodyAgeView()
                case .careHub:
                    CareHubView()
                }
            }
            .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(item: $hubDestination) { destination in
            healthHubDestinationView(destination)
                .toolbar(.hidden, for: .tabBar)
        }
        .alert("身高体重", isPresented: Binding(
            get: { bodyProfileMessage != nil },
            set: { if !$0 { bodyProfileMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(bodyProfileMessage ?? "")
        }
        .task {
            // 只首载执行全量加载；切 Tab/从详情返回触发的再次 appear 直接跳过（60s 定时器负责刷新）。
            guard !didLoadData else { return }
            // 先触发内部自带异步的即时加载，首屏卡片不等任何 HealthKit 查询。
            dashboardViewModel.loadData()
            habitViewModel.loadData(for: selectedDate)
            periodViewModel.reload(days: 90)
            reportViewModel.load(days: 30)

            // 好友共享数据预加载，让主页好友陪伴卡片立即有数据。
            async let socialBootstrap: Void = SharedHealthDataStore.shared.bootstrap()

            // 剩余相互独立的慢查询并发执行，避免串行等待拖慢整页出数据。
            async let profileLoad: Void = loadHealthProfileSummary()
            async let bodyLoad: Void = loadBodyProfile()
            if healthAge == nil {
                healthAge = await HealthKitManager.shared.fetchChronologicalAge()
            }
            await profileLoad
            await bodyLoad
            await socialBootstrap
            didLoadData = true
        }
        .onReceive(sedentaryRefreshTimer) { _ in
            Task {
                await dashboardViewModel.refreshSedentaryState()
                // 档案摘要与身高体重互不依赖，定时刷新时并发拉取。
                async let profileLoad: Void = loadHealthProfileSummary()
                async let bodyLoad: Void = loadBodyProfile()
                await profileLoad
                await bodyLoad
            }
        }
    }

    @ViewBuilder
    private func healthHubDestinationView(_ destination: HealthHubDestination) -> some View {
        switch destination {
        case .alerts:
            AlertHistoryView()
                .healthDetailNavigation(title: "消息")
        case .reports:
            ReportsRootView()
                .healthDetailNavigation(title: "报告")
        case .dailyReport:
            DailyReportView()
        case .weeklyReport:
            WeeklyReportView()
        case .monthlyReport:
            WeeklyReportView(period: .month)
        case .fitness:
            FitnessCalendarScreen(
                showsHeroTitle: false,
                showsQuickActions: true,
                contentInset: 4,
                bottomPadding: 88
            )
            .healthDetailNavigation(title: HealthPageName.fitness)
        case .activeEnergy:
            let card = habitViewModel.makeActiveEnergyCard()
            ActiveEnergyDetailView(card: card, selectedDate: selectedDate, summary: card.comparisonText)
                .healthDetailNavigation(title: "活动消耗")
        case .basalEnergy:
            let card = habitViewModel.makeBasalEnergyCard()
            BasalEnergyDetailView(card: card, selectedDate: selectedDate, summary: card.comparisonText)
                .healthDetailNavigation(title: "基础代谢")
        case .bodyAge:
            BodyAgeView()
        case .restingHeartRate:
            HeartRateDetailView(history: nil, initialDate: selectedDate)
        case .bodyProfile:
            BodyProfileRecordSheet(
                initialHeightCm: bodyProfileHeightCm ?? 175,
                initialWeightKg: bodyProfileWeightKg ?? 60,
                initialTargetWeightKg: targetWeightKg
            ) { record in
                await saveBodyProfile(record)
            }
        case .healthProfile:
            HealthProfileView {
                hubDestination = .dailyAction
            }
        case .wristTemperature:
            let card = habitViewModel.makeWristTemperatureCard()
            WristTemperatureDetailView(card: card, selectedDate: selectedDate, summary: card.comparisonText)
                .healthDetailNavigation(title: "手腕温度")
        case .walkingAsymmetry:
            if let metric = dashboardViewModel.otherMetrics.first(where: { $0.destination == .walkingAsymmetry }) {
                WalkingAsymmetryDetailView(metric: metric, initialDate: selectedDate)
                    .healthDetailNavigation(title: "步态不对称")
            } else {
                ContentUnavailableView(
                    "步态数据正在同步",
                    systemImage: "figure.walk.motion",
                    description: Text("连接健康 App 后，这里会展示步态不对称的长期变化。")
                )
                .healthDetailNavigation(title: "步态不对称")
            }
        case .dailyAction:
            DailyActionView(
                periodViewModel: periodViewModel,
                openReproductiveRecord: openReproductiveRecord,
                initialDate: selectedDate
            )
        case .drink:
            DrinkStampHubView(habitViewModel: habitViewModel)
        case .meal:
            MealRecognitionHubView()
        case .mood:
            StressRootView()
        case .sedentary:
            SedentaryView(viewModel: dashboardViewModel)
        case .environmentNoise:
            EnvironmentalAudioSheetView(initialDate: selectedDate)
        case .medicationSymptoms:
            MedicationCenterView()
        case .reproductiveHealth:
            ReproductiveHealthRecordView(periodViewModel: periodViewModel, initialSection: .period)
        case .friends:
            SocialRootView(onBack: nil)
        case .pressure:
            StressRootView()
        case .sleep:
            SleepView()
        }
    }

    private var background: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }

    private var healthReferenceDashboard: some View {
        AdaptivePageScrollView(topPadding: Theme.Spacing.compact, bottomPadding: 112) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                referenceHealthHero
                referenceBodySignalsSection
                referenceRecommendedRecordsSection
                figmaHealthReportEntry
                referenceCoreMetricsSection
                referenceAllMetricsButton
                if showsAllHealthTools {
                    allHealthCapabilitiesSection
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, healthHubAdditionalHorizontalInset)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private var healthHubAdditionalHorizontalInset: CGFloat {
        adaptiveLayout.usesExpandedLayout ? 8 : 4
    }

    private var referenceHealthHero: some View {
        let metric = HealthHubPresentationBuilder.profileMetric(from: healthProfileSummary)

        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color(hex: "E8FFF5"), Color(hex: "F3FFBE"), Color(hex: "FFFDEB")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 170, height: 170)
                .blur(radius: 24)
                .offset(x: 44, y: 35)

            if !dynamicTypeSize.isAccessibilitySize {
                Image("VitalityHeaderMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: adaptiveLayout.containerWidth < 370 ? 124 : 146)
                    .offset(x: 12, y: 12)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(localized: "健康"))
                        .font(.appSystem(.title2, design: .rounded).weight(.black))
                    Spacer()
                    Button { hubDestination = .healthProfile } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                            Image(systemName: "ellipsis")
                        }
                        .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(Color.white.opacity(0.62), in: Capsule())
                        .overlay { Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "健康档案"))
                }

                Spacer(minLength: 18)

                Text(String(localized: "长期健康概览"))
                    .font(.appSystem(.body, design: .rounded).weight(.medium))
                Text(referenceHealthHeroTitle(metric: metric))
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .padding(.top, 7)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(0.78)
                Text(HealthHubPresentationBuilder.profileExplanation(from: healthProfileSummary))
                    .font(.appSystem(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : (adaptiveLayout.containerWidth < 370 ? 106 : 132))
            .frame(maxWidth: .infinity, minHeight: 226, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func referenceHealthHeroTitle(metric: HealthHubProfileMetric) -> String {
        guard metric.valueText != "--" else {
            return String(localized: "档案尚未形成")
        }
        return String(localized: "\(metric.valueText) 分 · \(metric.title)")
    }

    private var referenceHealthOverview: some View {
        let metric = HealthHubPresentationBuilder.profileMetric(from: healthProfileSummary)

        return Button {
            hubDestination = .healthProfile
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) {
                        referenceOverviewCopy(metric: metric)
                        referenceScoreRing(metric: metric)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(spacing: 18) {
                        referenceOverviewCopy(metric: metric)
                        Spacer(minLength: 4)
                        referenceScoreRing(metric: metric)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
            }
            .shadow(color: cardShadow, radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "健康档案概览"))
        .accessibilityValue(metric.valueText == "--" ? String(localized: "暂无数据") : String(localized: "\(metric.valueText)分，\(metric.title)"))
        .accessibilityHint(String(localized: "查看健康档案"))
    }

    private func referenceOverviewCopy(metric: HealthHubProfileMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "健康档案概览"))
                    .font(.appSystem(.headline, design: .rounded).weight(.black))
                Image(systemName: "chevron.right")
                    .font(.appSystem(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.valueText)
                    .font(.appSystem(size: 38, weight: .black, design: .rounded))
                if metric.valueText != "--" {
                    Text(String(localized: "分"))
                        .font(.appSystem(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(accentMint)
                }
                Text(metric.title)
                    .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(hex: "A36A18"))
                    .padding(.horizontal, 9)
                    .frame(minHeight: 26)
                    .background(Color(hex: "FFF8D8"), in: Capsule())
            }
            Text(healthProfileSummary == nil
                 ? String(localized: "完成健康档案后，这里会显示档案进展")
                 : String(localized: "查看健康档案，了解评分依据与待完善项目"))
                .font(.appSystem(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func referenceScoreRing(metric: HealthHubProfileMetric) -> some View {
        ZStack {
            Circle().stroke(accentMint.opacity(0.14), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(metric.progress) / 100)
                .stroke(accentMint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(metric.valueText)
                .font(.appSystem(.title2, design: .rounded).weight(.black))
                .foregroundStyle(accentMint)
        }
        .frame(width: 102, height: 102)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.valueText == "--" ? String(localized: "暂无数据") : String(localized: "\(metric.valueText)分"))
    }

    private var referenceBodySignalsSection: some View {
        let pressure = effectivePressureAssessment

        return VStack(alignment: .leading, spacing: 12) {
            referenceSectionTitle(String(localized: "身体信号详情"))
            Text(String(localized: "读数来自已有健康记录；打开详情查看日期、趋势和数据依据。"))
                .font(.appSystem(.subheadline).weight(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: referenceThreeColumns, spacing: 10) {
                referenceSignalCard(
                    title: String(localized: "睡眠"),
                    value: figmaSleepDurationValue,
                    symbol: "moon.zzz.fill",
                    tint: accentAmber,
                    status: habitViewModel.sleepDuration > 0
                        ? String(localized: "已同步的睡眠时长")
                        : String(localized: "暂无睡眠记录，可先检查健康 App 中是否已有睡眠数据。")
                ) { hubDestination = .sleep }
                referenceSignalCard(
                    title: String(localized: "压力"),
                    value: pressure.hasData ? pressure.valueText : "--",
                    symbol: "waveform.path.ecg",
                    tint: accentCoral,
                    status: pressure.hasData
                        ? String(localized: "综合压力指数，越高表示负荷越高")
                        : String(localized: "等待可用心率、HRV 样本与个人基线。")
                ) { hubDestination = .pressure }
                referenceSignalCard(
                    title: String(localized: "静息心率"),
                    value: figmaHeartRateValue,
                    symbol: "heart.fill",
                    tint: Color(hex: "D45C45"),
                    status: dashboardViewModel.restingHeartRate.map { $0 > 0 } == true
                        ? String(localized: "已同步的静息心率，并非实时心率")
                        : String(localized: "暂无静息心率记录，可先检查设备是否已同步至健康 App。")
                ) { hubDestination = .restingHeartRate }
            }
            Text(String(localized: "暂无数据不等于读数为 0；这些信息用于个人回顾，不替代医学诊断。"))
                .font(.appSystem(.caption))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var referenceCoreColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize || adaptiveLayout.containerWidth < 600 ? 1 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var referenceThreeColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize || adaptiveLayout.containerWidth < 600 ? 1 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private func referenceSignalCard(
        title: String,
        value: String,
        symbol: String,
        tint: Color,
        status: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title, systemImage: symbol)
                            .font(.appSystem(.headline).weight(.bold))
                        Text(value)
                            .font(.appSystem(.title3).weight(.bold))
                            .foregroundStyle(tint)
                        Text(status)
                            .font(.appSystem(.subheadline))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if adaptiveLayout.containerWidth < 600 {
                    HStack(spacing: 13) {
                        Image(systemName: symbol)
                            .font(.appSystem(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(tint)
                            .frame(width: 42, height: 42)
                            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                            Text(status)
                                .font(.appSystem(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(value)
                            .font(.appSystem(.headline, design: .rounded).weight(.black))
                            .foregroundStyle(value == "--" ? Color.secondary : tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(title, systemImage: symbol)
                            .font(.appSystem(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                        Text(value)
                            .font(.appSystem(.headline, design: .rounded).weight(.black))
                            .foregroundStyle(value == "--" ? Color.secondary : tint)
                        Spacer(minLength: 8)
                        Text(status)
                            .font(.appSystem(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                }
            }
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)，\(status)")
        .accessibilityHint(String(localized: "打开指标详情"))
    }

    private var referenceAllMetricsButton: some View {
        Button {
            showsAllHealthTools.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                Text(showsAllHealthTools ? String(localized: "收起健康工具") : String(localized: "查看更多健康工具"))
                    .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: showsAllHealthTools ? "chevron.up" : "arrow.right.circle.fill")
                    .font(.appSystem(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(accentMint)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "健康工具"))
        .accessibilityValue(
            showsAllHealthTools ? String(localized: "已展开") : String(localized: "已收起")
        )
        .accessibilityHint(String(localized: "切换健康工具显示"))
    }

    /// 照护与行动入口，不将工具误标为身体测量指标。
    private var referenceCoreMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            referenceSectionTitle(String(localized: "照护与行动"))
            LazyVGrid(columns: referenceCoreColumns, spacing: 10) {
                referenceCoreFocusCard(
                    title: String(localized: "好友健康"),
                    description: String(localized: "查看已授权共享的健康信息，管理共享关系"),
                    symbol: "person.2.fill",
                    tint: accentMint,
                    actionText: String(localized: "去看看")
                ) { hubDestination = .friends }
                referenceCoreFocusCard(
                    title: String(localized: "药物管理"),
                    description: String(localized: "设置用药提醒，记录服药状态"),
                    symbol: "pills.fill",
                    tint: accentAmber,
                    actionText: String(localized: "去设置")
                ) { hubDestination = .medicationSymptoms }
                referenceCoreFocusCard(
                    title: String(localized: "健身计划"),
                    description: String(localized: "回看已记录的训练，查看运动详情与计划"),
                    symbol: "figure.run",
                    tint: accentBlue,
                    actionText: String(localized: "去训练")
                ) { hubDestination = .fitness }
            }
        }
    }

    /// 手机使用易读的横向卡片，宽屏保留三列展示。
    private func referenceCoreFocusCard(
        title: String,
        description: String,
        symbol: String,
        tint: Color,
        actionText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize || adaptiveLayout.containerWidth < 600 {
                    HStack(spacing: 14) {
                        Image(systemName: symbol)
                            .font(.appSystem(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(tint)
                            .frame(width: 48, height: 48)
                            .background(tint.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.appSystem(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(.primary)
                            Text(description)
                                .font(.appSystem(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.appSystem(.subheadline, design: .rounded).weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: symbol)
                            .font(.appSystem(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .frame(width: 56, height: 56)
                            .background(tint.opacity(0.12), in: Circle())
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                            .accessibilityHidden(true)
                        Text(description)
                            .font(.appSystem(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .center)
                            .padding(.top, 8)
                        Spacer(minLength: 8)
                        Text(actionText)
                            .font(.appSystem(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 32)
                            .background(tint.opacity(0.14), in: Capsule())
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 194, alignment: .top)
                }
            }
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(description)
        .accessibilityHint(actionText)
    }

    private var referenceRecommendedRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            referenceSectionTitle(String(localized: "建议记录"))
            Text(String(localized: "按需要补充饮品、餐食和情绪，帮助回顾自己的生活规律。"))
                .font(.appSystem(.subheadline))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        referenceRecordButtons
                    }
                } else {
                    HStack(spacing: 0) {
                        referenceRecordButtons
                    }
                }
            }
            .padding(.horizontal, 4)
            .bbLiquidGlassSurface(
                tint: accentMint,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                tintStrength: 0.05,
                shadow: false
            )
        }
    }

    @ViewBuilder
    private var referenceRecordButtons: some View {
                referenceRecordButton(
                    title: String(localized: "饮品"),
                    value: waterValueText == "--" ? String(localized: "去记录") : waterValueText,
                    symbol: "drop.fill",
                    tint: accentAmber
                ) { hubDestination = .drink }
                referenceRecordButton(
                    title: String(localized: "餐食"),
                    value: todayMealRecordValueText,
                    symbol: "fork.knife",
                    tint: accentMint
                ) { hubDestination = .meal }
                referenceRecordButton(
                    title: String(localized: "情绪"),
                    value: todayMoodEntries.isEmpty ? String(localized: "去记录") : String(localized: "已记录"),
                    symbol: "face.smiling",
                    tint: accentCoral
                ) { hubDestination = .mood }
    }

    private func referenceRecordButton(
        title: String,
        value: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    Text(value)
                        .font(.appSystem(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func referenceSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.appSystem(.title3, design: .rounded).weight(.black))
            .foregroundStyle(.primary)
    }

    private var healthEditorialHeader: some View {
        BBPageHeader(
            title: String(localized: "健康"),
            subtitle: String(localized: "把零散的数据，整理成今天的状态")
        ) {
            healthMessagesButton
        }
    }

    private var healthMessagesButton: some View {
        Button {
            hubDestination = .healthProfile
        } label: {
            Image(systemName: "sparkles")
                .font(.appSystem(.body, design: .rounded).weight(.bold))
                .foregroundStyle(accentMint)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .systemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "健康档案"))
        .accessibilityHint(String(localized: "查看健康档案"))
    }

    private var figmaTodaySummary: some View {
        let metric = HealthHubPresentationBuilder.profileMetric(from: healthProfileSummary)

        return HStack(spacing: Theme.Spacing.small) {
            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                Text(String(localized: "今日身体状态"))
                    .font(Theme.Typography.label)
                    .foregroundStyle(accentMint)
                Text(figmaRecoveryHeadline(score: metric.progress))
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(.primary)
                Text(figmaRecoveryDescription)
                    .font(Theme.Typography.supporting)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.compact) {
                    figmaSummaryMetric(title: String(localized: "睡眠"), value: figmaCompactSleepValue)
                    figmaSummaryMetric(title: String(localized: "压力"), value: figmaPressureValue)
                    figmaSummaryMetric(title: String(localized: "心率"), value: figmaHeartRateValue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle().stroke(accentMint.opacity(0.16), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(metric.progress) / 100)
                    .stroke(accentMint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(metric.valueText)
                    .font(.appSystem(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(accentMint)
            }
            .frame(width: 82, height: 82)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "健康评分"))
            .accessibilityValue(metric.valueText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color(hex: "E7F8F1"), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func figmaSummaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.appSystem(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.appSystem(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var figmaFrequentHealthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "常用健康"))
                    .font(.appSystem(.title3, design: .rounded).weight(.bold))
                Spacer()
                Text(String(localized: "自动置顶最常看的数据"))
                    .font(.appSystem(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                figmaFrequentCard(
                    title: String(localized: "睡眠"),
                    value: figmaSleepDurationValue,
                    subtitle: sleepFeatureSubtitle,
                    symbol: "moon.zzz.fill",
                    tint: Color(hex: "6A7BC8"),
                    fill: Color(hex: "EEF2FF"),
                    mascotName: "TodayPressureRelaxed"
                ) { hubDestination = .sleep }
                figmaFrequentCard(
                    title: String(localized: "压力与情绪"),
                    value: figmaPressureScoreValue,
                    subtitle: effectivePressureAssessment.hasData ? effectivePressureAssessment.title : String(localized: "等待健康数据"),
                    symbol: "waveform.path.ecg",
                    tint: accentMint,
                    fill: Color(hex: "E7F8F1"),
                    mascotName: "ActionFeelingMascot"
                ) { hubDestination = .pressure }
            }
        }
    }

    private func figmaFrequentCard(
        title: String,
        value: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        fill: Color,
        mascotName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: symbol)
                        .font(.appSystem(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(value)
                        .font(.appSystem(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.appSystem(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.trailing, 36)

                Image(mascotName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .opacity(0.88)
                    .offset(x: 7, y: 8)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .tint(tint)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var figmaHealthReportEntry: some View {
        Button { hubDestination = .reports } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentMint.opacity(0.10))
                    Image("TodayPressureRelaxed")
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                        .accessibilityHidden(true)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "健康报告"))
                        .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(reportSummaryText)
                        .font(.appSystem(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(String(localized: "查看"))
                    .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(accentMint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentMint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "打开健康报告"))
    }

    private var figmaFriendsEntry: some View {
        let state = socialDataStore.state
        let friendCount = state.friends.count
        let outgoingCount = state.outgoingShares.count
        let connectionCount = friendCount + outgoingCount
        let tint = connectionCount > 0
            ? accentMint
            : (state.isICloudAvailable ? accentBlue : Color(hex: "9CA3AF"))

        return Button { hubDestination = .friends } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.appSystem(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "好友"))
                        .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(socialCompanionSubtitle(
                        friendCount: friendCount,
                        outgoingCount: outgoingCount,
                        mutualCount: state.relationshipOverview.mutualCount,
                        isICloudReady: state.isICloudAvailable
                    ))
                    .font(.appSystem(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                Text(String(localized: "进入"))
                    .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "打开好友与健康共享"))
        .accessibilityIdentifier("health.friends.entry")
    }

    private var figmaCompactSleepValue: String {
        guard habitViewModel.sleepDuration > 0 else { return "--" }
        let hours = habitViewModel.sleepDuration / 60
        let minutes = habitViewModel.sleepDuration % 60
        return "\(hours)h\(minutes)"
    }

    private var figmaSleepDurationValue: String {
        guard habitViewModel.sleepDuration > 0 else { return "--" }
        let hours = habitViewModel.sleepDuration / 60
        let minutes = habitViewModel.sleepDuration % 60
        return String(localized: "\(hours)小时\(minutes)分")
    }

    private var figmaPressureValue: String {
        effectivePressureAssessment.hasData ? effectivePressureAssessment.valueText : "--"
    }

    private var figmaPressureScoreValue: String {
        effectivePressureAssessment.hasData ? "\(effectivePressureAssessment.valueText) / 100" : "--"
    }

    private var figmaHeartRateValue: String {
        guard let value = dashboardViewModel.restingHeartRate, value > 0 else { return "--" }
        return String(localized: "\(Int(value.rounded())) bpm")
    }

    private var figmaRecoveryDescription: String {
        guard habitViewModel.sleepDuration > 0 || effectivePressureAssessment.hasData else {
            return String(localized: "同步睡眠、压力与心率后生成今日状态")
        }
        if effectivePressureAssessment.band == .caution || effectivePressureAssessment.band == .high {
            return String(localized: "今天压力偏高，给身体留一些恢复时间")
        }
        if habitViewModel.sleepDuration > 0, effectivePressureAssessment.hasData {
            return String(localized: "睡眠与压力都在你的日常范围内")
        }
        return habitViewModel.sleepDuration > 0
            ? String(localized: "睡眠记录已同步，压力数据仍待补充")
            : String(localized: "压力数据已同步，睡眠记录仍待补充")
    }

    private func figmaRecoveryHeadline(score: Int) -> String {
        switch score {
        case 80...: return String(localized: "恢复不错")
        case 60..<80: return String(localized: "状态平稳")
        case 1..<60: return String(localized: "注意恢复")
        default: return String(localized: "等待数据")
        }
    }

    private var compactHealthSummary: some View {
        let summary = healthProfileSummary
        let metric = HealthHubPresentationBuilder.profileMetric(from: summary)
        let available = summary?.dataQuality.availableModules ?? 0
        let total = max(summary?.dataQuality.totalModules ?? 6, 1)
        let primary = HealthHubPresentationBuilder.focusItems(from: summary).first

        return VStack(alignment: .leading, spacing: 14) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        healthGrowthCopy
                        healthGrowthRing(metric)
                    }
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        healthGrowthCopy
                        Spacer(minLength: 4)
                        healthGrowthRing(metric)
                    }
                }
            }

            healthCoverageDots(available: available, total: total)

            if let primary {
                Button {
                    hubDestination = destination(for: primary.module)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(accentMint)
                            .frame(width: 42, height: 42)
                            .background(accentMint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: String(localized: "建议下一步：%@"), primary.title))
                                .font(.appSystem(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(accentMint)
                            Text(primary.detail)
                                .font(.appSystem(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: Theme.Icons.chevronRight)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                    .background(Color(uiColor: .systemBackground).opacity(0.70), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1) }
                }
                .bbCardButtonStyle()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("health.summary.next-step")
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
        }

    }

    private var healthGrowthCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "30 天健康成长指数"))
                .font(.appSystem(.title3, design: .rounded).weight(.black))
            Text(String(localized: "综合健康、运动和习惯数据的变化趋势"))
                .font(.appSystem(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthCoverageDots(available: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "数据覆盖 \(available)/\(total)"))
                .font(.appSystem(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(0..<min(total, 8), id: \.self) { index in
                    Circle()
                        .fill(index < available ? accentMint : Color(uiColor: .systemFill))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func healthGrowthRing(_ metric: HealthHubProfileMetric) -> some View {
        ZStack {
            Circle().stroke(accentMint.opacity(0.10), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(metric.progress) / 100)
                .stroke(accentMint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(metric.valueText)
                    .font(.appSystem(.largeTitle, design: .rounded).weight(.black))
                Text(metric.title)
                    .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 108, height: 108)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "健康指数"))
        .accessibilityValue("\(metric.valueText) \(metric.title)")
    }

    // MARK: - 今日健身区

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            editorialSectionTitle(String(localized: "今天做什么"))
            featuredSleepAction
            quickActionGrid
        }
    }

    private var featuredSleepAction: some View {
        Button { hubDestination = .sleep } label: {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.appSystem(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(hex: "795EE8"))
                    .frame(width: 52, height: 52)
                    .background(Color(hex: "795EE8").opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "睡眠"))
                        .font(.appSystem(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(sleepFeatureSubtitle)
                        .font(.appSystem(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }

                Spacer(minLength: 6)
                Image(systemName: Theme.Icons.chevronRight)
                    .font(.appSystem(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: "795EE8").opacity(0.10), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .bbCardButtonStyle()
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "打开睡眠详情"))
        .accessibilityIdentifier("health.quick.featured-sleep")
    }

    private var quickActionGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: HealthHubReferenceLayout.actionColumnCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)),
            spacing: 12
        ) {
            ForEach(HealthHubPresentationBuilder.referenceQuickActions) { action in
                Button { openQuickAction(action) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.symbol)
                            .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Color(hex: action.tintHex))
                            .frame(width: 38, height: 38)
                            .background(Color(hex: action.tintHex).opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.title)
                                .font(.appSystem(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(.primary)
                            Text(quickActionStatus(action))
                                .font(.appSystem(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 84, alignment: .leading)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5) }
                }
                .bbCardButtonStyle()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(action.title)
                .accessibilityValue(quickActionStatus(action))
                .accessibilityHint(String(localized: "打开健康功能"))
                .accessibilityIdentifier("health.quick.\(action.id)")
            }
        }
    }

    private var sleepFeatureSubtitle: String {
        if habitViewModel.sleepScore >= 80 {
            return String(localized: "昨晚睡得不错，继续保持规律作息")
        }
        if sleepHoursValueText != "--" {
            return String(format: String(localized: "昨夜 %@ 小时，查看恢复详情"), sleepHoursValueText)
        }
        return String(localized: "查看昨夜睡眠与恢复")
    }

    private func healthProfileStatusLabel(_ summary: HealthProfileSummary?) -> some View {
        Label(
            summary?.status.title ?? String(localized: "档案建立中"),
            systemImage: "waveform.path.ecg"
        )
        .font(.appSystem(.caption, design: .rounded).weight(.bold))
        .foregroundStyle(accentMint)
        .padding(.horizontal, 9)
        .frame(minHeight: 28)
        .background(Color(uiColor: .systemBackground).opacity(0.72), in: Capsule())
    }

    private var healthProfileLinkLabel: some View {
        HStack(spacing: 5) {
            Text(String(localized: "健康档案"))
            Image(systemName: "arrow.up.right")
        }
        .font(.appSystem(.caption, design: .rounded).weight(.bold))
        .foregroundStyle(.secondary)
    }

    private func quickActionStatus(_ action: HealthHubQuickAction) -> String {
        switch action {
        case .capability(let item):
            return capabilitySnapshot(for: item).note
        case .sleep:
            return String(localized: "查看睡眠与恢复")
        }
    }

    private var healthReviewSection: some View {
        let state = socialDataStore.state
        let friendCount = state.friends.count
        let outgoingCount = state.outgoingShares.count
        let connectionCount = friendCount + outgoingCount
        let sharingTint = connectionCount > 0 ? accentMint : (state.isICloudAvailable ? accentBlue : Color(hex: "9CA3AF"))
        let reviewColumnCount = HealthHubReferenceLayout.reviewColumnCount(
            availableWidth: min(adaptiveLayout.containerWidth, 620),
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )

        return VStack(alignment: .leading, spacing: 14) {
            editorialSectionTitle(String(localized: "回顾健康"))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 10),
                    count: reviewColumnCount
                ),
                spacing: 10
            ) {
                Button {
                    hubDestination = .reports
                } label: {
                    healthReviewCard(
                        title: String(localized: "健康报告"),
                        subtitle: reportSummaryText,
                        symbol: "doc.text.fill",
                        tint: Color(hex: "E58A4A"),
                        isSingleColumn: reviewColumnCount == 1
                    )
                }
                .bbCardButtonStyle()
                .accessibilityIdentifier("health.review.reports")

                Button {
                    hubDestination = .friends
                } label: {
                    healthReviewCard(
                        title: String(localized: "健康共享"),
                        subtitle: socialCompanionSubtitle(
                            friendCount: friendCount,
                            outgoingCount: outgoingCount,
                            mutualCount: state.relationshipOverview.mutualCount,
                            isICloudReady: state.isICloudAvailable
                        ),
                        symbol: "person.2.fill",
                        tint: sharingTint,
                        isSingleColumn: reviewColumnCount == 1
                    )
                }
                .bbCardButtonStyle()
                .accessibilityIdentifier("health.review.sharing")
            }
        }
    }

    private func healthReviewCard(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        isSingleColumn: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.appSystem(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.appSystem(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(11)
        .frame(
            maxWidth: .infinity,
            minHeight: dynamicTypeSize.isAccessibilitySize ? 92 : (isSingleColumn ? 84 : 108),
            alignment: .leading
        )
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5) }
        .contentShape(Rectangle())
    }

    private func healthReviewRow(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.appSystem(.body, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.appSystem(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)
            Image(systemName: Theme.Icons.chevronRight)
                .font(.appSystem(.caption, design: .rounded).weight(.black))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func socialCompanionSubtitle(
        friendCount: Int,
        outgoingCount: Int,
        mutualCount: Int,
        isICloudReady: Bool
    ) -> String {
        if mutualCount > 0 {
            return "与 \(mutualCount) 位好友保持双向健康共享"
        }
        if friendCount > 0 {
            return "\(friendCount) 位好友正在更新健康摘要"
        }
        if outgoingCount > 0 {
            return "\(outgoingCount) 条邀请等待接受"
        }
        if isICloudReady {
            return "邀请熟悉的人，安全共享只读健康摘要"
        }
        return "登录 iCloud 后即可邀请好友共享健康摘要"
    }

    private var allHealthCapabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            healthToolsHeading
            healthToolsList
        }
    }

    private var healthToolsList: some View {
        let items = HealthHubPresentationBuilder.healthToolCapabilities

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: HealthHubReferenceLayout.toolColumnCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            ),
            spacing: 12
        ) {
            ForEach(items) { item in
                let snapshot = capabilitySnapshot(for: item)
                Group {
                    if item == .medicationSymptoms {
                        NavigationLink {
                            MedicationCenterView()
                        } label: {
                            healthToolCard(item: item, snapshot: snapshot)
                        }
                    } else {
                        Button {
                            openCapability(item)
                        } label: {
                            healthToolCard(item: item, snapshot: snapshot)
                        }
                    }
                }
                .bbCardButtonStyle()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.title)
                .accessibilityValue(capabilityAccessibilityValue(snapshot, item: item))
                .accessibilityHint([item.toolExplanation, String(localized: "打开健康功能")].compactMap { $0 }.joined(separator: "，"))
                .accessibilityIdentifier("health.capability.\(item.id)")
            }
        }
    }

    private func healthToolCard(item: HealthCapabilityItem, snapshot: HealthCapabilitySnapshot) -> some View {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: item.tintHex))
                                .frame(width: 28, height: 28)
                                .background(Color(hex: item.tintHex).opacity(0.10), in: Circle())
                            Text(item.title)
                                .font(.appSystem(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let explanation = item.toolExplanation {
                            Text(explanation)
                                .font(.appSystem(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 6) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(HealthHubPresentationBuilder.toolValueText(value: snapshot.value, unit: snapshot.unit))
                                    .font(.appSystem(size: 19, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                Text(toolNote(snapshot, item: item))
                                    .font(.appSystem(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 28, height: 28)
                                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 166, alignment: .leading)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5) }
                    .contentShape(Rectangle())
    }

    private var healthToolsHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            editorialSectionTitle(String(localized: "健康工具"))
            Text(String(localized: "区分健康测量、趋势估算与日常记录，按需查看"))
                .font(.appSystem(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func toolNote(_ snapshot: HealthCapabilitySnapshot, item: HealthCapabilityItem) -> String {
        if HealthHubPresentationBuilder.isMissingToolValue(snapshot.value),
           [.activeEnergy, .basalEnergy, .wristTemperature, .walkingAsymmetry, .environmentNoise].contains(item) {
            return String(localized: "有可用健康记录后显示")
        }
        return snapshot.note
    }

    private func capabilityAccessibilityValue(_ snapshot: HealthCapabilitySnapshot, item: HealthCapabilityItem) -> String {
        let measuredValue = HealthHubPresentationBuilder.toolValueText(value: snapshot.value, unit: snapshot.unit)
        return [measuredValue, toolNote(snapshot, item: item)].filter { !$0.isEmpty }.joined(separator: "，")
    }

    private var reportsEditorialSection: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: "FFF0DF"))

            Image("TodayPressureRelaxed")
                .resizable()
                .scaledToFit()
                .frame(width: min(adaptiveLayout.containerWidth * 0.34, 150))
                .padding(.trailing, 2)
                .padding(.bottom, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                Button {
                    hubDestination = .reports
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        editorialSectionTitle(
                            eyebrow: "REPORTS",
                            title: "健康报告",
                            subtitle: reportSummaryText
                        )
                        editorialArrowLabel("进入报告中心", tint: Color(hex: "C36E24"))
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    reportShortcut("日报", destination: .dailyReport)
                    reportShortcut("周报", destination: .weeklyReport)
                    reportShortcut("月报", destination: .monthlyReport)
                }
            }
            .padding(22)
            .padding(.trailing, adaptiveLayout.containerWidth < 370 ? 72 : 112)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 230)
    }

    private func reportShortcut(_ title: String, destination: HealthHubDestination) -> some View {
        Button {
            hubDestination = destination
        } label: {
            Text(title)
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "8B5A31"))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var reportSummaryText: String {
        if let latest = reportViewModel.latest {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("Md")
            if let score = latest.score {
                return String(localized: "最新 \(formatter.string(from: latest.date)) · 综合 \(score) 分")
            }
            return String(localized: "最新 \(formatter.string(from: latest.date)) · 数据已整理")
        }
        return reportViewModel.isLoading ? String(localized: "正在整理最近一次报告") : String(localized: "日报、周报和月报各自独立成篇")
    }

    private func editorialSectionTitle(eyebrow: String, title: String, subtitle: String) -> some View {
        _editorialSectionTitle(title: title)
    }

    private func editorialSectionTitle(_ title: String) -> some View {
        _editorialSectionTitle(title: title)
    }

    private func _editorialSectionTitle(title: String) -> some View {
        Text(title)
            .font(.appSystem(.title3, design: .rounded).weight(.black))
            .foregroundStyle(.primary)
    }

    private func editorialArrowLabel(_ title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.appSystem(size: 12, weight: .black, design: .rounded))
            Image(systemName: "arrow.right")
                .font(.appSystem(size: 10, weight: .black))
        }
        .foregroundColor(tint)
    }

    private func focusSymbol(for module: HealthProfileModule) -> String {
        switch module {
        case .sleep: return "moon.zzz.fill"
        case .stress: return "brain.head.profile"
        case .activity: return "figure.run"
        case .sedentary: return "figure.seated.side.right"
        case .habits: return "checkmark.seal.fill"
        case .reproductive: return "heart.circle.fill"
        case .symptoms: return "pills.fill"
        case .healthKit: return "heart.text.square.fill"
        }
    }

    private func focusModuleTitle(_ module: HealthProfileModule) -> String {
        switch module {
        case .sleep: return String(localized: "睡眠")
        case .stress: return String(localized: "压力")
        case .activity: return String(localized: "活动")
        case .sedentary: return String(localized: "久坐")
        case .habits: return String(localized: "日常行动")
        case .reproductive: return String(localized: "周期健康")
        case .symptoms: return String(localized: "用药与症状")
        case .healthKit: return String(localized: "健康档案")
        }
    }

    private func focusTint(for item: HealthHubFocusItem) -> Color {
        switch item.kind {
        case .risk: return Color(hex: "D96552")
        case .recommendation:
            return item.badgeText == HealthProfileActionPriority.high.title
                ? Color(hex: "D96552")
                : Color(hex: "4B7F72")
        case .change: return Color(hex: "6278C8")
        case .building: return Color(hex: "B47A22")
        }
    }

    private func destination(for module: HealthProfileModule) -> HealthHubDestination {
        switch module {
        case .sleep: return .sleep
        case .stress: return .pressure
        case .activity: return .fitness
        case .sedentary: return .sedentary
        case .habits: return .dailyAction
        case .reproductive: return .reproductiveHealth
        case .symptoms: return .medicationSymptoms
        case .healthKit: return .healthProfile
        }
    }

    private func openQuickAction(_ action: HealthHubQuickAction) {
        switch action {
        case .capability(let item):
            openCapability(item)
        case .sleep:
            hubDestination = .sleep
        }
    }

    private func openCapability(_ item: HealthCapabilityItem) {
        switch item {
        case .fitness: hubDestination = .fitness
        case .activeEnergy: hubDestination = .activeEnergy
        case .basalEnergy: hubDestination = .basalEnergy
        case .bodyAge: hubDestination = .bodyAge
        case .bodyProfile: hubDestination = .bodyProfile
        case .healthProfile: hubDestination = .healthProfile
        case .wristTemperature: hubDestination = .wristTemperature
        case .walkingAsymmetry: hubDestination = .walkingAsymmetry
        case .dailyAction: hubDestination = .dailyAction
        case .drink: hubDestination = .drink
        case .meal: hubDestination = .meal
        case .mood: hubDestination = .mood
        case .sedentary: hubDestination = .sedentary
        case .environmentNoise: hubDestination = .environmentNoise
        case .medicationSymptoms: openMedicationCenter()
        case .reproductiveHealth: hubDestination = .reproductiveHealth
        case .friends: hubDestination = .friends
        }
    }

    /// 打开前重新激活基于条目的导航目标，避免返回健康页后旧的同值枚举状态吞掉第一次点击。
    private func openMedicationCenter() {
        hubDestination = nil
        Task { @MainActor in
            await Task.yield()
            hubDestination = .medicationSymptoms
        }
    }

    private func capabilitySnapshot(for item: HealthCapabilityItem) -> HealthCapabilitySnapshot {
        switch item {
        case .fitness:
            return .init(value: activeEnergyValueText, unit: "千卡", note: "锻炼 \(exerciseMinutesValueText) 分钟", progress: activityProgressValue)
        case .activeEnergy:
            let card = habitViewModel.makeActiveEnergyCard()
            return .init(value: card.valueText, unit: card.unitText, note: card.subtitleText, progress: activityProgressValue)
        case .basalEnergy:
            let card = habitViewModel.makeBasalEnergyCard()
            return .init(value: card.valueText, unit: card.unitText, note: card.subtitleText, progress: card.isEmpty ? 0.1 : 0.58)
        case .bodyAge:
            return .init(value: bodyAgeHubCardModel.displayValue, unit: "岁", note: bodyAgeHubCardModel.compareText, progress: 0)
        case .bodyProfile:
            return .init(value: bodyProfileCompactValueText, unit: bodyProfileCompactUnitText, note: bodyProfileBMI == nil ? "补充身高体重" : "身体数据已建立", progress: bodyProfileCompletionProgress)
        case .healthProfile:
            return .init(value: healthProfileCardValueText, unit: healthProfileCardUnitText, note: healthProfileSummary?.status.title ?? "长期档案建立中", progress: Double(healthProfileSummary?.growthScore ?? 0) / 100)
        case .wristTemperature:
            let card = habitViewModel.makeWristTemperatureCard()
            return .init(value: card.valueText, unit: card.unitText, note: card.subtitleText, progress: card.isEmpty ? 0.1 : 0.5)
        case .walkingAsymmetry:
            let metric = dashboardViewModel.otherMetrics.first { $0.destination == .walkingAsymmetry }
            return .init(value: metric?.valueText ?? "--", unit: metric?.unitText ?? "%", note: metric?.statusText ?? "等待健康 App 同步", progress: 0.24)
        case .dailyAction:
            return .init(value: dailyGoalProgressValueText, unit: "项", note: "完成今天的健康计划", progress: dailyGoalProgressValue)
        case .drink:
            return .init(value: waterValueText, unit: "毫升", note: "咖啡因余量 \(caffeineValueText) 毫克", progress: drinkWaterProgressValue)
        case .meal:
            return .init(value: "拍照", unit: "", note: "识别并记录今天的餐食", progress: 0)
        case .mood:
            return .init(value: moodRecoveryValueText, unit: moodRecoveryUnitText, note: todayMoodEntries.isEmpty ? "留下一次情绪感受" : "今天已记录情绪", progress: moodRecoveryProgress)
        case .sedentary:
            return .init(value: sedentaryCompactValueNumberText, unit: sedentaryCompactValueUnitText, note: dashboardViewModel.sedentaryInsightContent.cardSummary, progress: sedentaryProgressValue)
        case .environmentNoise:
            return .init(value: environmentNoiseValueText, unit: environmentNoiseUnitText, note: "观察环境声音暴露", progress: environmentNoiseProgressValue)
        case .medicationSymptoms:
            return .init(value: medicationSymptomsHeadlineText, unit: "", note: medicationSymptomsSummaryText, progress: 0)
        case .reproductiveHealth:
            return .init(value: "记录", unit: "", note: "周期与阶段性身体变化", progress: 0)
        case .friends:
            return .init(value: "共享", unit: "", note: "与可信任的人建立健康协作", progress: 0)
        }
    }

    /// 每个网格使用独立的不透明视图边界，避免 SwiftUI 为整个仪表盘实例化层级过深的泛型类型。
    private var healthReferenceEntryGrids: some View {
        VStack(alignment: .leading, spacing: adaptiveLayout.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                hubSectionHeader(title: "今日记录", tint: accentMint)
                healthReferenceWeekStrip
                primaryHealthReferenceGrid
            }

            VStack(alignment: .leading, spacing: 10) {
                hubSectionHeader(title: "监测与提醒", tint: accentAmber)
                secondaryHealthReferenceGrid
            }

            VStack(alignment: .leading, spacing: 10) {
                hubSectionHeader(title: "档案与社交", tint: accentRose)
                tertiaryHealthReferenceGrid
            }
        }
    }

    private var primaryHealthReferenceGrid: some View {
        LazyVGrid(columns: healthReferenceGridColumns, spacing: 14) {
            AnyView(
                Button {
                    route = .dailyAction
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.dailyGoal,
                        symbol: "target",
                        tint: accentMint,
                        value: dailyGoalProgressValueText,
                        unit: "",
                        progress: dailyGoalProgressValue
                    )
                }
                .bbCardButtonStyle()
            )

            AnyView(
                Button {
                    route = .moodHub
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.mentalRecovery,
                        symbol: "face.smiling.inverse",
                        tint: Color(hex: "39B98A"),
                        value: moodRecoveryValueText,
                        unit: moodRecoveryUnitText,
                        progress: moodRecoveryProgress
                    )
                }
                .bbCardButtonStyle()
            )

            AnyView(
                Button {
                    hubDestination = .sedentary
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.sedentaryReminder,
                        symbol: "figure.seated.side.right",
                        tint: sedentaryTint,
                        value: sedentaryCompactValueNumberText,
                        unit: sedentaryCompactValueUnitText,
                        progress: sedentaryProgressValue
                    )
                }
                .bbCardButtonStyle()
                .accessibilityLabel("久坐提醒")
                .accessibilityValue(dashboardViewModel.sedentaryReminderEnabled ? "提醒已开启" : "提醒已关闭")
            )

            AnyView(
                Button {
                    route = .drinkHub
                } label: {
                    healthReferenceDrinkCard
                }
                .bbCardButtonStyle()
            )

            // 首页只负责进入餐食识别流程；图片去向和人工确认要求在识别页继续明确展示。
            AnyView(
                Button {
                    route = .mealHub
                } label: {
                    healthReferenceSmallCard(
                        title: "餐食识别",
                        symbol: "fork.knife",
                        tint: accentCoral,
                        value: "AI",
                        unit: "热量估算",
                        progress: 0
                    )
                }
                .bbCardButtonStyle()
                .accessibilityLabel("餐食识别")
                .accessibilityValue("拍照或选择图片估算餐食热量")
            )
        }
    }

    private var secondaryHealthReferenceGrid: some View {
        LazyVGrid(columns: healthReferenceGridColumns, spacing: 14) {
            // 将 CareKit 风格用药任务和症状观察合并为一个健康记录入口。
            AnyView(
                Button {
                    openMedicationCenter()
                } label: {
                    medicationSymptomsReferenceCard
                }
                .bbCardButtonStyle()
                .accessibilityLabel("用药感受")
                .accessibilityValue(medicationSymptomsAccessibilityText)
            )

            AnyView(
                Button {
                    hubDestination = .environmentNoise
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.environmentNoise,
                        symbol: "ear",
                        tint: Color(hex: "F1C84B"),
                        value: environmentNoiseValueText,
                        unit: environmentNoiseUnitText,
                        progress: environmentNoiseProgressValue
                    )
                }
                .bbCardButtonStyle()
            )

        }
    }

    private var tertiaryHealthReferenceGrid: some View {
        LazyVGrid(columns: healthReferenceGridColumns, spacing: 14) {
            AnyView(
                Button {
                    hubDestination = .bodyProfile
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.bodyProfile,
                        symbol: "ruler.fill",
                        tint: Color(hex: "91C783"),
                        value: bodyProfileCompactValueText,
                        unit: bodyProfileCompactUnitText,
                        progress: bodyProfileCompletionProgress
                    )
                }
                .bbCardButtonStyle()
            )

            AnyView(
                Button {
                    hubDestination = .healthProfile
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.healthProfile,
                        symbol: "person.crop.circle.badge.checkmark",
                        tint: healthProfileCardTint,
                        value: healthProfileCardValueText,
                        unit: healthProfileCardUnitText,
                        progress: healthProfileCardProgress
                    )
                }
                .bbCardButtonStyle()
            )

            AnyView(
                Button {
                    navigateToReproductiveRecord()
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.femaleHealth,
                        symbol: "heart.circle.fill",
                        tint: Color(hex: "F35F9B"),
                        value: "记录",
                        unit: "周期健康",
                        progress: 0
                    )
                }
                .bbCardButtonStyle()
                .accessibilityLabel("周期健康")
                .accessibilityValue("周期健康记录")
            )

            AnyView(
                Button {
                    hubDestination = .friends
                } label: {
                    healthReferenceSmallCard(
                        title: HealthPageName.friends,
                        symbol: "person.2.fill",
                        tint: Color(hex: "FF7A59"),
                        value: "进入",
                        unit: "共享 · 协作",
                        progress: 0
                    )
                }
                .bbCardButtonStyle()
                .accessibilityLabel("好友")
                .accessibilityValue("健康共享与好友协作")
            )

            // 照护中心：聚合服药打卡、康复训练、健康习惯、症状日记的统一入口。
            AnyView(
                Button {
                    route = .careHub
                } label: {
                    healthReferenceSmallCard(
                        title: "照护中心",
                        symbol: "cross.case.fill",
                        tint: Color(hex: "8B7EE8"),
                        value: careHubCardValueText,
                        unit: "计划 · 打卡",
                        progress: careHubCardProgress
                    )
                }
                .bbCardButtonStyle()
                .accessibilityLabel("照护中心")
                .accessibilityValue("服药打卡、康复训练、健康习惯和症状日记")
            )
        }
    }

    private var healthReferenceDateHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(healthReferenceTitleText)
                    .font(.appSystem(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "2C333C"))

                Text(healthReferenceSubtitleText)
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "9AA3AD"))
            }

            Spacer(minLength: 0)

            if !Calendar.current.isDateInToday(selectedDate) {
                Button {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.appSystem(size: 11, weight: .black))
                        Text("回今天")
                            .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    }
                    .foregroundColor(Color(hex: "176B52"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(accentMint.opacity(0.12), in: Capsule())
                }
                .bbCardButtonStyle()
            }

            Button {
                hubDestination = .reports
            } label: {
                Image(systemName: "calendar")
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.Colors.surface.opacity(0.88), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .shadow(color: cardShadow, radius: 8, x: 0, y: 4)
            }
            .bbCardButtonStyle()
            .accessibilityLabel("选择日期")
        }
        .padding(.horizontal, 6)
    }

    private var healthReferenceWeekStrip: some View {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: selectedDate)
        let interval = calendar.dateInterval(of: .weekOfYear, for: normalizedDate)
        let weekStart = interval?.start ?? normalizedDate
        let scrollableDates = (-21..<28).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(scrollableDates, id: \.self) { date in
                        let isSelectable = isDateSelectable(date)
                        Button {
                            guard isSelectable else { return }
                            selectedDate = Calendar.current.startOfDay(for: date)
                        } label: {
                            healthReferenceDateCell(for: date)
                        }
                        .bbCardButtonStyle()
                        .disabled(!isSelectable)
                        .id(Calendar.current.startOfDay(for: date))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onAppear {
                scrollHealthReferenceWeekStrip(to: selectedDate, proxy: proxy)
            }
            .onChange(of: selectedDate) { _, newValue in
                scrollHealthReferenceWeekStrip(to: newValue, proxy: proxy)
            }
        }
    }

    private func scrollHealthReferenceWeekStrip(to date: Date, proxy: ScrollViewProxy) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                proxy.scrollTo(normalizedDate, anchor: .center)
            }
        }
    }

    /// 多彩糖果日期格：每个星期几对应一个糖果色，未选中是白色小胶囊 + 彩色星期字，
    /// 选中态整格填充当日主题色渐变，让周条像一排彩色糖果。
    private func healthReferenceDateCell(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isSelectable = isDateSelectable(date)
        let isToday = Calendar.current.isDateInToday(date)
        let tint = weekdayAccentColor(for: date)

        return VStack(spacing: 4) {
            Text(weekdayShortText(for: date))
                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? Color.white.opacity(0.92) : (isSelectable ? tint : Color(hex: "C9D2DB")))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(dayNumberText(for: date))
                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: isSelectable ? "3E4650" : "AAB3BD"))

            Circle()
                .fill(isToday ? (isSelected ? Color.white.opacity(0.95) : tint) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(width: 46, height: 62)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.86), tint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: tint.opacity(0.38), radius: 9, x: 0, y: 5)
                } else {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.white.opacity(isSelectable ? 0.92 : 0.55))
                        .shadow(color: cardShadow.opacity(isSelectable ? 1 : 0), radius: 5, x: 0, y: 3)
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(
                            tint.opacity(isToday ? 0.55 : (isSelectable ? 0.16 : 0.06)),
                            lineWidth: isToday ? 1.5 : 1
                        )
                }
            }
        )
        .opacity(isSelectable || isSelected ? 1 : 0.6)
    }

    /// 日期格主题色：按效果图统一为今日页主绿，选中格填充、未选中格只染星期字。
    private func weekdayAccentColor(for date: Date) -> Color {
        accentMint
    }

    /// 卡片统一底面：白色基底 + 主题色的微弱渐变染色，让卡片与入口色彩呼应。
    private func hubCardSurface(tint: Color, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.82))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.095),
                            Color.white.opacity(0.05),
                            tint.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    /// 横向紧凑入口卡：左侧图标带环形进度，中间标题与数值，右侧箭头。
    /// 相比旧的方形瓷砖高度减半，让首页一屏能容纳更多入口。
    private func healthReferenceSmallCard(
        title: LocalizedStringKey,
        symbol: String,
        tint: Color,
        value: String,
        unit: String,
        progress: Double,
        note: String? = nil,
        showsAccessory: Bool = true
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.12), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: clampedProgress(progress))
                    .stroke(tint.opacity(0.8), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.appSystem(size: 19, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "2E353D"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                    Text(unit)
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "B3B8BE"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                if let note {
                    Text(note)
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "9AA3AD"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            if showsAccessory {
                Image(systemName: Theme.Icons.chevronRight)
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Color(hex: "A9ADB4"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(hubCardSurface(tint: tint, cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: cardShadow, radius: 10, x: 0, y: 5)
    }

    private var healthReferenceDrinkCard: some View {
        healthReferenceSmallCard(
            title: "饮品",
            symbol: "drop.fill",
            tint: Color(hex: "58D5E5"),
            value: waterValueText == "--" ? "0" : waterValueText,
            unit: "毫升",
            progress: drinkWaterProgressValue,
            note: "咖啡因 \(caffeineValueText) 毫克"
        )
    }

    private var medicationSymptomsReferenceCard: some View {
        healthReferenceSmallCard(
            title: "用药感受",
            symbol: "pills.fill",
            tint: Color(hex: "6B7CFF"),
            value: medicationSymptomsHeadlineText,
            unit: "",
            progress: 0,
            note: medicationSymptomsSummaryText
        )
    }

    private var healthReferenceGridColumns: [GridItem] {
        let minWidth: CGFloat = adaptiveLayout.containerWidth < 370 ? 138 : 154
        return [
            GridItem(.adaptive(minimum: minWidth, maximum: 230), spacing: 14)
        ]
    }

    private var healthReferenceTitleText: String {
        Calendar.current.isDateInToday(selectedDate) ? "今天" : healthReferenceSelectedDateText
    }

    private var healthReferenceSubtitleText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        if Calendar.current.isDateInToday(selectedDate) {
            formatter.setLocalizedDateFormatFromTemplate("MEd")
            return formatter.string(from: selectedDate)
        }
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return "\(formatter.string(from: selectedDate)) · 历史回顾"
    }

    private var healthReferenceSelectedDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("MMdd")
        return formatter.string(from: selectedDate)
    }

    private var bodyProfileBMI: Double? {
        guard let height = bodyProfileHeightCm,
              let weight = bodyProfileWeightKg,
              height > 0,
              weight > 0 else {
            return nil
        }
        let heightM = height / 100.0
        return weight / (heightM * heightM)
    }

    private func weekdayShortText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("E")
        return formatter.string(from: date)
    }

    private func dayNumberText(for date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

    private func isDateSelectable(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date())
    }

    private func loadHealthProfileSummary() async {
        guard !isHealthProfileLoading else { return }
        isHealthProfileLoading = true
        let summary = await HealthProfileSummaryStore.shared.summary(range: .thirtyDays)
        healthProfileSummary = summary
        isHealthProfileLoading = false
    }

    @MainActor
    private func loadBodyProfile() async {
        async let height = HealthKitManager.shared.fetchLatestHeightCm()
        async let weight = HealthKitManager.shared.fetchLatestBodyMassKg()
        bodyProfileHeightCm = await height
        bodyProfileWeightKg = await weight
    }

    @MainActor
    private func saveBodyProfile(_ record: BodyProfileRecord) async {
        do {
            try await HealthKitManager.shared.saveBodyProfile(
                heightCm: record.heightCm,
                weightKg: record.weightKg,
                date: record.date
            )
            targetWeightKg = record.targetWeightKg
            bodyProfileHeightCm = record.heightCm
            bodyProfileWeightKg = record.weightKg
            hubDestination = nil
            bodyProfileMessage = "已保存到健康 App。趋势页会在健康数据同步后展示图表变化。"
        } catch {
            bodyProfileMessage = "暂时无法写入健康 App，请检查健康权限后再试。"
        }
    }

    private func healthProfileTint(score: Int) -> Color {
        if score >= 80 { return Theme.Colors.mintGreen }
        if score >= 65 { return accentBlue }
        if score >= 45 { return accentAmber }
        return accentCoral
    }

    private var additionalHealthMetricsSection: some View {
        let activeEnergy = habitViewModel.makeActiveEnergyCard()
        let basalEnergy = habitViewModel.makeBasalEnergyCard()
        let wristTemperature = habitViewModel.makeWristTemperatureCard()
        let walkingAsymmetry = dashboardViewModel.otherMetrics.first { $0.destination == .walkingAsymmetry }

        return VStack(alignment: .leading, spacing: 10) {
            hubSectionHeader(title: "更多健康指标", tint: accentBlue)

            sectionCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.appSystem(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "9DB4D8"))
                            .padding(.top, 1)

                        Text("训练消耗与关键体征分别归类，身体年龄已有的影响因子不在这里重复展示。")
                            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "EAF1FB").opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                healthCategoryGroup(
                    title: "健身指标",
                    icon: "figure.run",
                    accentColor: Color(hex: "81D02D")
                ) {
                    LazyVGrid(columns: compactSpecialtyColumns, spacing: 10) {
                        AnyView(
                            NavigationLink {
                                ActiveEnergyDetailView(
                                    card: activeEnergy,
                                    selectedDate: selectedDate,
                                    summary: activeEnergy.comparisonText
                                )
                                .healthDetailNavigation(title: "活动消耗")
                            } label: {
                                additionalMetricTile(activeEnergy)
                            }
                            .buttonStyle(BBCardButtonStyle())
                        )

                        AnyView(
                            NavigationLink {
                                BasalEnergyDetailView(
                                    card: basalEnergy,
                                    selectedDate: selectedDate,
                                    summary: basalEnergy.comparisonText
                                )
                                .healthDetailNavigation(title: "基础代谢")
                            } label: {
                                additionalMetricTile(basalEnergy)
                            }
                            .buttonStyle(BBCardButtonStyle())
                        )
                    }
                }

                healthCategoryGroup(
                    title: "关键体征",
                    icon: "waveform.path.ecg",
                    accentColor: Color(hex: "8266C6")
                ) {
                    LazyVGrid(columns: compactSpecialtyColumns, spacing: 10) {
                        AnyView(
                            NavigationLink {
                                WristTemperatureDetailView(
                                    card: wristTemperature,
                                    selectedDate: selectedDate,
                                    summary: wristTemperature.comparisonText
                                )
                                .healthDetailNavigation(title: "手腕温度")
                            } label: {
                                additionalMetricTile(wristTemperature)
                            }
                            .buttonStyle(BBCardButtonStyle())
                        )

                        if let walkingAsymmetry {
                            AnyView(
                                NavigationLink {
                                    WalkingAsymmetryDetailView(
                                        metric: walkingAsymmetry,
                                        initialDate: selectedDate
                                    )
                                    .healthDetailNavigation(title: "步态不对称")
                                } label: {
                                    compactSpecialtyTile(
                                        title: "步态不对称",
                                        icon: "figure.walk.motion",
                                        accentColor: Color(hex: "33A6DA"),
                                        value: walkingAsymmetry.valueText + walkingAsymmetry.unitText,
                                        note: walkingAsymmetry.statusText
                                    )
                                }
                                .buttonStyle(BBCardButtonStyle())
                            )
                        }
                    }
                }
                }
            }
        }
    }

    private func additionalMetricTile(_ card: HabitBodyMetricCardModel) -> some View {
        compactSpecialtyTile(
            title: card.title,
            icon: card.symbol,
            accentColor: Color(hex: card.tintHex),
            value: card.valueText + (card.unitText.isEmpty ? "" : "\(card.unitText)"),
            note: card.subtitleText
        )
    }

    private var sedentaryProgressValue: Double {
        let state = dashboardViewModel.sedentaryState
        if state.sourceStatus == .sleeping {
            return 0.18
        }
        if state.sourceStatus == .needsAuthorization || state.sourceStatus == .autoStartDisabled {
            return 0.22
        }
        if state.sourceStatus == .unavailable || state.sourceStatus == .noActivitySamples {
            return 0.12
        }
        let progress = Double(state.elapsedMinutes) / 120.0
        return min(max(progress, 0.10), 1.0)
    }

    private var sedentaryCompactValueNumberText: String {
        let content = dashboardViewModel.sedentaryInsightContent
        let raw = content.cardValueText
        if raw == "--" || raw.isEmpty {
            return String(localized: "待同步")
        }
        if let digits = raw.range(of: #"\d+"#, options: .regularExpression) {
            return String(raw[digits])
        }
        return raw
    }

    private var sedentaryCompactValueUnitText: String {
        let content = dashboardViewModel.sedentaryInsightContent
        if content.cardValueUnit == "min" {
            return String(localized: "分")
        }
        if !content.cardValueUnit.isEmpty {
            return content.cardValueUnit
        }
        if sedentaryCompactValueNumberText != content.cardValueText {
            let suffix = content.cardValueText.replacingOccurrences(of: sedentaryCompactValueNumberText, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty {
                return suffix
            }
        }
        return ""
    }

    private var bodyAgeHubCardModel: BodyAgeHubCardModel {
        let summary = healthDataManager.bodyAgeSummary
        return BodyAgeHubCardModel(
            bodyAge: summary?.valueYears,
            chronologicalAge: healthAge ?? onboardingAge,
            statusText: summary?.statusText ?? String(localized: "等待数据"),
            dataCoverageText: summary?.coverageText ?? String(localized: "健康 App 暂无数据"),
            trendValues: summary?.trendValues ?? [],
            tint: bodyAgeInsightTint
        )
    }

    private var bodyAgeHubCardAccessibilityValue: String {
        let model = bodyAgeHubCardModel
        return String(localized: "\(model.headline)，\(model.displayValue) 岁，\(model.statusText)，\(model.dataCoverageText)")
    }

    private var effectivePressureAssessment: StressPresentationAssessment {
        let assessment = dashboardViewModel.dailyStressAssessment
        guard !assessment.hasData else { return assessment }
        return dashboardViewModel.currentStressAssessment
    }

    private func navigateToReproductiveRecord() {
        openReproductiveRecord()
        route = .reproductiveRecord
    }

    private var activeEnergyValueText: String {
        guard let value = AppGroupManager.shared.getActiveEnergy(), value > 0 else {
            return "--"
        }
        return "\(value)"
    }

    private var stepCountValueText: String {
        guard habitViewModel.stepCount > 0 else { return "--" }
        return habitViewModel.stepCount.formatted(.number.grouping(.automatic))
    }

    private var sleepHoursValueText: String {
        guard habitViewModel.sleepDuration > 0 else { return "--" }
        return String(format: "%.1f", Double(habitViewModel.sleepDuration) / 60)
    }

    private var exerciseMinutesValueText: String {
        guard let value = AppGroupManager.shared.getExerciseMinutes(), value > 0 else {
            return "--"
        }
        return "\(value)"
    }

    private var activityProgressValue: Double {
        if let stored = AppGroupManager.shared.getActivityCompletionRate() {
            return clampedProgress(stored)
        }

        let parts = [
            AppGroupManager.shared.getActiveEnergyCompletionRate(),
            AppGroupManager.shared.getExerciseMinutesCompletionRate(),
            AppGroupManager.shared.getStandHoursCompletionRate()
        ].compactMap { $0 }

        guard !parts.isEmpty else { return 0.10 }
        return clampedProgress(parts.reduce(0, +) / Double(parts.count))
    }

    private var waterValueText: String {
        guard let value = AppGroupManager.shared.getWaterIntakeMl(), value > 0 else {
            return "--"
        }
        return "\(Int(value.rounded()))"
    }

    private var drinkWaterProgressValue: Double {
        guard let rate = AppGroupManager.shared.getWaterCompletionRate() else { return 0 }
        return clampedProgress(rate)
    }

    private var caffeineValueText: String {
        guard let value = AppGroupManager.shared.getCaffeineRemainedMg(), value > 0 else {
            return "0"
        }
        return "\(Int(value.rounded()))"
    }

    private var environmentNoiseValueText: String {
        guard let value = healthDataManager.currentActivity?.environmental_audio_exposure_db, value > 0 else { return "--" }
        return "\(Int(value.rounded()))"
    }

    private var environmentNoiseUnitText: String {
        environmentNoiseValueText == "--" ? "待同步" : "dB"
    }

    private var environmentNoiseProgressValue: Double {
        guard let value = healthDataManager.currentActivity?.environmental_audio_exposure_db, value > 0 else {
            return 0.10
        }
        return clampedProgress((value - 40) / 45.0)
    }

    private func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0.08), 1)
    }

    private var todayMedicationEntries: [MedicationEntry] {
        MedicationStore.shared.todayEntries(on: selectedDate)
    }

    private var medicationTaskEvents: [MedicationTaskEvent] {
        MedicationStore.shared.taskEvents(on: selectedDate, referenceDate: Date())
    }

    private var medicationTaskCompletedCount: Int {
        medicationTaskEvents.filter { $0.status == .completed }.count
    }

    private var medicationTaskOverdueCount: Int {
        medicationTaskEvents.filter { $0.status == .overdue }.count
    }

    private var medicationTaskSummaryText: String {
        if medicationTaskOverdueCount > 0 {
            return String(localized: "待补记 \(medicationTaskOverdueCount) 项")
        }
        if !medicationTaskEvents.isEmpty && medicationTaskCompletedCount == medicationTaskEvents.count {
            return String(localized: "今日计划已完成")
        }
        if !medicationTaskEvents.isEmpty {
            return String(localized: "计划记录进行中")
        }
        return latestMedicationNameText
    }

    private var medicationTaskAccessibilityText: String {
        if medicationTaskEvents.isEmpty {
            return todayMedicationEntries.isEmpty ? "暂无今日计划" : "今日已有记录"
        }
        return String(localized: "已完成 \(medicationTaskCompletedCount) 项，共 \(medicationTaskEvents.count) 项，\(medicationTaskSummaryText)")
    }

    private var medicationSymptomsSummaryText: String {
        let symptomCount = todaySymptomObservationCount
        if medicationTaskOverdueCount > 0 {
            return String(localized: "用药计划待补记 \(medicationTaskOverdueCount) 项，症状记录 \(symptomCount) 条")
        }
        if medicationTaskCompletedCount > 0 || symptomCount > 0 {
            return String(localized: "今日已记录用药 \(todayMedicationEntries.count) 条、症状 \(symptomCount) 条")
        }
        return String(localized: "在同一模块记录计划、实际用药和身体症状")
    }

    private var medicationSymptomsHeadlineText: String {
        let symptomCount = todaySymptomObservationCount
        if medicationTaskCompletedCount > 0 && symptomCount > 0 {
            return String(localized: "今日已联动")
        }
        if medicationTaskOverdueCount > 0 {
            return String(localized: "待补记 \(medicationTaskOverdueCount) 项")
        }
        if medicationTaskCompletedCount > 0 {
            return "待记症状"
        }
        if symptomCount > 0 {
            return "待记用药"
        }
        return String(localized: "今日待记录")
    }

    private var todaySymptomObservationCount: Int {
        SelfObservationStore.shared.records(on: selectedDate).filter(\.isSymptomObservation).count
    }

    // MARK: - 照护中心卡片

    /// 照护中心卡片展示的今日任务完成数。
    private var careHubCardValueText: String {
        let events = CareTaskEngine.shared.events(on: selectedDate, referenceDate: selectedDate)
        let total = events.count
        let completed = events.filter { $0.status == .completed }.count
        if total == 0 { return "无任务" }
        return "\(completed)/\(total)"
    }

    /// 照护中心卡片进度条比例（基于今日完成率）。
    private var careHubCardProgress: Double {
        let events = CareTaskEngine.shared.events(on: selectedDate, referenceDate: selectedDate)
        guard !events.isEmpty else { return 0 }
        let completed = events.filter { $0.status == .completed }.count
        return Double(completed) / Double(events.count)
    }

    private var medicationSymptomsAccessibilityText: String {
        let symptomText: String
        if latestSymptomObservationRecord != nil {
            symptomText = "最近症状为 \(latestSymptomText)，程度 \(latestSymptomSeverityText)"
        } else {
            symptomText = "暂无症状观察记录"
        }
        return "\(medicationTaskAccessibilityText)，\(symptomText)"
    }

    private var latestMedicationEntry: MedicationEntry? {
        todayMedicationEntries.sorted(by: { $0.takenAt > $1.takenAt }).first
    }

    private var latestMedicationNameText: String {
        guard let latest = latestMedicationEntry else {
            return String(localized: "待补充")
        }
        return "\(latest.category.title) · \(latest.name)"
    }

    private var todayMoodEntries: [MoodEntry] {
        MoodStore.shared.entries(on: selectedDate)
    }

    private var todayMealSummary: (totalCalories: Int, slots: [MealSlot: MealRecognitionRecord]) {
        DrinkExperienceStore.shared.todayMealSummary(on: selectedDate)
    }

    private var todayMealRecordValueText: String {
        guard !todayMealSummary.slots.isEmpty else {
            return String(localized: "去记录")
        }
        return String(localized: "\(todayMealSummary.slots.count) 餐")
    }

    private var bodyAgeInsightTint: Color {
        if effectivePressureAssessment.band == .caution || effectivePressureAssessment.band == .high {
            return Color(hex: "F46B5A")
        }
        if effectivePressureAssessment.band == .mild {
            return Color(hex: "FF9F0A")
        }
        return Color(hex: "5B8CFF")
    }

    private func tint(for tint: StressTint) -> Color {
        switch tint {
        case .tertiary:
            return Color(hex: "8A97AC")
        case .mintGreen:
            return accentMint
        case .orange:
            return Color(hex: "F4A259")
        case .orangeDeep:
            return accentAmber
        case .accentRed:
            return accentCoral
        }
    }

    private var sedentaryTint: Color {
        let state = dashboardViewModel.sedentaryState
        if state.sourceStatus == .needsAuthorization { return Color(hex: "4C7DFF") }
        if state.sourceStatus == .sleeping { return Color(hex: "5E5CE6") }
        if state.sourceStatus == .autoStartDisabled { return Color(hex: "8FA1B8") }
        if state.sourceStatus == .noActivitySamples { return Color(hex: "8FA1B8") }
        if state.sourceStatus == .unavailable { return accentCoral }
        let minutes = state.elapsedMinutes
        if minutes >= 90 { return Color(hex: "F46B5A") }
        if minutes >= 60 { return Color(hex: "F3A53B") }
        return Color(hex: "72D66B")
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
    }

    /// 宫格分组节标题，样式对齐报告页 ReportsSection 的标题，左侧加彩色强调条区分分组。
    private func hubSectionHeader(title: LocalizedStringKey, tint: Color = Color(hex: "9AA3AD")) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 15)

            Text(title)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "555B58"))
        }
        .padding(.horizontal, 4)
    }

    private func sectionHeader(title: String, subtitle: String, eyebrow: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            Text(title)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "0F2C57"))
            Text(subtitle)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dailyGoalProgressValueText: String {
        "\(habitViewModel.dailyWellnessSummary.todayCompletedCount)/\(DailyWellnessActionKind.allCases.count)"
    }

    private var dailyGoalProgressValue: Double {
        let total = max(DailyWellnessActionKind.allCases.count, 1)
        return Double(habitViewModel.dailyWellnessSummary.todayCompletedCount) / Double(total)
    }

    private var bodyProfileCompactValueText: String {
        if let bmi = bodyProfileBMI {
            return String(format: "%.1f", bmi)
        }
        if let weight = bodyProfileWeightKg {
            return String(format: "%.1f", weight)
        }
        return "--"
    }

    private var bodyProfileCompactUnitText: String {
        bodyProfileBMI == nil && bodyProfileWeightKg != nil ? "kg" : "BMI"
    }

    private var bodyProfileCompletionProgress: Double {
        var count = 0
        if bodyProfileHeightCm != nil { count += 1 }
        if bodyProfileWeightKg != nil { count += 1 }
        return Double(count) / 2.0
    }

    private var selfObservationRecords: [SelfObservationRecord] {
        SelfObservationStore.shared.allRecords()
    }

    private var latestSymptomObservationRecord: SelfObservationRecord? {
        selfObservationRecords.first(where: \.isSymptomObservation)
    }

    private var moodRecoveryValueText: String {
        guard !todayMoodEntries.isEmpty else { return "--" }
        return "\(todayMoodEntries.count)"
    }

    private var moodRecoveryUnitText: String {
        todayMoodEntries.isEmpty ? "待记录" : "次"
    }

    private var moodRecoveryProgress: Double {
        min(max(Double(todayMoodEntries.count) / 3.0, 0), 1)
    }

    private var healthProfileCardValueText: String {
        guard let summary = healthProfileSummary else { return "--" }
        return "\(summary.growthScore)"
    }

    private var healthProfileCardUnitText: String {
        healthProfileSummary == nil ? (isHealthProfileLoading ? "整理中" : "待建立") : "成长分"
    }

    private var healthProfileCardProgress: Double {
        min(max(Double(healthProfileSummary?.growthScore ?? 0) / 100.0, 0), 1)
    }

    private var healthProfileCardTint: Color {
        healthProfileSummary.map { healthProfileTint(score: $0.growthScore) } ?? Theme.Colors.mintGreen
    }

    private var latestSymptomText: String {
        latestSymptomObservationRecord?.symptomTitleText ?? "等待记录"
    }

    private var latestSymptomSeverityText: String {
        guard let record = latestSymptomObservationRecord else { return "暂无" }
        return SelfObservationCatalog.severityText(record.symptomSeverity)
    }

    private struct SpecialtyStat: Identifiable {
        let label: String
        let value: String
        let unit: String

        init(label: String, value: String, unit: String = "") {
            self.label = label
            self.value = value
            self.unit = unit
        }

        var id: String { "\(label)-\(value)-\(unit)" }
    }

    private func healthCategoryGroup<Content: View>(
        title: String,
        icon: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.appSystem(size: 14, weight: .black))
                    .foregroundColor(accentColor)
                    .frame(width: 32, height: 32)
                    .bbTintedChip(tint: accentColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous), tintOpacity: 0.08)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "14213D"))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(12)
        .background(Theme.Colors.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        )
    }

    private enum SpecialtyVisual {
        case bars([CGFloat])
        case progress(Double)
        case segments([Color])
        case dots([Color])
        case lineSeries([Double])
        case symbol
    }

    private var compactSpecialtyColumns: [GridItem] {
        // 横向行卡信息密度高，常规宽度单列即可；扩展布局下并排两列。
        let columnCount = adaptiveLayout.usesExpandedLayout ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columnCount)
    }

    /// 横向指标行：图标居左，标题与说明居中，数值右对齐，取代旧的方形瓷砖以提升密度。
    private func compactSpecialtyTile(
        title: String,
        icon: String,
        accentColor: Color,
        value: String,
        note: String
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(accentColor)
                .frame(width: 32, height: 32)
                .bbTintedChip(tint: accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous), tintOpacity: 0.08)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "14213D"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(note)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "6D7684"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "151A23"))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Image(systemName: Theme.Icons.chevronRight)
                .font(.appSystem(size: 11, weight: .black))
                .foregroundColor(Color(hex: "A1AAB7"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.66),
                    accentColor.opacity(0.035)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .bbTintedSurface(tint: accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintStrength: 0.045, shadow: false)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
    }

}

private extension String {
    /// 是否为纯数字文本（整数/小数），用于决定是否启用数字滚动过渡。
    var bbIsPureNumberText: Bool {
        !isEmpty && Double(self) != nil
    }
}

private struct HealthCapabilitySnapshot {
    let value: String
    let unit: String
    let note: String
    let progress: Double
}


#Preview {
    NavigationStack {
        HealthHubView(
            periodViewModel: PeriodViewModel(),
            openReproductiveRecord: { },
            route: .constant(nil),
            goalLinkedAction: nil,
            goalLinkedDate: nil
        )
    }
}

/// Body Age Hub Card Model 由 `HealthHubView` 调用，作为首页"身体年龄"入口卡片的数据模型。
/// 负责把身体年龄结果、年龄对比文案和趋势条高度整理成首页可直接渲染的轻量展示数据。
struct BodyAgeHubCardModel {
    let headline: String
    let displayValue: String
    let footer: String
    let compareText: String
    let trendBarHeights: [CGFloat]
    let tint: Color
    let dataCoverageText: String
    let statusText: String

    init(
        bodyAge: Double?,
        chronologicalAge: Int,
        statusText: String,
        dataCoverageText: String,
        trendValues: [Double],
        tint: Color
    ) {
        self.statusText = statusText
        self.dataCoverageText = dataCoverageText
        self.tint = tint
        self.headline = bodyAge == nil ? String(localized: "等待身体年龄") : String(localized: "当前身体年龄")
        self.displayValue = bodyAge.map { String(Int($0.rounded())) } ?? "--"

        if let bodyAge {
            let delta = bodyAge - Double(chronologicalAge)
            if abs(delta) < 1 {
                self.compareText = String(localized: "基本一致")
                self.footer = String(localized: "接近实际年龄")
            } else if delta < 0 {
                self.compareText = String(localized: "年轻 \(Int(abs(delta).rounded())) 岁")
                self.footer = String(localized: "比实际年龄更年轻")
            } else {
                self.compareText = String(localized: "偏高 \(Int(delta.rounded())) 岁")
                self.footer = String(localized: "比实际年龄偏高")
            }
        } else {
            self.compareText = String(localized: "等待样本")
            self.footer = statusText
        }

        if trendValues.isEmpty {
            self.trendBarHeights = [18, 26, 22, 30, 24, 34]
        } else {
            let minimum = trendValues.min() ?? 0
            let maximum = trendValues.max() ?? 0
            let span = max(maximum - minimum, 1)
            self.trendBarHeights = trendValues.map { value in
                14 + CGFloat((value - minimum) / span) * 18
            }
        }
    }
}
