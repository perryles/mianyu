import SwiftUI

nonisolated enum ProfileBusinessContactChannel: CaseIterable, Hashable {
    case email
    case xiaohongshu
}


struct BusinessCooperationView: View {
    @Environment(\.openURL) private var openURL
    @State private var mailDraft: MailDraft?
    @State private var fallbackDraft: MailDraft?
    @State private var showingMailFallback = false
    @State private var notice: BusinessNotice?

    var body: some View {
        MianyuPage(title: "商务与合作") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    hero

                    MianyuSectionTitle(title: "联系方式", bottomSpacing: -10)
                    contactCard

                    MianyuSectionTitle(title: "合作方式", bottomSpacing: -10)
                    cooperationCard

                    CooperationSupportCard(
                        title: String(localized: "先聊方向，再确认适合彼此的合作方式。"),
                        detail: "",
                        titleFontSize: 15
                    )
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
        .confirmationDialog("此设备尚未配置系统邮件账户", isPresented: $showingMailFallback, titleVisibility: .visible) {
            Button("使用其他邮件应用") { openFallbackMail() }
            Button("复制邮箱地址") {
                MailFallback.copySupportAddress()
                notice = .init(title: String(localized: "邮箱已复制"), message: ProfileExternalLinks.emailAddress)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你仍可复制邮箱，或使用设备上可处理 mailto 链接的邮件应用。")
        }
        .alert(item: $notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("知道了")))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("合作伙伴")
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundStyle(MianyuSupportPalette.coral)
            Text("一起做点有价值的事")
                .font(.appSystem(size: 24, weight: .bold))
                .foregroundStyle(MianyuSupportPalette.primaryText)
            Text("欢迎创作者、品牌与社区伙伴，和眠屿一起让健康理解更自然。")
                .font(.appSystem(size: 14, weight: .regular))
                .foregroundStyle(MianyuSupportPalette.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { CooperationApplicationView(cooperationType: .general) } label: {
                Label("聊聊合作", systemImage: "envelope.fill")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(MianyuSupportPalette.green, in: Capsule())
            }
            .buttonStyle(MianyuPressButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(MianyuSupportPalette.paleCoral, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 7, y: 4)
    }

    private var contactCard: some View {
        MianyuCard {
            VStack(spacing: 0) {
                Button { openSupportMail() } label: {
                    MianyuInfoRow(
                        title: String(localized: "邮箱"),
                        detail: ProfileExternalLinks.emailAddress,
                        symbol: "envelope.fill",
                        tint: MianyuSupportPalette.green,
                        showsChevron: true,
                        titleFontSize: 16,
                        detailFontSize: 14
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 59)
                Link(destination: ProfileExternalLinks.xiaohongshu) {
                    MianyuInfoRow(
                        title: String(localized: "小红书"),
                        detail: String(localized: "眠屿"),
                        symbol: "heart.fill",
                        tint: Color(hex: "E84C6A"),
                        showsChevron: true,
                        titleFontSize: 16,
                        detailFontSize: 14
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cooperationCard: some View {
        MianyuCard {
            VStack(spacing: 0) {
                NavigationLink { ContentCollaborationView() } label: {
                    MianyuInfoRow(title: String(localized: "内容共创"), detail: String(localized: "一起做有价值的健康内容"), symbol: "sparkles", showsChevron: true, titleFontSize: 16, detailFontSize: 14)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 59)
                NavigationLink { BrandCollaborationView() } label: {
                    MianyuInfoRow(title: String(localized: "品牌联名"), detail: String(localized: "共同探索产品与品牌合作"), symbol: "diamond", tint: MianyuSupportPalette.orange, showsChevron: true, titleFontSize: 16, detailFontSize: 14)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 59)
                NavigationLink { CommunityPartnerView() } label: {
                    MianyuInfoRow(title: String(localized: "社区伙伴"), detail: String(localized: "与社区、活动和创作者建立连接"), symbol: "circle.circle", tint: Color(hex: "656FFF"), showsChevron: true, titleFontSize: 16, detailFontSize: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openSupportMail() {
        let draft = MailDraft(
            recipients: [ProfileExternalLinks.emailAddress],
            subject: String(localized: "眠屿 · 商务与合作"),
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

private struct BusinessNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    NavigationStack { BusinessCooperationView() }
}
