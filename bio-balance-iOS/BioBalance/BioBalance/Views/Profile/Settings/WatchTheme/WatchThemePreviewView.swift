/// WatchThemePreviewView 承载「主题预览」：状态预览四宫格 + Watch 预览说明 + 分享 / 立即使用。
import SwiftUI
import AVKit

/// WatchThemePreviewView 展示已保存主题的全貌，并提供使用与分享入口。
struct WatchThemePreviewView: View {
    let theme: CustomWatchTheme

    @State private var customThemeStore = WatchCustomThemeStore.shared
    @State private var useNotice: String?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var isRenderingShareCard = false

    /// 演示用数据：预览页固定以“状态正常”展示主屏，四宫格遍历全部槽位。
    private let previewSlots = WatchThemeSlot.allCases

    var body: some View {
        ZStack {
            ReportsSoftBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    statusPreviewCard
                    watchExplainCard
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }

            VStack {
                Spacer()
                bottomBar
                    .padding(.horizontal, Theme.Layout.padding)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("主题预览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareCardActivitySheet(items: [shareURL])
            }
        }
        .overlay {
            if let useNotice {
                VStack {
                    Spacer()
                    Text(useNotice)
                        .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.bottom, 96)
                }
                .allowsHitTesting(false)
                .task {
                    try? await Task.sleep(for: .seconds(2.6))
                    self.useNotice = nil
                }
            }
        }
    }

    // MARK: - 主屏预览

    private var heroCard: some View {
        VStack(spacing: 14) {
            WatchThemeWatchPreview(
                content: .custom(theme, slot: .normal),
                width: 148
            )

            Text(theme.name)
                .font(.appSystem(size: 24, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    // MARK: - 状态预览

    private var statusPreviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("状态预览")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(previewSlots) { slot in
                    statusCell(slot)
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

    private func statusCell(_ slot: WatchThemeSlot) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "F5F6F5"))
                    .frame(height: 96)

                if let media = theme.slots[slot],
                   let image = UIImage(contentsOfFile: WatchCustomThemeFileStore.slotFileURL(
                        themeId: theme.id,
                        slot: slot,
                        fileExtension: media.fileExtension
                   ).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            .frame(height: 96)

            Text(slot.displayTitle)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    // MARK: - Watch 说明

    private var watchExplainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watch 预览")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("自定义主题将在眠屿 Watch App 主页展示，按当前恢复状态切换对应形象。")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    // MARK: - 底部操作

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                renderAndShare()
            } label: {
                Text("分享")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: "EAF4F0"), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRenderingShareCard)

            Button {
                useTheme()
            } label: {
                Text("立即使用")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.Colors.mintGreen, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func useTheme() {
        customThemeStore.useTheme(theme)
        useNotice = customThemeStore.lastSyncNotice ?? "主题已开始同步到手表"
    }

    // MARK: - 分享卡

    private func renderAndShare() {
        isRenderingShareCard = true
        Task {
            let renderer = ImageRenderer(
                content: WatchThemeShareCard(theme: theme)
                    .frame(width: 390, height: 560)
                    .background(Theme.Colors.surface)
            )
            renderer.scale = 3
            renderer.isOpaque = true
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("watch-theme-\(theme.id).png")
            if let image = renderer.uiImage,
               let data = image.pngData() {
                try? data.write(to: url, options: .atomic)
                shareURL = url
                showShareSheet = true
            } else {
                useNotice = "分享卡生成失败，请重试"
            }
            await MainActor.run { isRenderingShareCard = false }
        }
    }
}

/// WatchThemeShareCard 是分享卡片视图（含四状态缩略图）。
struct WatchThemeShareCard: View {
    let theme: CustomWatchTheme

    var body: some View {
        VStack(spacing: 20) {
            Text("我用眠屿创建了专属 Watch 主题")
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            WatchThemeWatchPreview(content: .custom(theme, slot: .normal), width: 150)

            Text(theme.name)
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: 14) {
                ForEach(WatchThemeSlot.allCases) { slot in
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(hex: "F5F6F5"))
                                .frame(width: 64, height: 64)
                            if let media = theme.slots[slot],
                               let image = UIImage(contentsOfFile: WatchCustomThemeFileStore.slotFileURL(
                                    themeId: theme.id,
                                    slot: slot,
                                    fileExtension: media.fileExtension
                               ).path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(6)
                            }
                        }
                        Text(slot.displayTitle)
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }

            Text("眠屿 Mianyu · Watch 主题")
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(28)
    }
}

/// ShareCardActivitySheet 包装系统分享面板。
private struct ShareCardActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
