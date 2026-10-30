/// CacheManagementView 由 SettingsView 调用，作为「页面缓存」管理页。
/// 负责展示缓存统计、分类缓存状态与同步状态，并承接清理、刷新和详情操作。

import SwiftUI

/// 缓存管理页，承接页面缓存总览、分类清理、状态刷新与详情查看。
struct CacheManagementView: View {
    let stats: CacheManagementStats

    @State private var pendingClearRequest: CacheClearRequest?
    @State private var showDetails = false
    @State private var cleanerRotation = false
    @State private var completionPop = false

    private var cacheSnapshot: AppDataCacheSnapshot {
        stats.snapshot.appDataSnapshot
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            AdaptivePageScrollView(topPadding: 12, bottomPadding: 88) {
                VStack(alignment: .leading, spacing: 12) {
                    cacheSectionBlock(title: "缓存总览") {
                        overviewContent
                    }

                    cacheSectionBlock(title: "当前缓存") {
                        categoryList
                    }

                    cacheSectionBlock(title: "缓存状态") {
                        statusList
                    }

                    cacheSectionBlock(title: "清理范围") {
                        scopeList
                    }

                    cacheSectionBlock(title: "执行操作") {
                        actionsPanel
                    }
                }
            }
        }
        .navigationTitle("页面缓存")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await stats.refresh() }
        .alert(
            pendingClearRequest?.title ?? "",
            isPresented: Binding(
                get: { pendingClearRequest != nil },
                set: { if !$0 { pendingClearRequest = nil } }
            ),
            presenting: pendingClearRequest
        ) { request in
            Button("取消", role: .cancel) {}
            Button("立即清理", role: .destructive) {
                switch request {
                case .all:
                    Task { await runClear(categories: Set(AppDataCacheCategory.allCases)) }
                case .category(let category):
                    Task { await runClear(categories: [category]) }
                }
            }
        } message: { request in
            Text(request.message)
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                CacheManagementDetailsView(snapshot: stats.snapshot)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .onChange(of: stats.isClearing) { _, newValue in
            if newValue {
                completionPop = false
                startCleanerRotation()
            } else {
                cleanerRotation = false
            }
        }
        .onChange(of: stats.lastOperation) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                completionPop = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.18)) {
                    completionPop = false
                }
            }
        }
    }

    // MARK: - 概览

    private var overviewContent: some View {
        VStack(spacing: 12) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                overviewTile(
                    title: "内存缓存",
                    value: "\(stats.snapshot.memoryCacheCount) 个",
                    tint: Theme.Colors.accentBlue
                )
                overviewTile(
                    title: "磁盘缓存",
                    value: Self.cacheSizeText(cacheSnapshot.totalBytes),
                    tint: Theme.Colors.mintGreen
                )
                overviewTile(
                    title: "数据库缓存",
                    value: databaseValueText,
                    tint: Color(hex: "FFB340")
                )
                overviewTile(
                    title: "缓存命中",
                    value: stats.snapshot.cacheHitStatsAvailable ? "已统计" : "未接入",
                    tint: Theme.Colors.textTertiary
                )
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近统计")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(Self.dateTimeText(stats.snapshot.generatedAt))
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                refreshButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var refreshButton: some View {
        Button {
            Task { await runRefresh() }
        } label: {
            HStack(spacing: 6) {
                if stats.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Colors.accentBlue)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                }
                Text(stats.isRefreshing ? "刷新中" : "刷新")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(Theme.Colors.accentBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.Colors.accentBlue.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(stats.isRefreshing || stats.isClearing)
    }

    private func overviewTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var databaseValueText: String {
        if stats.snapshot.databaseCacheCorrupted {
            return "异常"
        }
        guard let count = stats.snapshot.databaseCacheCount else {
            return "等待"
        }
        return "\(count) 条"
    }

    // MARK: - 分类

    private var categoryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(AppDataCacheCategory.allCases.enumerated()), id: \.element) { index, category in
                Button {
                    pendingClearRequest = .category(category)
                } label: {
                    cacheStatusRow(for: cacheSnapshot.category(category))
                }
                .buttonStyle(.plain)
                .disabled(stats.isClearing)

                if index < AppDataCacheCategory.allCases.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
    }

    private func cacheStatusRow(for snapshot: AppDataCacheCategorySnapshot) -> some View {
        let category = snapshot.category
        let hasCache = snapshot.itemCount > 0
        return HStack(alignment: .top, spacing: 12) {
            settingsInfoRow(
                title: category.title,
                detail: hasCache
                    ? "\(snapshot.itemCount) 项 · \(Self.cacheSizeText(snapshot.totalBytes)) · \(Self.lastUpdatedText(snapshot.lastUpdatedAt))"
                    : "暂无可清理项目",
                tint: tint(for: category),
                symbol: hasCache ? symbol(for: category) : "checkmark"
            )

            Image(systemName: hasCache ? "chevron.right" : "checkmark.circle.fill")
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(hasCache ? Color(hex: "B9C2D0") : Theme.Colors.mintGreen)
                .padding(.top, 27)
                .padding(.trailing, 18)
                .transition(.scale.combined(with: .opacity))
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: snapshot.itemCount)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: snapshot.totalBytes)
    }

    // MARK: - 状态

    private var statusList: some View {
        VStack(spacing: 0) {
            settingsInfoRow(icon: "memorychip", tint: Theme.Colors.accentBlue, title: "内存缓存", detail: memoryStatusDetail)
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "internaldrive", tint: Theme.Colors.mintGreen, title: "磁盘缓存", detail: "\(Self.cacheSizeText(cacheSnapshot.totalBytes)) · \(cacheSnapshot.totalItemCount) 项持久化数据")
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "cylinder.split.1x2", tint: Color(hex: "FFB340"), title: "数据库缓存", detail: databaseStatusDetail)
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "square.grid.2x2", tint: Color(hex: "6D7EF7"), title: "App Group 快照", detail: appGroupStatusDetail)
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "square.grid.2x2.fill", tint: Color(hex: "55BFF4"), title: "Widget 同步", detail: widgetSyncStatusDetail)
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "applewatch.radiowaves.left.and.right", tint: Color(hex: "5BB7C5"), title: "Watch 同步", detail: watchSyncStatusDetail)
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "clock.arrow.circlepath", tint: Theme.Colors.accentBlue, title: "最近清理", detail: lastClearStatusDetail)
            Divider().padding(.leading, 76)
            settingsInfoRow(icon: "scope", tint: Theme.Colors.textTertiary, title: "缓存命中", detail: String(localized: "当前未接入命中统计，等待缓存架构模块补充"))
        }
    }

    private var memoryStatusDetail: String {
        String(localized: "\(stats.snapshot.memoryCacheCount) 个运行时快照正在使用")
    }

    private var databaseStatusDetail: String {
        if stats.snapshot.databaseCacheCorrupted {
            return String(localized: "本地同步队列异常，暂无法统计")
        }
        guard let count = stats.snapshot.databaseCacheCount else {
            return String(localized: "本地同步队列等待首次统计")
        }
        return String(localized: "\(count) 条待同步记录（SwiftData）")
    }

    private var appGroupStatusDetail: String {
        guard stats.snapshot.appGroupAvailable else {
            return String(localized: "App Group 不可用")
        }
        let itemText = "\(stats.snapshot.appGroupItemCount) 项"
        if let date = stats.snapshot.appGroupLastWriteAt {
            return "\(itemText) · 最后写入 \(Self.dateTimeText(date))"
        }
        return "\(itemText) · 尚无快照写入"
    }

    private var widgetSyncStatusDetail: String {
        guard let date = stats.snapshot.widgetLastSyncAt else {
            return String(localized: "待同步")
        }
        let status = Date().timeIntervalSince(date) <= 6 * 60 * 60
            ? String(localized: "已同步")
            : String(localized: "数据较旧")
        return "\(status) · \(Self.dateTimeText(date))"
    }

    private var watchSyncStatusDetail: String {
        let watch = stats.snapshot.watchState
        var parts: [String] = []
        if watch.isPaired {
            parts.append(String(localized: "已配对"))
            if watch.isInstalled {
                parts.append(String(localized: "已安装"))
            }
        } else {
            parts.append(String(localized: "未配对"))
        }
        parts.append(watch.activationText)
        if watch.isReachable {
            parts.append(String(localized: "可连接"))
        }
        if let date = watch.lastSyncAt {
            parts.append(Self.dateTimeText(date))
        }
        return parts.joined(separator: " · ")
    }

    private var lastClearStatusDetail: String {
        guard let date = stats.lastClearDate else {
            return String(localized: "暂无清理记录")
        }
        return String(localized: "最近清理 \(Self.dateTimeText(date))")
    }

    // MARK: - 范围

    private var scopeList: some View {
        VStack(spacing: 0) {
            settingsInfoRow(title: "可清理", detail: "页面派生快照 / Widget 展示快照 / Watch 传输缓存", tint: Theme.Colors.accentBlue, symbol: "trash")
            Divider().padding(.leading, 76)
            settingsInfoRow(title: "不会删除", detail: "账号、偏好、目标、Health 原始数据和用户记录", tint: Theme.Colors.mintGreen, symbol: "lock.shield")
            Divider().padding(.leading, 76)
            settingsInfoRow(title: "清理后", detail: "重新进入今日、健康和趋势页后会按当前数据重新累积", tint: Color(hex: "FFB340"), symbol: "arrow.clockwise")
        }
    }

    // MARK: - 操作

    private var actionsPanel: some View {
        VStack(spacing: 14) {
            cacheCleaningAnimationPanel

            if let operation = stats.lastOperation {
                operationBanner(for: operation)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 18)
            }

            clearCacheButton
                .padding(.horizontal, 18)

            HStack(spacing: 10) {
                actionButton(
                    title: String(localized: "刷新状态"),
                    detail: String(localized: "重新读取缓存统计"),
                    symbol: "arrow.clockwise",
                    tint: Theme.Colors.accentBlue,
                    isLoading: stats.isRefreshing
                ) {
                    Task { await runRefresh() }
                }
                .disabled(stats.isClearing || stats.isRefreshing)

                actionButton(
                    title: String(localized: "缓存详情"),
                    detail: String(localized: "查看分类与占用"),
                    symbol: "list.bullet.rectangle",
                    tint: Color(hex: "6D7EF7"),
                    isLoading: false
                ) {
                    showDetails = true
                }
                .disabled(stats.isClearing)
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 15)
    }

    private var clearCacheButton: some View {
        let isEmpty = cacheSnapshot.totalItemCount == 0
        let tint = isEmpty ? Theme.Colors.mintGreen : Theme.Colors.accentRed

        return Button {
            pendingClearRequest = .all
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Colors.onAccent.opacity(0.16))

                    if stats.isClearing {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.appSystem(size: 16, weight: .bold))
                            .rotationEffect(.degrees(cleanerRotation ? 360 : 0))
                            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: cleanerRotation)
                    } else {
                        Image(systemName: isEmpty ? "checkmark" : "trash")
                            .font(.appSystem(size: 16, weight: .bold))
                    }
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(clearActionTitle)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    Text(clearActionDetail)
                        .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.78)
                }

                Spacer(minLength: 8)

                Image(systemName: isEmpty ? "checkmark.circle.fill" : "chevron.right")
                    .font(.appSystem(size: 14, weight: .bold))
                    .opacity(0.82)
            }
            .foregroundColor(Theme.Colors.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                    .stroke(Theme.Colors.onAccent.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(stats.isClearing || stats.isRefreshing || isEmpty)
        .opacity(stats.isRefreshing ? 0.58 : 1)
        .accessibilityLabel(clearActionTitle)
        .accessibilityHint(clearActionDetail)
    }

    private var clearActionTitle: String {
        if stats.isClearing {
            return String(localized: "正在清理")
        }
        return cacheSnapshot.totalItemCount == 0
            ? String(localized: "暂无可清理缓存")
            : String(localized: "清理页面缓存")
    }

    private var clearActionDetail: String {
        cacheSnapshot.totalItemCount == 0
            ? String(localized: "当前没有可清理的页面缓存。")
            : String(localized: "释放可重建的本地缓存")
    }

    private func actionButton(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(tint.opacity(0.12))

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(tint)
                        } else {
                            Image(systemName: symbol)
                                .font(.appSystem(size: 16, weight: .bold))
                                .foregroundColor(tint)
                        }
                    }
                    .frame(width: 38, height: 38)

                    Spacer(minLength: 6)

                    Image(systemName: "arrow.up.right")
                        .font(.appSystem(size: 11, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(detail)
                        .font(.appSystem(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
            .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.inset, style: .continuous)
                    .stroke(tint.opacity(0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func operationBanner(for operation: CacheManagementOperationResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: operationSymbol(for: operation.tone))
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundColor(operationTint(for: operation.tone))
            Text(operation.message)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(operationBackground(for: operation.tone), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 动画面板

    private var cacheCleaningAnimationPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.surfaceBorder, lineWidth: 5)
                        .frame(width: 58, height: 58)

                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            ringTint,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 58, height: 58)
                        .rotationEffect(.degrees(stats.isClearing && cleanerRotation ? 360 : -90))
                        .scaleEffect(completionPop ? 1.08 : 1)
                        .animation(
                            stats.isClearing
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .spring(response: 0.34, dampingFraction: 0.72),
                            value: cleanerRotation
                        )
                        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: completionPop)

                    Image(systemName: actionSymbol)
                        .font(.appSystem(size: 21, weight: .heavy))
                        .foregroundColor(ringTint)
                        .rotationEffect(.degrees(stats.isClearing && cleanerRotation ? 360 : 0))
                        .scaleEffect(completionPop ? 1.18 : 1)
                        .animation(
                            stats.isClearing
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .spring(response: 0.34, dampingFraction: 0.62),
                            value: cleanerRotation
                        )
                        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: completionPop)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(actionTitle)
                        .font(.appSystem(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(actionDetail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(AppDataCacheCategory.allCases, id: \.self) { category in
                    cacheCategoryMeter(for: cacheSnapshot.category(category))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: cacheSnapshot.totalItemCount)
    }

    private func cacheCategoryMeter(for snapshot: AppDataCacheCategorySnapshot) -> some View {
        let category = snapshot.category
        let tint = tint(for: category)
        let hasCache = snapshot.itemCount > 0

        return HStack(spacing: 10) {
            Text(category.title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "6D788A"))
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.secondaryBackground)

                    Capsule()
                        .fill(hasCache ? tint.opacity(stats.isClearing ? 0.72 : 0.58) : Theme.Colors.mintGreen.opacity(0.55))
                        .frame(width: max(6, proxy.size.width * meterRatio(for: snapshot)))
                        .scaleEffect(x: stats.isClearing && hasCache ? 0.72 : 1, anchor: .leading)
                        .opacity(hasCache ? 1 : 0.62)
                        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: snapshot.itemCount)
                        .animation(.easeInOut(duration: 0.52), value: stats.isClearing)
                }
            }
            .frame(height: 7)

            Text(hasCache ? "\(snapshot.itemCount)" : "0")
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(hasCache ? tint : Theme.Colors.mintGreen)
                .frame(width: 24, alignment: .trailing)
                .animation(.spring(response: 0.36, dampingFraction: 0.8), value: snapshot.itemCount)
        }
    }

    private var actionTitle: String {
        if stats.isClearing {
            return String(localized: "正在清理缓存")
        }
        return cacheSnapshot.totalItemCount == 0
            ? String(localized: "暂无可清理缓存")
            : String(localized: "准备清理页面缓存")
    }

    private var actionDetail: String {
        if stats.isClearing {
            return String(localized: "正在移除可重建的展示快照和同步缓存")
        }
        if cacheSnapshot.totalItemCount == 0 {
            return String(localized: "账号、偏好、目标和用户记录保持不变")
        }
        return String(localized: "\(cacheSnapshot.totalItemCount) 项派生缓存可清理，共 \(Self.cacheSizeText(cacheSnapshot.totalBytes))")
    }

    private var actionSymbol: String {
        if stats.isClearing {
            return "arrow.triangle.2.circlepath"
        }
        return cacheSnapshot.totalItemCount == 0 ? "checkmark" : "trash"
    }

    private var ringTint: Color {
        if stats.isClearing {
            return Theme.Colors.accentRed
        }
        return cacheSnapshot.totalItemCount == 0 ? Theme.Colors.mintGreen : Theme.Colors.accentBlue
    }

    private var ringProgress: CGFloat {
        if stats.isClearing {
            return 0.78
        }
        return cacheSnapshot.totalItemCount == 0 ? 1 : 0.36
    }

    private func meterRatio(for snapshot: AppDataCacheCategorySnapshot) -> CGFloat {
        guard snapshot.itemCount > 0 else { return 1 }
        let totalBytes = max(cacheSnapshot.totalBytes, 1)
        let byteRatio = CGFloat(snapshot.totalBytes) / CGFloat(totalBytes)
        let countRatio = CGFloat(snapshot.itemCount) / CGFloat(max(cacheSnapshot.totalItemCount, 1))
        return min(1, max(0.18, (byteRatio * 0.72) + (countRatio * 0.28)))
    }

    // MARK: - 辅助方法

    private func runRefresh() async {
        guard !stats.isRefreshing, !stats.isClearing else { return }
        await stats.refresh()
        stats.setOperationFeedback(
            CacheManagementOperationResult(
                tone: .success,
                message: String(localized: "缓存状态已刷新。")
            )
        )
    }

    private func runClear(categories: Set<AppDataCacheCategory>) async {
        guard !stats.isClearing else { return }
        _ = await stats.clear(categories: categories)
    }

    private func startCleanerRotation() {
        cleanerRotation = false
        DispatchQueue.main.async {
            cleanerRotation = true
        }
    }

    private func settingsInfoRow(title: String, detail: String, tint: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: symbol)
                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func settingsInfoRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        settingsInfoRow(title: title, detail: detail, tint: tint, symbol: icon)
    }

    private func cacheSectionBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSectionCard(title: title) {
            content()
        }
    }

    private func tint(for category: AppDataCacheCategory) -> Color {
        switch category {
        case .localPageSnapshots:
            return Theme.Colors.accentBlue
        case .sharedWidgetSnapshots:
            return Theme.Colors.mintGreen
        case .watchTransportSnapshots:
            return Color(hex: "FFB340")
        }
    }

    private func symbol(for category: AppDataCacheCategory) -> String {
        switch category {
        case .localPageSnapshots:
            return "doc.text.magnifyingglass"
        case .sharedWidgetSnapshots:
            return "rectangle.grid.2x2"
        case .watchTransportSnapshots:
            return "applewatch.radiowaves.left.and.right"
        }
    }

    private func operationSymbol(for tone: CacheManagementOperationTone) -> String {
        switch tone {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private func operationTint(for tone: CacheManagementOperationTone) -> Color {
        switch tone {
        case .success:
            return Theme.Colors.mintGreen
        case .failure:
            return Theme.Colors.accentRed
        case .info:
            return Theme.Colors.accentBlue
        }
    }

    private func operationBackground(for tone: CacheManagementOperationTone) -> Color {
        switch tone {
        case .success:
            return Color(hex: "F6FAF8")
        case .failure:
            return Color(hex: "FDF3F2")
        case .info:
            return Color(hex: "F2F7FC")
        }
    }

    fileprivate static func lastUpdatedText(_ date: Date?) -> String {
        guard let date else { return String(localized: "无更新时间") }
        return String(localized: "更新 \(dateTimeText(date))")
    }

    fileprivate static func dateTimeText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }

    fileprivate static func cacheSizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }
}

