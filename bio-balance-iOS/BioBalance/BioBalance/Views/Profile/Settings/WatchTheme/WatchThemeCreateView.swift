/// WatchThemeCreateView 承载「创建主题」：主题名称 + 四个状态素材上传（图片 / gif / live图 / 视频，最长5秒），
/// 静态图支持去除背景；顶部提供手表实时预览。
import SwiftUI
import PhotosUI

/// WatchThemeSlotDraft 是单个槽位的编辑态草稿。
struct WatchThemeSlotDraft: Identifiable {
    let id: WatchThemeSlot
    var media: WatchThemePickedMedia?
    var isProcessing = false
    var processedPreview: UIImage?
    var errorMessage: String?
}

/// WatchThemeCreateView 负责创建主题页的交互与素材处理编排。
struct WatchThemeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var themeName = ""
    @State private var drafts: [WatchThemeSlot: WatchThemeSlotDraft]
    @State private var pickerSlot: WatchThemeSlot?
    @State private var pickedItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    private let allSlots = WatchThemeSlot.allCases

    init() {
        _drafts = State(initialValue: Dictionary(
            uniqueKeysWithValues: WatchThemeSlot.allCases.map { ($0, WatchThemeSlotDraft(id: $0)) }
        ))
    }

    /// 至少上传一个素材才可保存。
    private var canSave: Bool {
        !WatchCustomThemePolicy.normalizedThemeName(themeName).isEmpty
            && drafts.values.contains { $0.processedPreview != nil || $0.media != nil }
            && !isSaving
    }

    var body: some View {
        ZStack {
            ReportsSoftBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    watchPreviewCard
                    nameCard
                    uploadCard
                    saveButton
                }
                .padding(.horizontal, Theme.Layout.padding)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("创建主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .photosPicker(
            isPresented: Binding(
                get: { pickerSlot != nil },
                set: { if !$0 { pickerSlot = nil } }
            ),
            selection: $pickedItem,
            matching: .any(of: [.images, .livePhotos, .videos])
        )
        .onChange(of: pickedItem) { _, item in
            guard let slot = pickerSlot else { return }
            pickerSlot = nil
            pickedItem = nil
            guard let item else { return }
            load(item: item, slot: slot)
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - 预览

    private var watchPreviewCard: some View {
        VStack(spacing: 12) {
            WatchThemeWatchPreview(
                content: .custom(draftTheme, slot: .normal),
                width: 140
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    /// 把当前草稿映射为预览用临时主题（不落盘）。
    private var draftTheme: CustomWatchTheme {
        var slots: [WatchThemeSlot: WatchThemeSlotMedia] = [:]
        for (slot, draft) in drafts {
            if let media = draft.media {
                slots[slot] = WatchThemeSlotMedia(
                    slot: slot,
                    fileExtension: media.kind == .animated ? "gif" : "png",
                    isAnimated: media.kind == .animated,
                    fileSize: 0
                )
            }
        }
        return CustomWatchTheme(
            id: "draft",
            name: WatchCustomThemePolicy.normalizedThemeName(themeName),
            slots: slots
        )
    }

    // MARK: - 名称

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主题名称")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            TextField("给主题起个名字", text: $themeName)
                .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .submitLabel(.done)
                .onChange(of: themeName) { _, value in
                    let limited = String(value.prefix(WatchCustomThemePolicy.maximumNameLength))
                    if limited != value { themeName = limited }
                }
        }
        .padding(18)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        }
    }

    // MARK: - 素材上传

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("上传素材")
                .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Text("支持图片、gif、live图、视频，最长5秒")
                .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                ForEach(allSlots) { slot in
                    slotCell(slot)
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

    private func slotCell(_ slot: WatchThemeSlot) -> some View {
        let draft = drafts[slot] ?? WatchThemeSlotDraft(id: slot)
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: "F5F6F5"))
                    .frame(height: 120)

                if draft.isProcessing {
                    ProgressView()
                } else if let preview = draft.processedPreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    Image(systemName: "plus")
                        .font(.appSystem(size: 22, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                if draft.media != nil || draft.processedPreview != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                removeMedia(slot)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.appSystem(size: 18, weight: .bold))
                                    .foregroundStyle(.white, Color.black.opacity(0.45))
                            }
                            .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 120)
            .contentShape(Rectangle())
            .onTapGesture {
                if draft.media == nil && !draft.isProcessing {
                    pickerSlot = slot
                }
            }

            Text(slot.displayTitle)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            // 去除背景仅对静态图开放。
            if let media = draft.media, media.kind == .staticImage {
                Button {
                    toggleRemoveBackground(slot)
                } label: {
                    Text("去除背景")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(draft.media?.removeBackground == true ? .white : Theme.Colors.mintGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            (draft.media?.removeBackground == true ? Theme.Colors.mintGreen : Theme.Colors.mintGreen.opacity(0.12)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.isProcessing)
            }

            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "F05275"))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - 素材处理

    private func load(item: PhotosPickerItem, slot: WatchThemeSlot) {
        drafts[slot]?.isProcessing = true
        drafts[slot]?.errorMessage = nil
        Task {
            guard let media = await WatchThemeMediaPipeline.load(item: item) else {
                await MainActor.run {
                    drafts[slot]?.isProcessing = false
                    drafts[slot]?.errorMessage = "素材加载失败，请换个文件试试"
                }
                return
            }
            await apply(media: media, slot: slot, removeBackground: false)
        }
    }

    private func toggleRemoveBackground(_ slot: WatchThemeSlot) {
        guard var media = drafts[slot]?.media, media.kind == .staticImage else { return }
        media.removeBackground.toggle()
        drafts[slot]?.isProcessing = true
        Task {
            await apply(media: media, slot: slot, removeBackground: media.removeBackground)
        }
    }

    private func apply(media: WatchThemePickedMedia, slot: WatchThemeSlot, removeBackground: Bool) async {
        var updated = media
        updated.removeBackground = removeBackground

        // 预览图：静态图直接处理缩放，动图取首帧。
        var preview: UIImage?
        var processingError: String?
        do {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WatchThemeDraft", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let processed = try await WatchThemeMediaPipeline.process(
                media: updated,
                slot: slot,
                themeDirectory: tempDirectory
            )
            if let data = try? Data(contentsOf: tempDirectory.appendingPathComponent("\(slot.rawValue).\(processed.fileExtension)")) {
                preview = UIImage(data: data)
            }
            drafts[slot]?.media = updated
        } catch {
            processingError = "素材处理失败，请换个文件试试"
        }

        await MainActor.run {
            drafts[slot]?.isProcessing = false
            drafts[slot]?.processedPreview = preview
            if let processingError {
                drafts[slot]?.errorMessage = processingError
            }
        }
    }

    private func removeMedia(_ slot: WatchThemeSlot) {
        drafts[slot] = WatchThemeSlotDraft(id: slot)
    }

    // MARK: - 保存

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                }
                Text("保存主题")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundColor(.white)
            .background(
                canSave ? Theme.Colors.mintGreen : Theme.Colors.mintGreen.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private func save() {
        let name = WatchCustomThemePolicy.normalizedThemeName(themeName)
        guard !name.isEmpty else { return }
        isSaving = true

        Task {
            var slots: [WatchThemeSlot: WatchThemeSlotMedia] = [:]
            do {
                let theme = WatchCustomThemeStore.shared.createTheme(name: name, slots: [:])
                let directory = WatchCustomThemeFileStore.themeDirectory(themeId: theme.id)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                for (slot, draft) in drafts {
                    guard let media = draft.media else { continue }
                    let processed = try await WatchThemeMediaPipeline.process(
                        media: media,
                        slot: slot,
                        themeDirectory: directory
                    )
                    slots[slot] = processed
                }
                guard !slots.isEmpty else {
                    throw WatchThemeMediaError.encodingFailed
                }

                var saved = theme
                saved.slots = slots
                WatchCustomThemeStore.shared.updateTheme(saved)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveErrorMessage = "保存失败，请重试"
                }
            }
        }
    }
}
