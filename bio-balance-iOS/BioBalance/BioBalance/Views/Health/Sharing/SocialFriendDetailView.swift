/// 好友详情页：参考图的详情设计。
/// 头像身份头部 + 「睡眠 / 步速」分段 + 大号摘要卡与指标宫格 + 对方分享的内容列表；
/// 数据边界遵循 ICLOUD_DATA_ARCHITECTURE：只展示对方主动共享的最近 7 天只读摘要。

import Charts
import SwiftUI

struct SocialFriendDetailPresentation: Equatable {
    let hasLocation: Bool
    let actionCount: Int
    let countdownCount: Int
    let todoCount: Int

    var sharedCategoryCount: Int {
        [hasLocation, actionCount > 0, countdownCount > 0, todoCount > 0]
            .filter { $0 }
            .count
    }

    var hasSharedContent: Bool { sharedCategoryCount > 0 }

    var sharedSummary: String {
        hasSharedContent
            ? String(localized: "已分享 \(sharedCategoryCount) 类内容")
            : String(localized: "暂未分享其他内容")
    }
}

/// 详情页「今日 / 7 天 / 30 天」时间范围分段（设计稿 4:2）。
/// 共享摘要合同只携带最近 7 天，今日与 30 天仅在有数据时可选，否则引导回 7 天。
private enum FriendTrendRange: String, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return String(localized: "今日")
        case .sevenDays: return String(localized: "7天")
        case .thirtyDays: return String(localized: "30天")
        }
    }
}

/// 详情页「睡眠 / 步速」指标分段，对应参考图的时间范围切换。
private enum FriendTrendMetric: String, CaseIterable, Identifiable {
    case sleep
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return String(localized: "睡眠")
        case .walking: return String(localized: "步速")
        }
    }
}

struct SocialFriendDetailView: View {
    let friend: FriendHealthProfile
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmingRemoval = false
    @State private var showingCollaborativeTodo = false
    @State private var showingShareSettings = false
    @State private var showingStressDetail = false
    @State private var selectedTrend: FriendTrendMetric = .sleep
    @State private var selectedRange: FriendTrendRange = .sevenDays
    @State private var encouragementSent = false

