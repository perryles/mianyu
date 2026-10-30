/// HealthProfileView 由 HealthHubView 调用，作为「健康画像」详情页。
/// 负责展示健康画像 Hero 区、维度详情、变化洞察与 AI 解读入口。

import SwiftUI

struct HealthProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = HealthProfileViewModel()
    @State private var showingProfileAI = false
    @State private var isDataEvidenceExpanded = false
    @State private var assessmentDate = Calendar.current.startOfDay(for: Date())
    @State var expandedDimensionIDs: Set<HealthProfileDimension.ID> = []
    @State private var insightsTab: InsightsTab = .changes
    let onRecordToday: (() -> Void)?

    init(onRecordToday: (() -> Void)? = nil) {
        self.onRecordToday = onRecordToday
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            } else {
                HealthDetailPageBackground()
            }

            AdaptivePageScrollView(style: .page, topPadding: 16, bottomPadding: 96, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isLoading && viewModel.summary == nil {
                        loadingCard
                    } else if let summary = viewModel.summary,
                              summary.range == viewModel.selectedRange {
                        profileContent(summary)
                    } else if viewModel.isLoading {
                        loadingCard
                    } else {
                        emptyStateCard(
                            title: "你的健康档案正在建立",
                            detail: "继续同步睡眠、心率、活动和日常记录后，这里会开始总结你的长期节律和成长变化。",
                            primaryTitle: "检查健康权限",
                            secondaryTitle: "去记录今天状态",
                            tertiaryTitle: "查看已有数据"
                        )
                    }
                }
            }
        }
        .healthDetailNavigation(title: HealthPageName.healthProfile)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            viewModel.load()
        }
        .onChange(of: viewModel.selectedRange) { _, _ in
            viewModel.load()
        }
        .sheet(isPresented: $showingProfileAI) {
            if let summary = viewModel.summary {
                HealthAIView(profileDigest: summary.aiDigest)
                    .adaptiveSheetChrome(style: .page, detents: [.large], dragIndicator: .visible)
            }
        }
        .alert("健康档案", isPresented: Binding(get: {
            viewModel.authorizationMessage != nil
        }, set: { visible in
            if !visible { viewModel.authorizationMessage = nil }
        })) {
            Button("好") { viewModel.authorizationMessage = nil }
        } message: {
            Text(viewModel.authorizationMessage ?? "")
        }
    }

    private func profileContent(_ summary: HealthProfileSummary) -> some View {
        let presentation = HealthProfilePagePresentation.make(summary: summary)

        return VStack(alignment: .leading, spacing: 20) {
            pageHeroSection(summary)

            if summary.isBuilding {
                buildingStateCard(summary)
            } else {
                focusSection(presentation)
                dimensionsSection(presentation.dimensions)
                insightsSection(
                    changes: summary.changes,
                    tags: summary.tags,
                    milestones: summary.milestones
                )
            }
            dataEvidenceSection(summary)

            if shouldShowSelfAssessment(summary) {
                selfAssessmentPanel(summary)
            }

            HealthDisclaimerCard(
                message: "健康档案用于长期生活方式管理，不提供疾病诊断或治疗建议。AI 解读仅使用当前档案的聚合摘要；出现持续不适或高风险症状时，请及时寻求专业医疗帮助。",
                title: "健康说明",
                style: .compact
            )

            Text("档案更新时间 \(dateTimeText(summary.generatedAt))")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func pageHeroSection(_ summary: HealthProfileSummary) -> some View {
        let quality = summary.dataQuality
        let accent = profileHeroAccent(summary.status)
        let score = summary.isBuilding ? quality.score : summary.growthScore
        let scoreTitle = summary.isBuilding ? String(localized: "档案依据") : String(localized: "成长指数")

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label(summary.status.title, systemImage: profileHeroSymbol(summary.status))
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.12), in: Capsule())

                Spacer(minLength: 8)

                Menu {
                    Button("最近 7 天") { viewModel.selectedRange = .sevenDays }
                    Button("最近 30 天") { viewModel.selectedRange = .thirtyDays }
                    Button("最近 90 天") { viewModel.selectedRange = .ninetyDays }
                } label: {
                    HStack(spacing: 5) {
                        Text(summary.range.title)
                        Image(systemName: "chevron.down")
                            .font(.appSystem(size: 10, weight: .black))
                    }
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("档案范围，\(summary.range.title)")
                .accessibilityIdentifier("healthProfile.rangeMenu")
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("长期健康画像")
                        .font(.appSystem(size: 25, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(summary.headline)
                        .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                profileScoreRing(score: score, title: scoreTitle, accent: accent)
            }

            Divider().overlay(accent.opacity(0.14))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    heroFact(title: "可信度", value: quality.confidence.title)
                    heroDivider
                    heroFact(title: "数据覆盖", value: "\(quality.availableModules)/\(quality.totalModules)")
                    heroDivider
                    heroFact(title: "观察时间", value: "\(summary.range.dayCount) 天")
                }

                VStack(spacing: 12) {
                    heroFact(title: "可信度", value: quality.confidence.title)
                    heroFact(title: "数据覆盖", value: "\(quality.availableModules)/\(quality.totalModules)")
                    heroFact(title: "观察时间", value: "\(summary.range.dayCount) 天")
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingProfileAI = true
                } label: {
                    Label("AI 解读档案", systemImage: "sparkles")
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("healthProfile.aiInsight")

                Button {
                    viewModel.load(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.appSystem(size: 15, weight: .black))
                        .foregroundColor(Color(hex: "455366"))
                        .frame(width: 50, height: 50)
                        .background(Theme.Colors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("重新同步健康档案")
                .accessibilityIdentifier("healthProfile.refresh")
            }
        }
        .padding(adaptiveLayout.usesExpandedLayout ? 28 : 20)
        .background(
            LinearGradient(
                colors: [profileHeroBackground(summary), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(accent.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("healthProfile.overview")
    }

    private func profileScoreRing(score: Int, title: String, accent: Color) -> some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(title)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(score)")
    }

    private func heroFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var heroDivider: some View {
        Divider()
            .frame(height: 30)
            .overlay(Theme.Colors.surfaceBorder)
    }

    private func profileHeroAccent(_ status: HealthProfileStatus) -> Color {
        switch status {
        case .building: return Color(hex: "D89524")
        case .growing: return Color(hex: "27A879")
        case .stable: return Color(hex: "3478C9")
        case .needsRepair: return Color(hex: "DE6A55")
        case .volatile: return Color(hex: "7A67C7")
        }
    }

    private func profileHeroBackground(_ summary: HealthProfileSummary?) -> Color {
        guard let summary else { return Color(hex: "EAF1F6") }
        switch summary.status {
        case .building: return Color(hex: "FDF2D9")
        case .growing: return Color(hex: "E2F7EF")
        case .stable: return Color(hex: "E7F1FD")
        case .needsRepair: return Color(hex: "FDECE7")
        case .volatile: return Color(hex: "EFEAFC")
        }
    }

    private func profileHeroSymbol(_ status: HealthProfileStatus) -> String {
        switch status {
        case .building: return "hourglass"
        case .growing: return "leaf.fill"
        case .stable: return "waveform.path.ecg"
        case .needsRepair: return "bandage.fill"
        case .volatile: return "waveform.path"
        }
    }

    private func shouldShowSelfAssessment(_ summary: HealthProfileSummary) -> Bool {
        let state = summary.dataCompleteness.first { $0.title == "主观状态" }?.state
        if state == .insufficient || state == nil { return true }

        guard let latest = SelfObservationStore.shared.allRecords()
            .filter(\.isHealthProfileAssessment)
            .max(by: { $0.recordedAt < $1.recordedAt }) else {
            return true
        }
        let latestDay = Calendar.current.startOfDay(for: latest.recordedAt)
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: latestDay, to: today).day ?? 0 >= 7
    }

    private func selfAssessmentQuestions(_ summary: HealthProfileSummary) -> [HealthProfileSelfAssessmentPanel.Question] {
        var questions: [HealthProfileSelfAssessmentPanel.Question] = [.selfRating]
        let incompleteTitles = summary.dataCompleteness
            .filter { $0.state == .insufficient || $0.state == .unauthorized }
            .map(\.title)

        if incompleteTitles.contains(where: { $0.contains("睡眠") }) {
            questions.append(.sleepQuality)
        }
        if incompleteTitles.contains(where: { $0.contains("压力") || $0.contains("心率") }) {
            questions.append(.stressLoad)
        }
        if incompleteTitles.contains(where: { $0.contains("活动") }) {
            questions.append(.energy)
        }

        for fallback in [
            HealthProfileSelfAssessmentPanel.Question.energy,
            .stressLoad,
            .sleepQuality
        ] where questions.count < 3 && !questions.contains(fallback) {
            questions.append(fallback)
        }
        return Array(questions.prefix(3))
    }

    private func selfAssessmentPanel(_ summary: HealthProfileSummary) -> some View {
        HealthProfileSelfAssessmentPanel(
            title: "补充档案体感",
            subtitle: "回答当前最能补全档案依据的 3 项；不生成独立分数或连续打卡。",
            selectedDate: assessmentDate,
            questions: selfAssessmentQuestions(summary)
        ) {
            viewModel.load(forceRefresh: true)
        }
        .frame(maxWidth: adaptiveLayout.usesExpandedLayout ? 720 : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildingStateCard(_ summary: HealthProfileSummary) -> some View {
        let quality = summary.dataQuality
        let needsAuthorization = !quality.unauthorizedModules.isEmpty
        let coreTitles = Set(["睡眠", "心率与 HRV", "活动"])
        let hasNoCoreSamples = summary.dataCompleteness
            .filter { coreTitles.contains($0.title) }
            .allSatisfy { $0.sampleCount == 0 }
        let shouldOfferAuthorization = needsAuthorization || hasNoCoreSamples

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("继续建立长期档案", subtitle: quality.summary)

            Label(
                needsAuthorization
                    ? "更新缺少的数据权限后，档案会自动重新判断。"
                    : (hasNoCoreSamples
                        ? "暂未读到睡眠、心率或活动样本，可以检查健康权限后重新同步。"
                        : "当前数据可以继续积累；也可以补充一次体感，让建立期结论更贴近你。"),
                systemImage: shouldOfferAuthorization ? "lock.open.fill" : "clock.arrow.circlepath"
            )
            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    if shouldOfferAuthorization {
                        authorizationButton(
                            title: needsAuthorization ? "更新健康权限" : "检查健康权限",
                            fillsWidth: false
                        )
                    }
                    if !shouldOfferAuthorization {
                        refreshProfileButton(fillsWidth: false)
                    }
                    if onRecordToday != nil {
                        recordTodayButton(title: "记录日常状态", fillsWidth: false)
                    }
                }

                VStack(spacing: 10) {
                    if shouldOfferAuthorization {
                        authorizationButton(
                            title: needsAuthorization ? "更新健康权限" : "检查健康权限",
                            fillsWidth: true
                        )
                    }
                    if !shouldOfferAuthorization {
                        refreshProfileButton(fillsWidth: true)
                    }
                    if onRecordToday != nil {
                        recordTodayButton(title: "记录日常状态", fillsWidth: true)
                    }
                }
            }
        }
        .modifier(ProfileSectionCard(tint: Color(hex: "F3A53B")))
    }

    private func focusSection(_ presentation: HealthProfilePagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("本周先照顾一件事", subtitle: "档案会把最值得优先处理的变化放在这里。")

            if let primary = presentation.primaryFocus {
                let tint = focusTint(primary.emphasis)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        iconBubble(symbol: focusSymbol(primary), tint: tint, size: 44)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(primary.title)
                                    .font(.appSystem(size: 19, weight: .black, design: .rounded))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                BBStatusBadge(title: primary.badgeText, tint: tint)
                            }
                            Text(primary.reason)
                                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Label {
                        Text(primary.detail)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(tint)

                    Text(primary.evidenceText)
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(16)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("healthProfile.primaryFocus")

                if !presentation.supportingFocus.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(presentation.supportingFocus.enumerated()), id: \.element.id) { index, item in
                            supportingFocusRow(item)
                            if index < presentation.supportingFocus.count - 1 {
                                Divider().overlay(Theme.Colors.surfaceBorder)
                            }
                        }
                    }
                }
            } else {
                inlineEmptyState("暂时没有特别需要处理的重点，维持已有节奏就好。")
            }
        }
        .modifier(ProfileSectionCard(tint: Color(hex: "4CA6A8")))
    }

    private func supportingFocusRow(_ item: HealthHubFocusItem) -> some View {
        let tint = focusTint(item.emphasis)
        return HStack(spacing: 12) {
            Image(systemName: focusSymbol(item))
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(item.detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(item.badgeText)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    private func dimensionsSection(_ dimensions: [HealthProfileDimension]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("健康维度", subtitle: "先扫一眼整体分布，点开单项再看判断依据。")

            if dimensions.isEmpty {
                inlineEmptyState("暂时没有足够数据生成健康维度。")
            } else {
                LazyVGrid(columns: dimensionColumns, spacing: 10) {
                    ForEach(dimensions) { dimension in
                        dimensionTile(dimension)
                    }
                }

                if let expanded = dimensions.first(where: { expandedDimensionIDs.contains($0.id) }) {
                    let tint = trendTint(expanded.trend)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "quote.opening")
                                .foregroundColor(tint)
                            Text(expanded.title)
                                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        Text(expanded.detail)
                            .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("healthProfile.dimensionDetail.\(expanded.kind.rawValue)")
                }
            }
        }
        .modifier(ProfileSectionCard(tint: Color(hex: "6B83E8")))
    }

    private var dimensionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 10)]
        }
        let count = adaptiveLayout.usesExpandedLayout ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private func dimensionTile(_ dimension: HealthProfileDimension) -> some View {
        let tint = trendTint(dimension.trend)
        let isExpanded = expandedDimensionIDs.contains(dimension.id)

        return Button {
            if isExpanded {
                expandedDimensionIDs.removeAll()
            } else {
                expandedDimensionIDs = [dimension.id]
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: dimension.kind.symbol)
                        .font(.appSystem(size: 16, weight: .black))
                        .foregroundColor(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer(minLength: 4)
                    Text(dimension.score.map(String.init) ?? "--")
                        .font(.appSystem(size: 23, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Text(dimension.title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(dimension.trend.title)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(
                isExpanded ? tint.opacity(0.10) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isExpanded ? tint.opacity(0.32) : Theme.Colors.surfaceBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dimension.title)，\(dimension.statusText)，\(dimension.score.map { "\($0) 分" } ?? "暂无分数")")
        .accessibilityHint(isExpanded ? "轻点收起判断依据" : "轻点查看判断依据")
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
        .accessibilityIdentifier("healthProfile.dimension.\(dimension.kind.rawValue)")
    }

    private func focusTint(_ emphasis: HealthHubFocusItem.Emphasis) -> Color {
        switch emphasis {
        case .urgent: return Color(hex: "E86F54")
        case .observe: return Color(hex: "4E82D8")
        case .maintain: return Theme.Colors.mintGreen
        case .building: return Color(hex: "D89524")
        }
    }

    private func focusSymbol(_ item: HealthHubFocusItem) -> String {
        switch item.kind {
        case .recommendation: return "target"
        case .risk: return "exclamationmark.triangle.fill"
        case .change: return "arrow.triangle.2.circlepath"
        case .building: return "hourglass"
        }
    }

    private enum InsightsTab: String, CaseIterable {
        case changes
        case portrait

        var title: String {
            switch self {
            case .changes: return "近期变化"
            case .portrait: return "长期画像"
            }
        }

        var symbol: String {
            switch self {
            case .changes: return "arrow.triangle.2.circlepath"
            case .portrait: return "person.crop.circle.badge.checkmark"
            }
        }
    }

    private func insightsSection(
        changes: [HealthProfileChange],
        tags: [HealthProfileTag],
        milestones: [HealthProfileMilestone]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(InsightsTab.allCases, id: \.self) { tab in
                    let isActive = insightsTab == tab
                    Button {
                        guard !isActive else { return }
                        insightsTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.symbol)
                                .font(.appSystem(size: 12, weight: .black))
                            Text(tab.title)
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        }
                        .foregroundColor(isActive ? .white : Color(hex: "50627F"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isActive {
                                Capsule().fill(Color(hex: "50627F"))
                            } else {
                                Capsule().fill(Theme.Colors.secondaryBackground)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }

            Group {
                switch insightsTab {
                case .changes:
                    changesContent(changes)
                case .portrait:
                    portraitContent(tags: tags, milestones: milestones)
                }
            }
        }
        .modifier(ProfileSectionCard(tint: Color(hex: "94A3C3")))
    }

    private func changesContent(_ changes: [HealthProfileChange]) -> some View {
        Group {
            if changes.isEmpty {
                inlineEmptyState("最近整体比较稳定，继续积累数据后会出现更细的变化判断。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(changes.prefix(5).enumerated()), id: \.element.id) { index, change in
                        profileRow(
                            symbol: symbol(for: change.kind),
                            title: change.title,
                            detail: change.detail,
                            badge: change.kind == .positive ? "改善" : (change.kind == .risk ? "留意" : "稳定"),
                            tint: tint(for: change.kind)
                        )
                        if index < min(changes.count, 5) - 1 {
                            Divider().overlay(Theme.Colors.surfaceBorder)
                        }
                    }
                }
            }
        }
    }

    private func portraitContent(tags: [HealthProfileTag], milestones: [HealthProfileMilestone]) -> some View {
        Group {
            if tags.isEmpty && milestones.isEmpty {
                inlineEmptyState("目前样本还不够形成长期画像，先继续观察。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tags.prefix(4).enumerated()), id: \.element.id) { index, tag in
                        profileRow(
                            symbol: "tag.fill",
                            title: tag.title,
                            detail: tagEvidenceText(tag),
                            badge: tag.confidence.title,
                            tint: tag.confidence == .low ? Color(hex: "94A3C3") : Color(hex: "6B83E8")
                        )
                        if index < min(tags.count, 4) - 1 || !milestones.isEmpty {
                            Divider().overlay(Theme.Colors.surfaceBorder)
                        }
                    }

                    ForEach(Array(milestones.prefix(4).enumerated()), id: \.element.id) { index, milestone in
                        profileRow(
                            symbol: "flag.checkered",
                            title: milestone.title,
                            detail: milestone.detail,
                            badge: shortDateText(milestone.achievedAt),
                            tint: Color(hex: "F3A53B")
                        )
                        if index < min(milestones.count, 4) - 1 {
                            Divider().overlay(Theme.Colors.surfaceBorder)
                        }
                    }
                }
            }
        }
    }

    private func dataEvidenceSection(_ summary: HealthProfileSummary) -> some View {
        let quality = summary.dataQuality

        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("档案依据", subtitle: "查看数据覆盖、授权状态和样本不足原因。")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(quality.score)")
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(scoreTint(quality.score))
                Text("/ 100 · \(quality.confidence.title)")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(quality.summary)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $isDataEvidenceExpanded) {
                VStack(spacing: 0) {
                    ForEach(Array(summary.dataCompleteness.enumerated()), id: \.element.id) { index, item in
                        evidenceRow(item)
                        if index < summary.dataCompleteness.count - 1 {
                            Divider().overlay(Theme.Colors.surfaceBorder)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(isDataEvidenceExpanded ? "收起数据来源" : "查看全部数据来源")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "50627F"))
            }
            .tint(Color(hex: "50627F"))
        }
        .modifier(ProfileSectionCard(tint: Color(hex: "94A3C3")))
    }

    private func emptyStateCard(title: String, detail: String, primaryTitle: String, secondaryTitle: String, tertiaryTitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            iconBubble(symbol: "heart.text.square.fill", tint: Theme.Colors.mintGreen, size: 54)
            Text(title)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "102B56"))
            Text(detail)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    authorizationButton(title: primaryTitle, fillsWidth: false)
                    if onRecordToday != nil {
                        recordTodayButton(title: secondaryTitle, fillsWidth: false)
                    }
                }
                VStack(spacing: 10) {
                    authorizationButton(title: primaryTitle, fillsWidth: true)
                    if onRecordToday != nil {
                        recordTodayButton(title: secondaryTitle, fillsWidth: true)
                    }
                }
            }
            if let tertiaryTitle {
                Button {
                    dismiss()
                } label: {
                    Label(tertiaryTitle, systemImage: "chart.xyaxis.line")
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "6B83E8"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .bbTintedChip(tint: Color(hex: "6B83E8"), in: Capsule(), tintOpacity: 0.07)
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(ProfileSectionCard(tint: Theme.Colors.mintGreen))
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在整理你的长期健康档案")
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .modifier(ProfileSectionCard(tint: Theme.Colors.mintGreen))
    }

    private func authorizationButton(title: String, fillsWidth: Bool) -> some View {
        Button {
            viewModel.requestHealthAuthorization()
        } label: {
            Label(title, systemImage: "heart.fill")
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .frame(minWidth: fillsWidth ? 0 : 132, maxWidth: fillsWidth ? .infinity : nil)
                .padding(.vertical, 12)
                .bbTintedPrimaryButton(tint: Theme.Colors.mintGreen, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAuthorizing)
    }

    private func refreshProfileButton(fillsWidth: Bool) -> some View {
        Button {
            viewModel.load(forceRefresh: true)
        } label: {
            Label("重新同步", systemImage: "arrow.clockwise")
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "50627F"))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .frame(minWidth: fillsWidth ? 0 : 108, maxWidth: fillsWidth ? .infinity : nil)
                .padding(.vertical, 12)
                .bbTintedChip(tint: Color(hex: "50627F"), in: Capsule(), tintOpacity: 0.07)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }

    private func recordTodayButton(title: String, fillsWidth: Bool) -> some View {
        Button {
            dismiss()
            onRecordToday?()
        } label: {
            Label(title, systemImage: "square.and.pencil")
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.mintGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .frame(minWidth: fillsWidth ? 0 : 132, maxWidth: fillsWidth ? .infinity : nil)
                .padding(.vertical, 12)
                .bbTintedChip(tint: Theme.Colors.mintGreen, in: Capsule(), tintOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HealthProfileView()
    }
}
