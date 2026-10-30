import SwiftUI
#if os(watchOS)
import WatchKit
#endif

@Observable
private final class WatchHomePresentationState {
    var activeSheet: WatchHomeSheet?
    var showsSwimmingWorkout = false
}

struct WatchHomeView: View {
    var hrManager: WatchHeartRateManager
    var receiver: WatchConnectivityReceiver
    var swimmingWorkoutManager: SwimmingWorkoutManager
    @State private var presentationState = WatchHomePresentationState()

    private var snapshot: WatchRealtimeHealth? { receiver.latest }

    private func presentSwimmingIfNeeded(_ phase: SwimmingWorkoutPhase) {
        switch phase {
        case .preparing, .running, .paused, .ending:
            presentationState.showsSwimmingWorkout = true
        case .idle, .finished, .failed:
            break
        }
    }

    var body: some View {
        ZStack {
            WatchHomeBackground()
                .ignoresSafeArea()

            if let snapshot {
                WatchFocusHomePage(
                    hrManager: hrManager,
                    receiver: receiver,
                    snapshot: snapshot,
                    syncText: syncText,
                    openRecovery: { presentationState.activeSheet = .hrvInfo },
                    openPressure: { presentationState.activeSheet = .pressure },
                    openSleep: { presentationState.activeSheet = .sleep },
                    openMotivation: { presentationState.activeSheet = .motivation },
                    openAI: { presentationState.activeSheet = .ai },
                    openMore: { presentationState.activeSheet = .more },
                    openSwimming: { presentationState.showsSwimmingWorkout = true }
                )
            } else {
                WatchWaitingHomePage(
                    receiver: receiver,
                    openAI: { presentationState.activeSheet = .ai },
                    openSettings: { presentationState.activeSheet = .settings },
                    openSwimming: { presentationState.showsSwimmingWorkout = true }
                )
            }
        }
        .navigationDestination(isPresented: $presentationState.showsSwimmingWorkout) {
            SwimmingWorkoutFlowView(manager: swimmingWorkoutManager)
        }
        .task {
            presentSwimmingIfNeeded(swimmingWorkoutManager.phase)
        }
        .onChange(of: swimmingWorkoutManager.phase) { _, phase in
            presentSwimmingIfNeeded(phase)
        }
        .safeAreaInset(edge: .bottom) {
            if hrManager.authorizationState == .needsAuthorization
                || hrManager.authorizationState == .requesting {
                Button {
                    hrManager.requestAuthorization()
                } label: {
                    HStack(spacing: 6) {
                        if hrManager.authorizationState == .requesting {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "heart.fill")
                        }
                        Text(hrManager.authorizationState == .requesting ? "正在授权" : "开启手表心率")
                            .font(.watchAppSystem(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.mint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.mint.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(hrManager.authorizationState == .requesting)
                .padding(.horizontal, 8)
            }
        }
        .sheet(item: $presentationState.activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .settings:
                    ComplicationGuideView(receiver: receiver, showsCloseButton: true)
                case .hrvInfo:
                    if let snapshot {
                        WatchRecoveryInfoSheet(snapshot: snapshot)
                    }
                case .pressure:
                    if let snapshot {
                        WatchTodayPressureView(snapshot: snapshot)
                    }
                case .sleep:
                    if let snapshot {
                        WatchNightSleepView(snapshot: snapshot)
                    }
                case .motivation:
                    if let snapshot {
                        WatchMotivationView(snapshot: snapshot)
                    }
                case .ai:
                    WatchAIView(receiver: receiver)
                case .more:
                    if let snapshot {
                        WatchFeaturePicker(
                            receiver: receiver,
                            snapshot: snapshot
                        )
                    }
                }
            }
        }
    }

    private var syncText: String {
        if let last = receiver.lastSyncDate {
            return String(localized: "更新于 \(last.formatted(date: .omitted, time: .shortened))")
        }
        return receiver.isReachable ? String(localized: "已连接 iPhone") : String(localized: "等待 iPhone 连接")
    }
}

private struct WatchWaitingHomePage: View {
    var receiver: WatchConnectivityReceiver
    let openAI: () -> Void
    let openSettings: () -> Void
    let openSwimming: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                Spacer(minLength: 2)

