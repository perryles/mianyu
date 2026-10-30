import SwiftUI

struct HelpFeedbackView: View {
    @Environment(\.openURL) private var openURL
    @State private var selectedType: FeedbackType = .issue
    @State private var mailDraft: MailDraft?
    @State private var fallbackDraft: MailDraft?
    @State private var showingMailFallback = false
    @State private var notice: HelpNotice?

    var body: some View {
        MianyuPage(title: "帮助与反馈") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    NavigationLink { FAQListView() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.appSystem(size: 14, weight: .bold))
                            Text("搜索常见问题")
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(MianyuSupportPalette.secondaryText)
                            Spacer()
                            Text("查看全部")
                                .font(Theme.Typography.captionBold)
                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: 12, weight: .bold))
                        }
                        .foregroundStyle(MianyuSupportPalette.green)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 7, y: 4)
                    }
                    .buttonStyle(MianyuPressButtonStyle())

                    MianyuSectionTitle(title: "快速支持", bottomSpacing: -10)
                    HStack(spacing: 16) {
                        supportCard(
                            title: String(localized: "邮件支持"),
                            detail: String(localized: "直接联系我们"),
                            symbol: "envelope.fill",
                            tint: MianyuSupportPalette.green,
                            background: MianyuSupportPalette.paleMint
                        ) { openSupportMail() }

                        NavigationLink { FeedbackView(initialType: selectedType) } label: {
                            supportCardLabel(
                                title: String(localized: "提交反馈"),
                                detail: String(localized: "问题或新想法"),
                                symbol: "arrow.up.right",
                                tint: MianyuSupportPalette.violet,
                                background: MianyuSupportPalette.paleViolet
                            )
                        }
                        .buttonStyle(MianyuPressButtonStyle())
                    }

                    MianyuSectionTitle(title: "写给眠屿", bottomSpacing: -10)
                    quickFeedbackCard

                    NavigationLink { FAQListView() } label: {
                        MianyuInfoRow(
                            title: String(localized: "常见问题"),
                            detail: String(localized: "先看看有没有现成答案"),
                            symbol: "questionmark",
                            showsChevron: true,
                            titleFontSize: 16,
                            detailFontSize: 14
                        )
                    }
                    .buttonStyle(MianyuPressButtonStyle())
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 11, y: 8)

                    Text("通常会在 1–3 个工作日内回复你")
                        .font(.appSystem(size: 13, weight: .regular))
                        .foregroundStyle(MianyuSupportPalette.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $mailDraft) { draft in
            MailComposer(draft: draft) { result in
                mailDraft = nil
                switch result {
                case .sent:
                    notice = .init(title: String(localized: "邮件已发送"), message: String(localized: "谢谢你联系我们。"))
                case .saved:
                    notice = .init(title: String(localized: "草稿已保存"), message: String(localized: "你可以稍后在邮件应用中继续发送。"))
                case .cancelled:
                    break
                case .failed(let error):
                    notice = .init(title: String(localized: "发送失败"), message: error?.localizedDescription ?? String(localized: "请检查网络或邮件账户后重试。"))
                }
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
            Text("你仍可复制邮箱，或使用设备上可处理 mailto 链接的邮件应用。")
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了")))
        }
    }

    private var quickFeedbackCard: some View {
        MianyuCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("描述问题、实际现象和期待结果")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundStyle(MianyuSupportPalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("待填写")
                        .font(.appSystem(size: 12, weight: .bold))
                        .foregroundStyle(MianyuSupportPalette.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Theme.Colors.secondarySurface, in: Capsule())
                }

                Text("反馈主题")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)

                HStack(spacing: 8) {
                    ForEach(FeedbackType.allCases) { type in
                        MianyuSelectionChip(
                            title: type.title,
                            isSelected: selectedType == type,
                            tint: tint(for: type),
                            background: background(for: type),
                            fontSize: 12
                        ) { selectedType = type }
                    }
                }

                HStack {
                    Text("反馈内容")
                        .font(.appSystem(size: 14, weight: .bold))
                    Spacer()
                    Text("0/1000")
                        .font(.appSystem(size: 12, weight: .bold))
                }
                .foregroundStyle(MianyuSupportPalette.secondaryText)

                NavigationLink { FeedbackView(initialType: selectedType) } label: {
                    HStack {
                        Text("点击开始填写")
                            .font(.appSystem(size: 14, weight: .regular))
                            .foregroundStyle(Color(hex: "9AA4B1"))
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(MianyuSupportPalette.green)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 58)
                    .background(MianyuSupportPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
                }
                .buttonStyle(MianyuPressButtonStyle())
            }
            .padding(17)
        }
    }

    private func supportCard(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            supportCardLabel(title: title, detail: detail, symbol: symbol, tint: tint, background: background)
        }
        .buttonStyle(MianyuPressButtonStyle())
    }

    private func supportCardLabel(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        background: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.appSystem(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.surface, in: Circle())
            Spacer(minLength: 0)
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(MianyuSupportPalette.primaryText)
            HStack {
                Text(detail)
                    .font(Theme.Typography.supporting)
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 92)
        .padding(11)
        .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.05), radius: 11, y: 8)
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

    private func openSupportMail() {
        let draft = MailDraft(
            recipients: [ProfileExternalLinks.emailAddress],
            subject: String(localized: "眠屿 · 邮件支持"),
            body: "",
            attachments: []
        )
        if MailComposer.canSendMail {
            mailDraft = draft
        } else {
            fallbackDraft = draft
            showingMailFallback = true
        }
    }

    private func openFallbackMail() {
        guard let url = fallbackDraft?.mailtoURL else { return }
        openURL(url) { accepted in
            if !accepted {
                notice = .init(title: String(localized: "无法打开邮件"), message: String(localized: "请复制邮箱地址后手动联系眠屿。"))
            }
        }
    }
}

private struct HelpNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    NavigationStack { HelpFeedbackView() }
}
