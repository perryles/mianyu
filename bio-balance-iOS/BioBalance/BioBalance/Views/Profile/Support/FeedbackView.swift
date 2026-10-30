import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FeedbackView: View {
    @Environment(\.openURL) private var openURL
    @State private var type: FeedbackType
    @State private var message = ""
    @State private var contact = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachments: [FeedbackAttachment] = []
    @State private var isLoadingAttachments = false
    @State private var isSubmitting = false
    @State private var mailDraft: MailDraft?
    @State private var fallbackDraft: MailDraft?
    @State private var showingMailFallback = false
    @State private var notice: FeedbackNotice?

    private let service: any FeedbackService

    init(initialType: FeedbackType = .issue, service: any FeedbackService = MailFeedbackService()) {
        _type = State(initialValue: initialType)
        self.service = service
    }

    var body: some View {
        MianyuPage(title: "提交反馈") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuHeroCard(
                        eyebrow: String(localized: "反馈给眠屿"),
                        title: String(localized: "你的描述，会直接帮助我们改进"),
                        detail: String(localized: "建议写清楚出现时间、实际现象和你期待的结果。"),
                        eyebrowFontSize: 14,
                        titleFontSize: 24,
                        detailFontSize: 14
                    )

                    MianyuSectionTitle(title: "反馈类型", bottomSpacing: -10)
                    typePicker

                    MianyuSectionTitle(title: "问题描述", bottomSpacing: -10)
                    messageCard

                    MianyuSectionTitle(title: "补充信息", bottomSpacing: -10)
                    attachmentCard

                    MianyuPrimaryButton(
                        "提交反馈",
                        isLoading: isSubmitting,
                        isEnabled: !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        submit()
                    }

                    Text("提交即表示你同意仅将这些信息用于问题定位与回复。")
                        .font(.appSystem(size: 13, weight: .regular))
                        .foregroundStyle(MianyuSupportPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: message) { _, value in
            if value.count > 1000 { message = String(value.prefix(1000)) }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            loadAttachments(from: items)
        }
        .sheet(item: $mailDraft) { draft in
            MailComposer(draft: draft) { result in
                handleMailResult(result)
            }
        }
        .confirmationDialog(
            "此设备尚未配置系统邮件账户",
            isPresented: $showingMailFallback,
            titleVisibility: .visible
        ) {
            Button("使用其他邮件应用") { openFallbackMail() }
            Button("复制邮箱地址") {
                MailFallback.copySupportAddress()
                notice = .init(title: String(localized: "邮箱已复制"), message: ProfileExternalLinks.emailAddress)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你仍可复制邮箱，或使用设备上可处理 mailto 链接的邮件应用。附件需要在邮件应用中重新添加。")
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    private var typePicker: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackType.allCases) { item in
                MianyuSelectionChip(
                    title: item.title,
                    isSelected: type == item,
                    tint: tint(for: item),
                    background: background(for: item),
                    fontSize: 12
                ) { type = item }
            }
        }
    }

    private var messageCard: some View {
        MianyuCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("尽量描述发生了什么、你做了什么、结果是什么。")
                    .font(.appSystem(size: 14, weight: .regular))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                MianyuTextEditor(
                    prompt: "例如：昨晚睡眠数据同步后，深睡时长显示异常……",
                    text: $message,
                    minimumHeight: 92
                )
                Text("\(message.count)/1000")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("已输入 \(message.count) 个字符，最多 1000 个字符")
            }
            .padding(17)
        }
    }

    private var attachmentCard: some View {
        MianyuCard {
            VStack(alignment: .leading, spacing: 13) {
                let pickerLabel = FeedbackAttachmentPickerLabel(isLoading: isLoadingAttachments)
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 5,
                    selectionBehavior: .ordered,
                    matching: .images
                ) {
                    pickerLabel
                }
                .disabled(isLoadingAttachments)
                .accessibilityHint("最多选择 5 张图片")

                Text("最多 5 张图片。当前项目没有录屏附件上传接口。")
                    .font(.appSystem(size: 13, weight: .regular))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)

                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(attachments) { attachment in
                                attachmentPreview(attachment)
                            }
                        }
                    }
                    .accessibilityLabel("已添加 \(attachments.count) 张图片")
                }

                HStack(spacing: 10) {
                    Text("联系方式（可选）")
                        .font(.appSystem(size: 14, weight: .bold))
                        .foregroundStyle(MianyuSupportPalette.primaryText)
                    TextField("邮箱 / 手机号", text: $contact)
                        .font(.appSystem(size: 14, weight: .regular))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(MianyuSupportPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
                }
            }
            .padding(17)
        }
    }

    private func attachmentPreview(_ attachment: FeedbackAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                attachments.removeAll { $0.id == attachment.id }
                selectedPhotoItems = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, Color.black.opacity(0.58))
                    .font(.appSystem(size: 18, weight: .bold))
            }
            .offset(x: 5, y: -5)
            .accessibilityLabel("移除图片")
        }
    }

    private func tint(for type: FeedbackType) -> Color {
        switch type {
        case .issue: MianyuSupportPalette.blue
        case .feature: MianyuSupportPalette.orange
        case .accountData: MianyuSupportPalette.green
        }
    }

    private func background(for type: FeedbackType) -> Color {
        switch type {
        case .issue: MianyuSupportPalette.paleBlue
        case .feature: MianyuSupportPalette.paleOrange
        case .accountData: MianyuSupportPalette.mint
        }
    }

    private func loadAttachments(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingAttachments = true
        Task { @MainActor in
            do {
                var loaded: [FeedbackAttachment] = []
                for (index, item) in items.prefix(5).enumerated() {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw FeedbackAttachmentLoadError.unreadable
                    }
                    let contentType = item.supportedContentTypes.first ?? .jpeg
                    let fileExtension = contentType.preferredFilenameExtension ?? "jpg"
                    loaded.append(
                        FeedbackAttachment(
                            data: data,
                            mimeType: contentType.preferredMIMEType ?? "image/jpeg",
                            fileName: "feedback-\(index + 1).\(fileExtension)"
                        )
                    )
                }
                attachments = loaded
            } catch {
                selectedPhotoItems = []
                attachments = []
                notice = .init(
                    title: String(localized: "无法添加附件"),
                    message: String(localized: "请确认照片仍可访问，然后重新选择。")
                )
            }
            isLoadingAttachments = false
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            do {
                let draft = try await service.prepareSubmission(
                    FeedbackRequest(type: type, message: message, contact: contact, attachments: attachments)
                )
                isSubmitting = false
                if MailComposer.canSendMail {
                    mailDraft = draft
                } else {
                    fallbackDraft = draft
                    showingMailFallback = true
                }
            } catch {
                isSubmitting = false
                notice = .init(title: String(localized: "无法提交反馈"), message: error.localizedDescription)
            }
        }
    }

    private func openFallbackMail() {
        guard let url = fallbackDraft?.mailtoURL else {
            notice = .init(title: String(localized: "无法打开邮件"), message: String(localized: "请复制邮箱地址后手动联系眠屿。"))
            return
        }
        openURL(url) { accepted in
            if accepted {
                notice = .init(title: String(localized: "邮件草稿已打开"), message: String(localized: "请在邮件应用中确认发送；附件需要重新添加。"))
            } else {
                notice = .init(title: String(localized: "无法打开邮件"), message: String(localized: "请复制邮箱地址后手动联系眠屿。"))
            }
        }
    }

    private func handleMailResult(_ result: MailComposerResult) {
        mailDraft = nil
        switch result {
        case .sent:
            message = ""
            contact = ""
            attachments = []
            selectedPhotoItems = []
            notice = .init(title: String(localized: "反馈已发送"), message: String(localized: "谢谢你，我们通常会在 1–3 个工作日内回复。"))
        case .saved:
            notice = .init(title: String(localized: "草稿已保存"), message: String(localized: "你可以稍后在邮件应用中继续发送。"))
        case .cancelled:
            break
        case .failed(let error):
            notice = .init(title: String(localized: "发送失败"), message: error?.localizedDescription ?? String(localized: "请检查网络或邮件账户后重试。"))
        }
    }
}

nonisolated private struct FeedbackAttachmentPickerLabel: View, Sendable {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().tint(MianyuSupportPalette.green)
            } else {
                Image(systemName: "plus")
            }
            Text("添加截图")
        }
        .font(.appSystem(size: 15, weight: .bold))
        .foregroundStyle(MianyuSupportPalette.green)
    }
}

private struct FeedbackNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum FeedbackAttachmentLoadError: Error {
    case unreadable
}

#Preview {
    NavigationStack { FeedbackView(initialType: .feature) }
}