private enum CacheClearRequest: Identifiable {
    case all
    case category(AppDataCacheCategory)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .category(let category):
            return "category-\(category.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return String(localized: "清理页面缓存？")
        case .category(let category):
            return String(localized: "清理\(category.title)？")
        }
    }

    var message: String {
        switch self {
        case .all:
            return String(localized: "会清空页面派生快照、Widget 展示快照和 Watch 传输缓存，不会删除账号、偏好、目标、Health 原始数据或用户记录。")
        case .category(let category):
            return String(localized: "会移除「\(category.title)」下的派生缓存，不会删除账号、偏好、目标或 Health 原始数据。")
        }
    }
}

/// 缓存详情页，只展示条目元数据，不展示任何健康数值或原始样本。
private struct CacheManagementDetailsView: View {
    let snapshot: CacheManagementStatsSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    summaryBlock

                    ForEach(AppDataCacheCategory.allCases, id: \.self) { category in
                        categoryDetailBlock(category)
                    }

                    if !snapshot.cacheHitStatsAvailable {
                        cacheHitPlaceholder
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("缓存详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }

    private var summaryBlock: some View {
        HStack(spacing: 10) {
            miniTile(title: "总大小", value: CacheManagementView.cacheSizeText(snapshot.totalBytes), tint: Theme.Colors.accentBlue)
            miniTile(title: "总项目", value: "\(snapshot.totalItemCount) 项", tint: Theme.Colors.mintGreen)
        }
    }

    private func miniTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(value)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func categoryDetailBlock(_ category: AppDataCacheCategory) -> some View {
        let categorySnapshot = snapshot.appDataSnapshot.category(category)
        let items = categorySnapshot.items

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer(minLength: 8)
                Text("\(items.count) 项 · \(CacheManagementView.cacheSizeText(categorySnapshot.totalBytes))")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if items.isEmpty {
                Text("暂无缓存条目")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    itemRow(item)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder.opacity(0.8), lineWidth: 1)
        )
    }

    private func itemRow(_ item: AppDataCacheItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(CacheManagementView.cacheSizeText(item.sizeBytes))
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.accentBlue)
                    .lineLimit(1)
            }

            Text(item.key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let updatedAt = item.updatedAt {
                Text(CacheManagementView.dateTimeText(updatedAt))
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var cacheHitPlaceholder: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "scope")
                .font(.appSystem(size: 15, weight: .bold))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("命中统计")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("等待缓存架构模块补充命中率与缺失计数")
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