    private let ink = Color(hex: "12141A")
    private let secondaryInk = Color(hex: "6E7887")
    private let trackInk = Color(hex: "F2F5F7")
    private let accent = Theme.Colors.mintGreen
    private let sleepTint = Color(hex: "6C7CE0")
    private let sleepBarTint = Color(hex: "D1C9FF")
    private let walkTint = Color(hex: "3FBF9F")
    private let liveTint = Color(hex: "29AD73")
    private let locationTint = Theme.Colors.accentOrange
    private let todoTint = Theme.Colors.accentBlue
    private let divider = Color(uiColor: .separator).opacity(0.14)

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            AdaptivePageScrollView(topPadding: 12, bottomPadding: 52) {
                VStack(alignment: .leading, spacing: 20) {
                    identityCard
                    rangeSegment
                    trendCard
                    quickMetricGrid
                    cheerSection
                    sharedContentSection
                    lastUpdatedFooter
                    privacyNote
                }
            }
        }
        .navigationTitle("好友详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("分享设置", systemImage: "square.and.arrow.up.2") {
                        showingShareSettings = true
                    }
                    Button("移除好友共享", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                        confirmingRemoval = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("更多好友操作")
            }
        }
        .sheet(isPresented: $showingShareSettings) {
            NavigationStack {
                SocialShareSettingsView(friendName: friend.name)
            }
                .adaptiveSheetChrome(style: .page, dragIndicator: .visible)
        }
        .navigationDestination(isPresented: $showingStressDetail) {
            SocialStressDetailView(friend: friend)
                .toolbar(.hidden, for: .tabBar)
        }
        .sheet(isPresented: $showingCollaborativeTodo) {
            NavigationStack {
                CollaborativeTodoListView(
                    ownerUserRecordName: friend.ownerUserRecordName,
                    ownerDisplayName: friend.name
                )
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .alert("停止这位好友的共享？", isPresented: $confirmingRemoval) {
            Button("取消", role: .cancel) { }
            Button("移除", role: .destructive) {
                onRemove()
                dismiss()
            }
        } message: {
            Text("移除后，你将立即看不到这位好友的共享摘要。")
        }
    }

    // MARK: - 身份卡

    /// 设计稿 (4:2) 的白色身份卡：头像 + 名字 + 「3分钟前更新 · 正在共享」。
    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        avatar
                        identityCopy
                    }
                } else {
                    HStack(spacing: 16) {
                        avatar
                        identityCopy
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(String(friend.name.prefix(1)))
                .font(.appSystem(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: "5B9BD5"))
                .frame(width: 64, height: 64)
                .background(Color(hex: "B8DEFF"), in: Circle())

            Circle()
                .fill(friend.storyStatusColor)
                .frame(width: 15, height: 15)
                .overlay { Circle().stroke(.white, lineWidth: 3) }
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    private var identityCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(friend.name)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)

            // 设计稿的「3分钟前更新 · 正在共享」状态行。
            HStack(spacing: 5) {
                Text(String(localized: "\(relativeUpdatedText)更新 · \(sharingStateText)"))
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(friend.isStale ? Theme.Colors.accentOrange : liveTint)
                    .lineLimit(1)
            }

            if let handle = friend.publicProfile?.handle, !handle.isEmpty {
                Text("@\(handle)")
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sharingStateText: String {
        friend.isStale ? String(localized: "缓存摘要") : String(localized: "正在共享")
    }

    private var staleBanner: some View {
        Label(
            "当前显示最近一次缓存的摘要，可能不是最新状态。",
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        )
        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(Theme.Colors.accentOrange)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Theme.Colors.accentOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 分段与摘要大卡

    /// 设计稿的「今日 / 7天 / 30天」胶囊分段；摘要只有 7 天，未覆盖范围自动回退。
    private var rangeSegment: some View {
        HStack(spacing: 8) {
            ForEach(FriendTrendRange.allCases) { range in
                let isEnabled = range == .sevenDays
                Button {
                    guard isEnabled else { return }
                    selectedRange = range
                } label: {
                    Text(range.title)
                        .font(.appSystem(size: 12, weight: isEnabled && selectedRange == range ? .bold : .medium, design: .rounded))
                        .foregroundStyle(
                            selectedRange == range
                                ? ink
                                : isEnabled ? secondaryInk : secondaryInk.opacity(0.45)
                        )
                        .padding(.horizontal, 14)
                        .frame(minWidth: 52, minHeight: 30)
                        .background {
                            Capsule().fill(
                                selectedRange == range
                                    ? Color.white
                                    : isEnabled ? trackInk : trackInk.opacity(0.6)
                            )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityAddTraits(selectedRange == range ? [.isSelected] : [])
                .accessibilityHint(isEnabled ? "" : String(localized: "共享摘要只包含最近 7 天"))
            }
            Spacer(minLength: 0)
        }
    }

    /// 设计稿的睡眠大卡：指标名 +「昨晚」标注 + 大号数值 + 时段行 + 底部进度条。
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(selectedTrend.title)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer(minLength: 8)
                // 设计稿的「昨晚」标注（摘要合同是 7 天均值，标注跟随实际口径）。
                Text(selectedTrend == .sleep ? String(localized: "近 7 天") : String(localized: "近 7 天"))
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
            }

            if selectedTrend == .sleep {
                Text(selectedTrendValue)
                    .font(.appSystem(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(trendSubtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.secondaryBackground)
                        Capsule()
                            .fill(sleepBarTint)
                            .frame(width: sleepProgressWidth(proxy.size.width))
                    }
                }
                .frame(height: 8)
                .accessibilityLabel("平均睡眠占 8 小时目标的比例")

                if sleepPoints.isEmpty {
                    Text("最近没有可展示的每日睡眠记录。")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryInk)
                } else {
                    Chart(sleepPoints) { day in
                        if let minutes = day.sleepMinutes {
                            BarMark(x: .value("日期", day.date, unit: .day), y: .value("分钟", minutes))
                                .foregroundStyle(sleepBarTint)
                                .cornerRadius(3)
                        }
                    }
                    .friendTrendChartStyle(compact: true)
                    .accessibilityLabel("近 7 天每日睡眠分钟柱状图")
                }
            } else if walkingPoints.isEmpty {
                emptyChart("最近 7 天步速样本不足，这很常见。", symbol: "figure.walk")
            } else {
                Chart(walkingPoints) { day in
                    if let speed = day.walkingSpeedMps {
                        LineMark(x: .value("日期", day.date), y: .value("m/s", speed))
                            .foregroundStyle(walkTint)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("日期", day.date), y: .value("m/s", speed))
                            .foregroundStyle(walkTint)
                    }
                }
                .friendTrendChartStyle(compact: false)
                .accessibilityLabel("近 7 天步速折线图")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 睡眠大卡的时段行：设计稿的「23:12 – 07:02 · 深睡 1小时52分」位置，
    /// 摘要合同没有入睡/醒来时间，用有效天数与均值差异描述代替。
    private var trendSubtitle: String {
        let highlights = friend.snapshot.highlights
        guard highlights.validSleepDays > 0 else {
            return String(localized: "最近 7 天暂无有效睡眠记录")
        }
        return String(localized: "\(highlights.validSleepDays)/7 晚有记录")
    }

    private func sleepProgressWidth(_ available: CGFloat) -> CGFloat {
        let minutes = friend.snapshot.highlights.averageSleepMinutes ?? 0
        let ratio = min(max(Double(minutes) / 480, 0.08), 1)
        return available * ratio
    }

    // MARK: - 关心一下

    /// 设计稿的「关心一下」卡：展示一句鼓励语并提供快捷发送。
    private var cheerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关心一下")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(ink)

            Text(encouragementSent ? String(localized: "鼓励已送给 \(friend.name) 🌙") : cheerMessage)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                encouragementSent = true
            } label: {
                Text(encouragementSent ? String(localized: "已发送") : String(localized: "发送鼓励"))
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 41)
                    .background(
                        Capsule().fill(
                            encouragementSent ? Color(hex: "E5F7F0") : Color(hex: "C7F2DB")
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(encouragementSent)
            .accessibilityHint(encouragementSent ? "" : String(localized: "给好友发送一句鼓励"))

            Group {
                Button {
                    showingStressDetail = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.appSystem(size: 13, weight: .bold))
                        Text("查看压力详情")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 11, weight: .bold))
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 41)
                    .background(trackInk, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("暂无好友压力数据")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// 依据对方最新摘要生成鼓励语。
    private var cheerMessage: String {
        if let minutes = friend.snapshot.highlights.averageSleepMinutes, minutes >= 420 {
            return String(localized: "“最近睡得很充足，继续保持呀 🌙”")
        }
        if friend.snapshot.highlights.validWalkingSpeedDays >= 5 {
            return String(localized: "“这周节奏很稳，为你点赞 👏”")
        }
        return String(localized: "“今天睡得很好，继续保持呀 🌙”")
    }

    private func emptyChart(_ text: String, symbol: String) -> some View {
        ContentUnavailableView {
            Label("暂无趋势", systemImage: symbol)
        } description: {
            Text(text)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // MARK: - 快捷指标双小卡

    /// 设计稿 (4:2) 睡眠大卡下方的「步数 / 压力」双小卡；
    /// 摘要合同没有步数与压力，这里换成合同内的「有效睡眠 / 有效步速」双卡，
    /// 保持设计稿的一行两卡节奏。
    private var quickMetricGrid: some View {
        HStack(spacing: 10) {
            quickMetricCard(
                tint: Color(hex: "C7F2DB"),
                title: String(localized: "有效睡眠"),
                value: String(localized: "\(friend.snapshot.highlights.validSleepDays)/7 晚")
            )
            quickMetricCard(
                tint: Color(hex: "B8DEFF"),
                title: String(localized: "有效步速"),
                value: String(localized: "\(friend.snapshot.highlights.validWalkingSpeedDays)/7 天")
            )
        }
    }

    /// 设计稿小卡的样式：彩色圆点 + 灰色标题 + 大号数值（横向排布，高 65）。
    private func quickMetricCard(tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
                Text(value)
                    .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var sharedContentSection: some View {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("对方分享", detail: detailPresentation.sharedSummary)

            if detailPresentation.hasSharedContent {
                VStack(spacing: 0) {
                    sharedContentRows
                }
                .friendDetailSurface()
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "lock.open")
                        .font(.appSystem(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(uiColor: .secondarySystemFill), in: Circle())
                    Text("除健康摘要外，对方暂未分享其他内容。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .friendDetailSurface()
            }
        }
    }

    @ViewBuilder
    private var sharedContentRows: some View {
        if let location = friend.snapshot.location {
            contentRow(
                symbol: "location.fill",
                tint: locationTint,
                title: "共享位置",
                detail: location.displayText,
                meta: "粗略位置 · \(shortDate(location.capturedAt))"
            )
            sharedDivider(after: .location)
        }

        ForEach(friend.snapshot.sharedActionRecords.prefix(3)) { record in
            contentRow(
                symbol: "figure.walk.motion",
                tint: accent,
                title: record.summaryText,
                detail: record.progressText,
                meta: "行动记录 · \(shortDate(record.date))"
            )
            sharedDivider(after: .action(record.id))
        }

        ForEach(friend.snapshot.sharedCountdownItems.prefix(3)) { item in
            contentRow(
                symbol: "calendar",
                tint: locationTint,
                title: item.title,
                detail: item.note ?? item.relativeText,
                meta: "\(item.relativeText) · \(shortDate(item.targetDate))"
            )
            sharedDivider(after: .countdown(item.id))
        }

        if let todo = friend.snapshot.sharedTodoListSummary, todo.itemCount > 0 {
            Button {
                showingCollaborativeTodo = true
            } label: {
                contentRow(
                    symbol: "checklist",
                    tint: todoTint,
                    title: todo.title,
                    detail: todo.summaryText,
                    meta: todoLastEditorText ?? "共享待办 · 只读"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开共享待办清单")
        }
    }

    private func contentRow(symbol: String, tint: Color, title: String, detail: String, meta: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private enum SharedRowID: Equatable {
        case location
        case action(TimeInterval)
        case countdown(String)
    }

    @ViewBuilder
    private func sharedDivider(after row: SharedRowID) -> some View {
        if hasSharedRow(after: row) {
            Divider().overlay(divider).padding(.leading, 68)
        }
    }

    private func hasSharedRow(after row: SharedRowID) -> Bool {
        switch row {
        case .location:
            return !friend.snapshot.sharedActionRecords.isEmpty
                || !friend.snapshot.sharedCountdownItems.isEmpty
                || (friend.snapshot.sharedTodoListSummary?.itemCount ?? 0) > 0
        case .action(let id):
            let visibleActions = Array(friend.snapshot.sharedActionRecords.prefix(3))
            let isLastAction = visibleActions.last?.id == id
            return !isLastAction
                || !friend.snapshot.sharedCountdownItems.isEmpty
                || (friend.snapshot.sharedTodoListSummary?.itemCount ?? 0) > 0
        case .countdown(let id):
            let visibleCountdowns = Array(friend.snapshot.sharedCountdownItems.prefix(3))
            let isLastCountdown = visibleCountdowns.last?.id == id
            return !isLastCountdown || (friend.snapshot.sharedTodoListSummary?.itemCount ?? 0) > 0
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 页脚

    /// 设计稿底部的「最后更新」行。
    private var lastUpdatedFooter: some View {
        Text("最后更新：\(relativeUpdatedText)")
            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var privacyNote: some View {
        Label(
            "这里只展示对方主动共享的内容；健康摘要、位置和共同事项均为只读。",
            systemImage: "lock.shield.fill"
        )
        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 派生数据

    private var detailPresentation: SocialFriendDetailPresentation {
        .init(
            hasLocation: friend.snapshot.location != nil,
            actionCount: friend.snapshot.sharedActionRecords.count,
            countdownCount: friend.snapshot.sharedCountdownItems.count,
            todoCount: friend.snapshot.sharedTodoListSummary?.itemCount ?? 0
        )
    }

    private var sleepPoints: [SharedHealthDay] {
        friend.snapshot.days.filter { $0.sleepMinutes != nil }
    }

    private var walkingPoints: [SharedHealthDay] {
        friend.snapshot.days.filter { $0.walkingSpeedMps != nil }
    }

    private var trendTint: Color {
        selectedTrend == .sleep ? sleepTint : walkTint
    }

    private var selectedTrendValue: String {
        selectedTrend == .sleep ? friend.sleepText : friend.walkingText
    }

    private var relativeUpdatedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: friend.lastUpdated, relativeTo: Date())
    }

    private var averageSleepText: String {
        guard let minutes = friend.snapshot.highlights.averageSleepMinutes else {
            return friend.sleepText
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) 小时") : String(localized: "\(hours) 小时 \(rest) 分")
    }

    private var averageWalkingText: String {
        guard let speed = friend.snapshot.highlights.averageWalkingSpeedMps else {
            return friend.walkingText
        }
        return String(format: "%.2f m/s", speed)
    }

    private var todoLastEditorText: String? {
        guard let todo = friend.snapshot.sharedTodoListSummary,
              let lastEditor = todo.lastEditedByUserRecordName,
              !lastEditor.isEmpty else { return nil }
        if lastEditor == friend.ownerUserRecordName || lastEditor == friend.publicProfile?.recordName {
            return String(localized: "最近编辑：\(friend.name)")
        }
        return nil
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    /// 压力详情缺省兜底（provider 未提供时几乎不会走到）。
    private var emptyStressSnapshot: SocialShareSnapshot {
        SocialShareSnapshot(
            title: String(localized: "等待同步"),
            subtitle: "",
            shareSummary: "",
            stressTitle: String(localized: "身体压力"),
            stressValueText: String(localized: "等待同步"),
            hrvValueText: String(localized: "等待同步"),
            bpmValueText: String(localized: "等待同步"),
            sleepValueText: "",
            moodTitle: "",
            moodIntensityText: "",
            trendSummary: "",
            adviceText: "",
            lastUpdatedText: "",
            shareText: "",
            assessment: StressPresentation.unavailableAssessment(reason: .noDailySamples)
        )
    }
}

private extension View {
    func friendDetailSurface() -> some View {
        background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 1)
            }
    }

    func friendTrendChartStyle(compact: Bool) -> some View {
        frame(height: compact ? 120 : 170)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
    }
}
