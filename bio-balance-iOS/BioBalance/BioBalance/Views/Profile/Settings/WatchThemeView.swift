/// WatchThemeView 可由设置入口调用，用来选择 Apple Watch 端展示的吉祥物主题。
import SwiftUI

/// WatchTheme 用于描述单个 Watch 吉祥物主题的数据模型。
struct WatchTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let accent: Color
    let background: Color
    let style: WatchMascotStyle
}

/// WatchMascotStyle 用于区分不同吉祥物绘制风格。
enum WatchMascotStyle: Hashable {
    case bubble
    case bossCat
    case bear
    case flowerCat
    case bunny
    case tiger
    case pig
    case joey
}

/// WatchThemeView 负责承载 Watch 主题选择页面（官方吉祥物 + 自定义主题）与主题同步逻辑。
struct WatchThemeView: View {
    @AppStorage("watchThemeId") private var watchThemeId: String = "joey"
    @AppStorage("watchMascotEnabled") private var watchMascotEnabled: Bool = true
    @AppStorage("watchMascotMessage") private var watchMascotMessage: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var customThemeStore = WatchCustomThemeStore.shared
    @State private var themeToDelete: CustomWatchTheme?

    private let themes: [WatchTheme] = [
        WatchTheme(id: "bubble", name: "压力泡泡", accent: Color(hex: "68D4A2"), background: Color(hex: "EDFFF5"), style: .bubble),
        WatchTheme(id: "bosscat", name: "醒神仔", accent: Color(hex: "FFD85E"), background: Color(hex: "FFF9E8"), style: .bossCat),
        WatchTheme(id: "bearjoy", name: "小熊joy", accent: Color(hex: "F0C27B"), background: Color(hex: "FFF5E7"), style: .bear),
        WatchTheme(id: "flowercat", name: "焦绿猫", accent: Color(hex: "FF9BC3"), background: Color(hex: "FFF2F7"), style: .flowerCat),
        WatchTheme(id: "bunny", name: "汪啊", accent: Color(hex: "F3A6D2"), background: Color(hex: "FFF4FA"), style: .bunny),
        WatchTheme(id: "tiger", name: "虎虎", accent: Color(hex: "8F94FF"), background: Color(hex: "F5F6FF"), style: .tiger),
        WatchTheme(id: "piggy", name: "猪傻傻", accent: Color(hex: "FF9FA8"), background: Color(hex: "FFF4F5"), style: .pig),
        WatchTheme(id: "joey", name: "周伊 Joey", accent: Color(hex: "63D6A0"), background: Color(hex: "F0FFF7"), style: .joey)
    ]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var selectedTheme: WatchTheme {
        // themes 是内置静态非空数组，兜底分支仅用于消除强制解包；即便数组被清空也不会崩溃。
        themes.first(where: { $0.id == watchThemeId }) ?? themes.last ?? WatchTheme(
            id: "joey",
            name: "周伊 Joey",
            accent: Color(hex: "63D6A0"),
            background: Color(hex: "F0FFF7"),
            style: .joey
        )
    }

