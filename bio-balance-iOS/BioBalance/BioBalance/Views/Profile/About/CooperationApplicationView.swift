import SwiftUI

struct CooperationApplicationView: View {
    @Environment(\.openURL) private var openURL
    @State private var application: CooperationApplication
    @State private var isSubmitting = false
    @State private var mailDraft: MailDraft?
    @State private var fallbackDraft: MailDraft?
    @State private var showingMailFallback = false
    @State private var notice: CooperationNotice?

    private let service: any CooperationService

    init(
        cooperationType: CooperationType = .general,
        service: any CooperationService = MailCooperationService()
    ) {
        _application = State(initialValue: CooperationApplication(cooperationType: cooperationType))
        self.service = service
    }

    var body: some View {
        MianyuPage(title: "合作申请") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuHeroCard(
                        eyebrow: application.cooperationType.title,
                        title: String(localized: "先了解彼此，再决定怎么一起做"),
                        detail: String(localized: "通常会在 1–3 个工作日内回复。"),
                        tint: MianyuSupportPalette.coral,
                        background: MianyuSupportPalette.paleCoral,
                        eyebrowFontSize: 14,
                        titleFontSize: 24,
                        detailFontSize: 14
                    )

                    MianyuSectionTitle(title: "合作身份", bottomSpacing: -10)
                    identityPicker

                    MianyuSectionTitle(title: "基本信息", bottomSpacing: -10)
                    basicInformationCard

                    MianyuSectionTitle(title: "合作想法", bottomSpacing: -10)
                    ideaCard

                    MianyuPrimaryButton(
                        "提交合作申请",
                        isLoading: isSubmitting,
                        isEnabled: isFormReady
                    ) { submit() }

                    Text("提交后，我们只会将信息用于合作沟通。")
                        .font(.appSystem(size: 13, weight: .regular))
                        .foregroundStyle(MianyuSupportPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $mailDraft) { draft in
            MailComposer(draft: draft) { result in handleMailResult(result) }
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
            Text("合作申请将通过邮件发送。你也可以复制邮箱后手动联系我们。")
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了")))
        }
    }

    private var identityPicker: some View {
        HStack(spacing: 8) {
            ForEach(CooperationIdentity.allCases) { identity in
                MianyuSelectionChip(
                    title: identity.title,
                    isSelected: application.identity == identity,
                    tint: MianyuSupportPalette.green,
                    background: Color(hex: "F4F6F8"),
                    fontSize: 12
                ) { application.identity = identity }
            }
        }
    }

    private var basicInformationCard: some View {
        MianyuCard {
            VStack(spacing: 8) {
                formRow(title: String(localized: "称呼"), prompt: String(localized: "你的姓名或称呼"), text: $application.name)
                formRow(title: String(localized: "品牌 / 机构"), prompt: String(localized: "可填写品牌、团队或社区名称"), text: $application.organization)
                formRow(title: String(localized: "联系方式"), prompt: String(localized: "邮箱、微信或手机号"), text: $application.contact)
            }
            .padding(15)
        }
    }

    private func formRow(title: String, prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundStyle(MianyuSupportPalette.primaryText)
                .frame(width: 82, alignment: .leading)
            TextField(prompt, text: text)
                .font(.appSystem(size: 14, weight: .regular))
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(MianyuSupportPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
        }
    }

    private var ideaCard: some View {
        MianyuCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("简单说说你想做什么，以及希望眠屿参与什么。")
                    .font(.appSystem(size: 14, weight: .regular))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                MianyuTextEditor(
                    prompt: "例如：联合做一次睡眠主题内容活动……",
                    text: $application.idea,
                    minimumHeight: 68
                )
            }
            .padding(15)
        }
    }

    private var isFormReady: Bool {
        !application.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !application.contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !application.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            do {
                let draft = try await service.prepareSubmission(application)
                isSubmitting = false
                if MailComposer.canSendMail {
                    mailDraft = draft
                } else {
                    fallbackDraft = draft
                    showingMailFallback = true
                }
            } catch {
                isSubmitting = false
                notice = .init(title: String(localized: "无法提交申请"), message: error.localizedDescription)
            }
        }
    }

    private func openFallbackMail() {
        guard let url = fallbackDraft?.mailtoURL else { return }
        openURL(url) { accepted in
            if accepted {
                notice = .init(title: String(localized: "邮件草稿已打开"), message: String(localized: "请在邮件应用中确认发送。"))
            } else {
                notice = .init(title: String(localized: "无法打开邮件"), message: String(localized: "请复制邮箱地址后手动联系眠屿。"))
            }
        }
    }

    private func handleMailResult(_ result: MailComposerResult) {
        mailDraft = nil
        switch result {
        case .sent:
            application = CooperationApplication(cooperationType: application.cooperationType)
            notice = .init(title: String(localized: "合作申请已发送"), message: String(localized: "谢谢你，我们通常会在 1–3 个工作日内回复。"))
        case .saved:
            notice = .init(title: String(localized: "草稿已保存"), message: String(localized: "你可以稍后在邮件应用中继续发送。"))
        case .cancelled:
            break
        case .failed(let error):
            notice = .init(title: String(localized: "发送失败"), message: error?.localizedDescription ?? String(localized: "请检查网络或邮件账户后重试。"))
        }
    }
}

private struct CooperationNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    NavigationStack { CooperationApplicationView(cooperationType: .brand) }
}