                WatchFocusMascot(
                    snapshot: nil,
                    isEnabled: receiver.watchMascotEnabled,
                    message: receiver.watchMascotMessage,
                    themeId: receiver.watchThemeId,
                    customThemeId: receiver.watchCustomThemeId,
                    accessibilityHintText: receiver.watchMascotEnabled
                        ? String(localized: "轻点互动，拖动跟随，长按打开表盘设置")
                        : String(localized: "长按打开表盘设置"),
                    longPressActionName: String(localized: "打开表盘设置"),
                    onLongPress: {
                        #if os(watchOS)
                        WKInterfaceDevice.current().play(.click)
                        #endif
                        openSettings()
                    }
                )
                    .frame(width: min(proxy.size.width * 0.42, 78), height: min(proxy.size.width * 0.42, 78))

                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        if receiver.isSyncing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Circle()
                                .fill(receiver.isReachable ? Color.mint : Color.orange)
                                .frame(width: 6, height: 6)
                        }
                        Text(receiver.isSyncing ? "正在同步" : (receiver.isReachable ? "iPhone 已连接" : "等待 iPhone"))
                            .font(.watchAppSystem(size: 15, weight: .bold, design: .rounded))
                    }
                    Text(receiver.syncErrorMessage?.isEmpty == false ? "暂时无法取得健康数据" : "连接后会显示恢复状态")
                        .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 5) {
                    WatchFocusActionButton(
                        icon: receiver.isAIWorking ? "sparkles" : "waveform",
                        title: receiver.isAIWorking ? String(localized: "整理中") : String(localized: "问 AI"),
                        tint: Color(red: 0.66, green: 0.78, blue: 1.0),
                        showsBadge: receiver.hasUnreadAIAnswer,
                        action: openAI
                    )
                    WatchFocusActionButton(
                        icon: "arrow.clockwise",
                        title: String(localized: "同步"),
                        tint: .mint,
                        action: { receiver.syncNow() }
                    )
                    WatchFocusActionButton(
                        icon: "figure.pool.swim",
                        title: String(localized: "游泳"),
                        tint: Color(red: 0.36, green: 0.91, blue: 0.82),
                        action: openSwimming
                    )
                }
            }
            .padding(.horizontal, 8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// 首页采用单焦点交互：一个陪伴角色、一个当前状态，
/// 其余信息按需逐步展开。
private struct WatchFocusHomePage: View {
    var hrManager: WatchHeartRateManager
    var receiver: WatchConnectivityReceiver
    let snapshot: WatchRealtimeHealth
    let syncText: String
    let openRecovery: () -> Void
    let openPressure: () -> Void
    let openSleep: () -> Void
    let openMotivation: () -> Void
    let openAI: () -> Void
    let openMore: () -> Void
    let openSwimming: () -> Void

    private var state: WatchHomeHeroState {
        WatchHomeStateMapper.makeHeroState(snapshot: snapshot)
    }

    private var statusDetail: String {
        let now = Date()
        let heartRateZone = freshZone(hrManager.heartRateZone, at: now)
        let cyclingPowerZone = freshZone(hrManager.cyclingPowerZone, at: now)

        if let heartRateZone, let cyclingPowerZone {
            return String(localized: "\(hrManager.bpm) bpm · HR Z\(heartRateZone.index) · 功率 Z\(cyclingPowerZone.index)")
        }
        if let heartRateZone {
            return liveZoneText(prefix: "心率 \(hrManager.bpm) · Zone", state: heartRateZone)
        }
        if let cyclingPowerZone {
            return liveZoneText(prefix: "骑行功率 Zone", state: cyclingPowerZone)
        }
        if hrManager.heartRateZone != nil || hrManager.cyclingPowerZone != nil {
            return String(localized: "训练区间信号暂不可用")
        }
        if receiver.isSyncing { return String(localized: "正在同步健康状态") }
        if let error = receiver.syncErrorMessage, !error.isEmpty { return String(localized: "同步遇到问题，点按查看") }
        if snapshot.hrv > 0 { return String(localized: "HRV \(Int(snapshot.hrv.rounded()))ms · \(syncText)") }
        if snapshot.stress_value > 0 { return String(localized: "压力 \(snapshot.stress_value) · \(syncText)") }
        return syncText
    }

    private func freshZone(_ state: WatchLiveWorkoutZoneState?, at date: Date) -> WatchLiveWorkoutZoneState? {
        guard let state else { return nil }
        guard let sampleDate = state.lastSampleDate else { return state }
        return date.timeIntervalSince(sampleDate) <= 20 ? state : nil
    }

    private func liveZoneText(prefix: String, state: WatchLiveWorkoutZoneState) -> String {
        let minutes = max(0, Int(state.duration / 60))
        let durationText = minutes > 0 ? String(localized: " · \(minutes) 分钟") : ""
        return "\(prefix) \(state.index)\(durationText)"
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 7) {
                Spacer(minLength: 2)

                WatchFocusMascot(
                    snapshot: snapshot,
                    isEnabled: receiver.watchMascotEnabled,
                    message: receiver.watchMascotMessage,
                    themeId: receiver.watchThemeId,
                    customThemeId: receiver.watchCustomThemeId,
                    accessibilityHintText: receiver.watchMascotEnabled
                        ? String(localized: "轻点互动，拖动跟随，长按打开全部功能")
                        : String(localized: "长按打开全部功能"),
                    longPressActionName: String(localized: "打开全部功能"),
                    onLongPress: {
                        #if os(watchOS)
                        WKInterfaceDevice.current().play(.click)
                        #endif
                        openMore()
                    }
                )
                .frame(width: min(proxy.size.width * 0.48, 96), height: min(proxy.size.width * 0.48, 96))
                .contentShape(Circle())

                Button(action: openRecovery) {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(state.valueColor)
                                .frame(width: 6, height: 6)
                            Text(state.statusText)
                                .font(.watchAppSystem(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            if receiver.isAIWorking {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }

                        TimelineView(.periodic(from: .now, by: 5)) { _ in
                            Text(statusDetail)
                                .font(.watchAppSystem(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(state.valueColor.opacity(0.22), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)

                WatchQuickLaunchBar(
                    isAIWorking: receiver.isAIWorking,
                    hasUnreadAIAnswer: receiver.hasUnreadAIAnswer,
                    openPressure: openPressure,
                    openSleep: openSleep,
                    openMotivation: openMotivation,
                    openAI: openAI,
                    openMore: openMore,
                    openSwimming: openSwimming
                )
            }
            .padding(.horizontal, 8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct WatchQuickLaunchBar: View {
    let isAIWorking: Bool
    let hasUnreadAIAnswer: Bool
    let openPressure: () -> Void
    let openSleep: () -> Void
    let openMotivation: () -> Void
    let openAI: () -> Void
    let openMore: () -> Void
    let openSwimming: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                quickButton(title: String(localized: "游泳"), icon: "figure.pool.swim", tint: Color(red: 0.36, green: 0.91, blue: 0.82), action: openSwimming)
                quickButton(title: String(localized: "压力"), icon: "waveform.path.ecg", tint: .pink, action: openPressure)
                quickButton(title: String(localized: "睡眠"), icon: "moon.stars.fill", tint: .indigo, action: openSleep)
                quickButton(title: String(localized: "鼓励"), icon: "quote.bubble.fill", tint: .orange, action: openMotivation)
                quickButton(
                    title: isAIWorking ? String(localized: "整理中") : String(localized: "问 AI"),
                    icon: "sparkles",
                    tint: Color(red: 0.66, green: 0.78, blue: 1),
                    showsBadge: hasUnreadAIAnswer,
                    action: openAI
                )
                quickButton(title: String(localized: "更多"), icon: "square.grid.2x2", tint: .mint, action: openMore)
            }
        }
    }

    private func quickButton(
        title: String,
        icon: String,
        tint: Color,
        showsBadge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 20)
                    .overlay(alignment: .topTrailing) {
                        if showsBadge {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                        }
                    }
                Text(title)
                    .font(.watchAppSystem(size: 9, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(width: 45, height: 42)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct WatchFocusMascot: View {
    let snapshot: WatchRealtimeHealth?
    let isEnabled: Bool
    let message: String?
    let themeId: String
    var customThemeId: String? = nil
    let accessibilityHintText: String
    let longPressActionName: String
    let onLongPress: () -> Void

    /// 当前槽位对应素材是否可用（有自定义主题且已收到该档素材）。
    private var activeCustomSlot: WatchThemeSlot? {
        guard let customThemeId,
              let theme = WatchCustomThemeFileStore.readMeta(themeId: customThemeId),
              !theme.slots.isEmpty else {
            return nil
        }
        let slot = WatchThemeSlotResolver.slot(
            hrv: snapshot?.hrv ?? 0,
            stress: snapshot?.stress_value ?? 0
        )
        let chain = WatchThemeSlotResolver.fallbackChain(for: slot)
        return chain.first { theme.slots[$0] != nil }
    }

    var body: some View {
        VStack(spacing: 1) {
            if isEnabled, let slot = activeCustomSlot, let customThemeId {
                WatchCustomThemeMascotView(
                    themeId: customThemeId,
                    slot: slot,
                    accessibilityHintText: accessibilityHintText,
                    longPressActionName: longPressActionName,
                    onLongPress: onLongPress
                )

                if let message = WatchMascotContentPolicy.normalize(message) {
                    Text(message)
                        .font(.watchAppSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            } else if isEnabled {
                WatchAnimatedMascotView(
                    themeId: themeId,
                    hrv: snapshot?.hrv ?? 0,
                    stressValue: snapshot?.stress_value ?? 0,
                    stressState: snapshot?.stressState,
                    accent: .mint,
                    accessibilityHintText: accessibilityHintText,
                    longPressActionName: longPressActionName,
                    onLongPress: onLongPress
                )

                if let message = WatchMascotContentPolicy.normalize(message) {
                    Text(message)
                        .font(.watchAppSystem(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            } else {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.mint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.mint.opacity(0.12), in: Circle())
                    .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("健康状态")
                    .accessibilityHint(accessibilityHintText)
                    .accessibilityAction(named: longPressActionName) { onLongPress() }
            }
        }
    }
}

/// WatchCustomThemeMascotView 用自定义素材替换官方吉祥物徽章，保留原圆底、呼吸感与交互。
private struct WatchCustomThemeMascotView: View {
    let themeId: String
    let slot: WatchThemeSlot
    let accessibilityHintText: String
    let longPressActionName: String
    let onLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let phase = sin(context.date.timeIntervalSinceReferenceDate * 2.0)
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.62))
                Circle()
                    .stroke(Color.mint.opacity(0.75), lineWidth: 1.2)
                Circle()
                    .fill(Color.mint.opacity(0.18))
                    .padding(3)

                WatchCustomThemeArtworkView(themeId: themeId, slot: slot)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            }
            .scaleEffect(reduceMotion ? 1 : 1 + phase * 0.02)
            .offset(y: reduceMotion ? 0 : phase * 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前健康伙伴")
        .accessibilityHint(accessibilityHintText)
        .accessibilityAction(named: longPressActionName) { onLongPress() }
    }
}

private struct WatchFocusActionButton: View {
    let icon: String
    let title: String
    let tint: Color
    var showsBadge = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.watchAppSystem(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(alignment: .topTrailing) {
                if showsBadge {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                        .offset(x: -3, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WatchFeaturePicker: View {
    var receiver: WatchConnectivityReceiver
    let snapshot: WatchRealtimeHealth

    var body: some View {
        NavigationStack {
            List {
                Section("今天") {
                    NavigationLink { WatchRecoveryInfoSheet(snapshot: snapshot) } label: {
                        rowLabel(String(localized: "恢复状态"), icon: "heart.text.square.fill", tint: .mint)
                    }
                    NavigationLink { WatchTodayPressureView(snapshot: snapshot) } label: {
                        rowLabel(String(localized: "今日压力"), icon: "waveform.path.ecg", tint: .pink)
                    }
                    NavigationLink { WatchMindRhythmView(snapshot: snapshot) } label: {
                        rowLabel(String(localized: "身心节奏"), icon: "brain.head.profile", tint: .mint)
                    }
                    NavigationLink { WatchNightSleepView(snapshot: snapshot) } label: {
                        rowLabel(String(localized: "睡眠"), icon: "moon.stars.fill", tint: .indigo)
                    }
                    NavigationLink { ActivitySummaryView(receiver: receiver) } label: {
                        rowLabel(String(localized: "活动"), icon: "figure.walk", tint: .green)
                    }
                }

                Section("助手") {
                    NavigationLink { WatchMotivationView(snapshot: snapshot) } label: {
                        rowLabel(String(localized: "每日鼓励"), icon: "quote.bubble.fill", tint: .orange)
                    }
                    NavigationLink { WatchAIView(receiver: receiver) } label: {
                        rowLabel(receiver.isAIWorking ? String(localized: "Pulse AI 正在整理") : String(localized: "问问 Pulse AI"), icon: "sparkles", tint: .blue)
                    }
                }

                Section("手表") {
                    NavigationLink { ComplicationGuideView(receiver: receiver, showsCloseButton: false) } label: {
                        rowLabel(String(localized: "表盘与组件"), icon: "applewatch.watchface", tint: .orange)
                    }
                }
            }
            .navigationTitle("眠屿")
        }
    }

    private func rowLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            HStack {
                Text(title)
                    .font(.watchAppSystem(size: 13, weight: .semibold, design: .rounded))
                if title.contains("Pulse AI"), receiver.hasUnreadAIAnswer {
                    Circle().fill(.red).frame(width: 7, height: 7)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
    }
}