    var body: some View {
        ZStack {
            ReportsSoftBackground()
            mascotAmbientBackground

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    customizationCard
                    customThemeCard
                    mascotGridCard
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Watch 主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            AppGroupManager.shared.saveWatchThemeId(watchThemeId)
            persistMascotConfiguration()
        }
        .onDisappear { persistMascotConfiguration() }
        .alert(
            "删除主题",
            isPresented: Binding(
                get: { themeToDelete != nil },
                set: { if !$0 { themeToDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let themeToDelete {
                    customThemeStore.deleteTheme(themeId: themeToDelete.id)
                }
                themeToDelete = nil
            }
        } message: {
            if let themeToDelete {
                Text("确定删除「\(themeToDelete.name)」吗？删除后手表将恢复默认形象。")
            }
        }
    }

    private var mascotAmbientBackground: some View {
        Theme.Colors.pageBackground
            .ignoresSafeArea()
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            if let activeTheme = customThemeStore.activeTheme {
                WatchThemeWatchPreview(
                    content: .custom(activeTheme, slot: .normal),
                    width: 140
                )
                .padding(.vertical, 8)
            } else {
                ZStack {
                    Circle()
                        .fill(selectedTheme.background)
                        .frame(width: 150, height: 150)
                        .overlay(
                            Circle()
                                .stroke(selectedTheme.accent.opacity(0.65), lineWidth: 4)
                        )

                    TimelineView(.periodic(from: .now, by: 0.3)) { context in
                        let phase = sin(context.date.timeIntervalSinceReferenceDate * 2.0)
                        WatchMascotPortrait(style: selectedTheme.style)
                            .frame(width: 118, height: 118)
                            .offset(y: reduceMotion ? 0 : phase * 3)
                            .scaleEffect(reduceMotion ? 1 : 1 + phase * 0.012)
                    }
                }
            }

            VStack(spacing: 6) {
                Text(customThemeStore.activeTheme?.name ?? selectedTheme.name)
                    .font(.appSystem(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                if customThemeStore.isUsingCustomTheme {
                    Button {
                        customThemeStore.restoreOfficialTheme()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.appSystem(size: 14, weight: .bold))
                            Text("恢复默认主题")
                                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.appSystem(size: 14, weight: .bold))
                        Text("同步手表形象")
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(selectedTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    /// 自定义主题区：创建入口 + 我的主题列表。
    private var customThemeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自定义主题")
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            NavigationLink(destination: WatchThemeCreateView()) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Colors.mintGreen.opacity(0.14))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "paintbrush.fill")
                                .font(.appSystem(size: 18, weight: .bold))
                                .foregroundColor(Theme.Colors.mintGreen)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("创建主题")
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text("上传图片打造专属原创主题")
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 13, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(14)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            if !customThemeStore.themes.isEmpty {
                VStack(spacing: 10) {
                    ForEach(customThemeStore.themes) { theme in
                        customThemeRow(theme)
                    }
                }
            }

            if let notice = customThemeStore.lastSyncNotice {
                Text(notice)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    private func customThemeRow(_ theme: CustomWatchTheme) -> some View {
        HStack(spacing: 12) {
            WatchThemeWatchPreview(
                content: .custom(theme, slot: .normal),
                width: 56,
                showSideButton: false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.name)
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("自定义主题")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            if customThemeStore.activeThemeId == theme.id {
                Text("使用中")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.mintGreen)
            } else {
                Button("使用") {
                    customThemeStore.useTheme(theme)
                }
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.mintGreen)
            }

            Menu {
                NavigationLink(destination: WatchThemePreviewView(theme: theme)) {
                    Label("预览", systemImage: "eye")
                }
                Button(role: .destructive) {
                    themeToDelete = theme
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(10)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var customizationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $watchMascotEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在 Watch 显示吉祥物")
                        .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                    Text("关闭后保留健康数据，只隐藏伙伴形象与陪伴语。")
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
            .tint(selectedTheme.accent)
            .onChange(of: watchMascotEnabled) { _, _ in persistMascotConfiguration() }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("自定义陪伴语")
                        .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                    Text(verbatim: "\(watchMascotMessage.count)/\(WatchMascotContentPolicy.maximumLength)")
                        .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                TextField("例如：慢一点，也很好", text: $watchMascotMessage)
                    .textFieldStyle(.plain)
                    .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(selectedTheme.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .disabled(!watchMascotEnabled)
                    .opacity(watchMascotEnabled ? 1 : 0.55)
                    .submitLabel(.done)
                    .onSubmit { persistMascotConfiguration() }
                    .onChange(of: watchMascotMessage) { _, value in
                        let limited = String(value.prefix(WatchMascotContentPolicy.maximumLength))
                        if limited != value { watchMascotMessage = limited }
                        persistMascotConfiguration(message: limited, syncToWatch: false)
                    }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    private func persistMascotConfiguration(message: String? = nil, syncToWatch: Bool = true) {
        let resolved = WatchMascotContentPolicy.normalize(message ?? watchMascotMessage)
        AppGroupManager.shared.saveWatchMascotConfiguration(isEnabled: watchMascotEnabled, message: resolved)
        if syncToWatch {
            HealthDataManager.shared.syncWatchMascotConfiguration(isEnabled: watchMascotEnabled, message: resolved)
        }
    }

    private var mascotGridCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("官方吉祥物")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                HStack(spacing: 6) {
                    Text("了解更多")
                        .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.appSystem(size: 12, weight: .bold))
                }
                .foregroundColor(Theme.Colors.textTertiary)
            }

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(themes) { theme in
                    Button {
                        watchThemeId = theme.id
                        AppGroupManager.shared.saveWatchThemeId(theme.id)
                        HealthDataManager.shared.syncWatchThemeSelection(theme.id)
                    } label: {
                        WatchThemeCard(theme: theme, isSelected: watchThemeId == theme.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }
}

/// WatchThemeCard 由 WatchThemeView 调用，用来渲染单个主题选项卡片。
private struct WatchThemeCard: View {
    let theme: WatchTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(theme.background)
                    .frame(width: 92, height: 92)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 4)
                    )

                WatchMascotPortrait(style: theme.style)
                    .frame(width: 72, height: 72)

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 26, height: 26)

                        Image(systemName: Theme.Icons.checkmark)
                            .font(.appSystem(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 2, y: 2)
                }
            }

            Text(theme.name)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

/// WatchMascotPortrait 由 WatchThemeView 和 WatchThemeCard 调用，用来渲染吉祥物主图。
private struct WatchMascotPortrait: View {
    let style: WatchMascotStyle

    var body: some View {
        switch style {
        case .bubble:
            BubbleMascotView()
        case .bossCat:
            BossCatMascotView()
        case .bear:
            BearMascotView()
        case .flowerCat:
            FlowerCatMascotView()
        case .bunny:
            BunnyMascotView()
        case .tiger:
            TigerMascotView()
        case .pig:
            PigMascotView()
        case .joey:
            Image("SettingsHeaderMascot")
                .resizable()
                .scaledToFit()
        }
    }
}

/// BubbleMascotView 用于绘制压力泡泡吉祥物。
private struct BubbleMascotView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "68D4A2"))
            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 18, height: 18)
                .offset(x: 22, y: -10)
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.88))
                    .frame(width: 18, height: 8)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.88))
                    .frame(width: 18, height: 8)
            }
            .offset(y: -6)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.88))
                .frame(width: 9, height: 3)
                .offset(y: -6)
            Capsule()
                .fill(Color.black.opacity(0.85))
                .frame(width: 18, height: 5)
                .offset(y: 14)
        }
    }
}

/// BossCatMascotView 用于绘制醒神仔吉祥物。
private struct BossCatMascotView: View {
    var body: some View {
        ZStack {
            CatHeadShape()
                .fill(Color.white)
            CatHeadShape()
                .stroke(Color.black.opacity(0.82), lineWidth: 2.5)
            CrownShape()
                .fill(Color(hex: "FFD85E"))
                .frame(width: 20, height: 11)
                .offset(y: -28)
            HStack(spacing: 10) {
                SparkShape()
                    .fill(Color(hex: "FFD85E"))
                    .frame(width: 8, height: 8)
                SparkShape()
                    .fill(Color(hex: "FFD85E"))
                    .frame(width: 8, height: 8)
            }
            .offset(y: -24)
            .rotationEffect(.degrees(8))
            HStack(spacing: 10) {
                ArcEyeShape()
                    .stroke(Color.black.opacity(0.82), lineWidth: 2.5)
                    .frame(width: 14, height: 10)
                ArcEyeShape()
                    .stroke(Color.black.opacity(0.82), lineWidth: 2.5)
                    .frame(width: 14, height: 10)
                    .scaleEffect(x: -1, y: 1)
            }
            .offset(y: -3)
            Circle()
                .fill(Color(hex: "C7D4F7"))
                .frame(width: 28, height: 18)
                .offset(y: 10)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 12, y: 0), control: CGPoint(x: 6, y: 6))
            }
            .stroke(Color.black.opacity(0.82), lineWidth: 2.5)
            .frame(width: 12, height: 8)
            .offset(y: 16)
        }
    }
}

/// BearMascotView 用于绘制小熊 Joy 吉祥物。
private struct BearMascotView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hex: "E8BD82"))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.75), lineWidth: 2.2)
            Circle()
                .fill(Color(hex: "F7DAB0"))
                .frame(width: 18, height: 18)
                .offset(x: -18, y: -16)
            Circle()
                .fill(Color(hex: "F7DAB0"))
                .frame(width: 18, height: 18)
                .offset(x: 18, y: -16)
            HStack(spacing: 14) {
                Circle().fill(Color.black.opacity(0.82)).frame(width: 5, height: 5)
                Circle().fill(Color.black.opacity(0.82)).frame(width: 5, height: 5)
            }
            .offset(y: -6)
            Capsule()
                .fill(Color(hex: "F98E68"))
                .frame(width: 18, height: 12)
                .offset(y: 10)
        }
    }
}

/// FlowerCatMascotView 用于绘制焦绿猫吉祥物。
private struct FlowerCatMascotView: View {
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(Color(hex: "FFB1C9"))
                    .frame(width: 22, height: 22)
                    .offset(y: -28)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle()
                .fill(Color(hex: "8FD772"))
                .frame(width: 54, height: 54)
            CatHeadShape()
                .stroke(Color.black.opacity(0.78), lineWidth: 2.1)
                .frame(width: 42, height: 36)
            HStack(spacing: 10) {
                Circle().fill(Color.black.opacity(0.82)).frame(width: 4, height: 4)
                Circle().fill(Color.black.opacity(0.82)).frame(width: 4, height: 4)
            }
            .offset(y: -2)
            Capsule()
                .fill(Color.black.opacity(0.82))
                .frame(width: 12, height: 3)
                .offset(y: 11)
        }
    }
}

/// BunnyMascotView 用于绘制汪啊吉祥物。
private struct BunnyMascotView: View {
    var body: some View {
        ZStack {
            BunnyHeadShape()
                .fill(Color.white)
            BunnyHeadShape()
                .stroke(Color.black.opacity(0.82), lineWidth: 2.4)
            HStack(spacing: 12) {
                FlowerSparkView(color: Color(hex: "F7A8D5"))
                FlowerSparkView(color: Color(hex: "FFD85E"))
            }
            .offset(y: -20)
            HStack(spacing: 12) {
                ArcEyeShape()
                    .stroke(Color.black.opacity(0.82), lineWidth: 2.2)
                    .frame(width: 12, height: 9)
                ArcEyeShape()
                    .stroke(Color.black.opacity(0.82), lineWidth: 2.2)
                    .frame(width: 12, height: 9)
                    .scaleEffect(x: -1, y: 1)
            }
            .offset(y: -1)
            Circle()
                .fill(Color(hex: "FFB5D0"))
                .frame(width: 6, height: 6)
                .offset(y: 9)
        }
    }
}

/// TigerMascotView 用于绘制虎虎吉祥物。
private struct TigerMascotView: View {
    var body: some View {
        ZStack {
            CatHeadShape()
                .fill(Color.white)
            CatHeadShape()
                .stroke(Color.black.opacity(0.82), lineWidth: 2.5)
            HStack(spacing: 14) {
                Circle().fill(Color.black.opacity(0.88)).frame(width: 5, height: 5)
                Circle().fill(Color.black.opacity(0.88)).frame(width: 5, height: 5)
            }
            .offset(y: -4)
            Capsule()
                .fill(Color.black.opacity(0.88))
                .frame(width: 16, height: 4)
                .offset(y: 10)
            HStack(spacing: 22) {
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 8, height: 16)
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 8, height: 16)
            }
            .offset(y: -18)
        }
    }
}

/// PigMascotView 用于绘制猪傻傻吉祥物。
private struct PigMascotView: View {
    var body: some View {
        ZStack {
            PigHeadShape()
                .fill(Color.white)
            PigHeadShape()
                .stroke(Color.black.opacity(0.82), lineWidth: 2.4)
            HStack(spacing: 36) {
                FlowerSparkView(color: Color(hex: "FF909B"))
                FlowerSparkView(color: Color(hex: "FF909B"))
            }
            .offset(y: 4)
            HStack(spacing: 12) {
                ArcEyeShape()
                    .stroke(Color.black.opacity(0.82), lineWidth: 2.2)
                    .frame(width: 12, height: 9)
                ArcEyeShape()
                    .stroke(Color.black.opacity(0.82), lineWidth: 2.2)
                    .frame(width: 12, height: 9)
                    .scaleEffect(x: -1, y: 1)
            }
            .offset(y: -4)
            Capsule()
                .fill(Color.black.opacity(0.82))
                .frame(width: 14, height: 4)
                .offset(y: 10)
        }
    }
}

/// FlowerSparkView 由花朵系吉祥物调用，用来渲染装饰性星火。
private struct FlowerSparkView: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .offset(y: -5)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
        }
        .frame(width: 12, height: 12)
    }
}

/// CatHeadShape 用于花猫相关头像的轮廓绘制。
nonisolated private struct CatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.maxY - rect.height * 0.18), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.34), control: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.26, y: rect.minY + rect.height * 0.02), control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

/// BunnyHeadShape 用于兔子头像的轮廓绘制。
nonisolated private struct BunnyHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.22, width: rect.width * 0.64, height: rect.height * 0.58), cornerSize: CGSize(width: rect.width * 0.28, height: rect.height * 0.28))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.23, y: rect.minY, width: rect.width * 0.18, height: rect.height * 0.34), cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12))
        path.addRoundedRect(in: CGRect(x: rect.maxX - rect.width * 0.41, y: rect.minY, width: rect.width * 0.18, height: rect.height * 0.34), cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12))
        return path
    }
}

/// PigHeadShape 用于猪猪头像的轮廓绘制。
nonisolated private struct PigHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.14, width: rect.width * 0.80, height: rect.height * 0.72))
    }
}

/// CrownShape 用于醒神仔头冠装饰的轮廓绘制。
nonisolated private struct CrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// SparkShape 用于装饰性闪光图形的轮廓绘制。
nonisolated private struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.midY - rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.midY + rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.midY + rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.midY - rect.height * 0.16))
        path.closeSubpath()
        return path
    }
}

/// ArcEyeShape 用于表情眼睛弧线的轮廓绘制。
nonisolated private struct ArcEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

#Preview {
    NavigationStack {
        WatchThemeView()
    }
}
