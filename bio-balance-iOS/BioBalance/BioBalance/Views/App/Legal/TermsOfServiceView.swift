/// TermsOfServiceView 由设置页与登录页调用，作为「服务条款」法律说明页。
/// 负责分段展示服务说明、账号责任、使用规则等合规条款内容。

import SwiftUI

/// 服务条款视图 由上级页面或路由调用，作为法律说明模块里的界面或内容组件。
/// 负责展示隐私政策、服务条款等合规内容。
struct TermsOfServiceView: View {
    private let sections: [LegalDocumentSection] = [
        LegalDocumentSection(
            title: String(localized: "1. 服务说明"),
            body: String(localized: "眠屿 提供健康摘要、趋势分析、习惯记录、提醒、AI 健康问答、好友共享、协作内容与可能的会员能力。不同版本、地区、设备和系统条件下，可用功能可能不同。"),
            icon: "sparkles.rectangle.stack.fill",
            tone: .mint,
            highlights: [
                String(localized: "部分能力依赖 Apple Health / HealthKit、iCloud、网络连接、后端服务或第三方平台。"),
                String(localized: "我们可以基于稳定性、安全性、合规或产品规划对功能进行新增、调整、暂停或下线。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "2. 使用资格与账号责任"),
            body: String(localized: "你应在具备相应民事行为能力，且遵守适用法律法规的前提下使用本应用。若你使用登录、同步或共享功能，你应妥善保管账号、设备和验证方式，并对自己账号下的活动负责。"),
            icon: "person.crop.circle.badge.checkmark",
            tone: .blue,
            highlights: [
                String(localized: "请勿冒用他人身份、绕过安全机制或滥用共享/协作能力。"),
                String(localized: "如发现未授权使用、账号异常或设备丢失，请及时采取退出登录、修改设置等措施。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "3. 合理使用规则"),
            body: String(localized: "你同意仅以合法、善意和符合产品设计目的的方式使用本服务，不得从事违法、侵权、破坏性、欺诈性或影响他人正常使用的行为。"),
            icon: "checklist.checked",
            tone: .green,
            highlights: [
                String(localized: "不得尝试反向工程、扫描漏洞、批量抓取、干扰服务器或规避付费/权限控制。"),
                String(localized: "不得利用应用传播违法信息、骚扰他人，或未经同意共享他人隐私与健康信息。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "4. 健康与 AI 免责声明"),
            body: String(localized: "应用内的健康评分、趋势、提醒、建议、AI 回答和可视化内容，仅用于一般健康管理、习惯追踪和信息参考，不构成医疗意见、诊断、治疗建议或急救指引。"),
            icon: "cross.case.fill",
            tone: .orange,
            highlights: [
                String(localized: "如你出现胸痛、呼吸困难、持续异常指标、心理危机或其他紧急情况，请立即联系医生或当地急救服务。"),
                String(localized: "AI 内容可能存在不准确、过时、遗漏或不适用于你个人情况的风险。"),
                String(localized: "任何重要健康决定都不应仅依据本应用作出。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "5. 订阅、购买与恢复"),
            body: String(localized: "若应用当前或未来提供会员、自动续订订阅或一次性购买项目，相关价格、权益、试用、账单与税费以购买页面、App Store 展示和 Apple 的结算规则为准。"),
            icon: "creditcard.fill",
            tone: .blue,
            highlights: [
                String(localized: "自动续订订阅通常会通过你的 Apple ID 扣款，除非你在当前周期结束前至少 24 小时取消。"),
                String(localized: "购买后可在 App Store 订阅设置中管理、取消或恢复购买。"),
                String(localized: "一次性购买项目通常不会自动续订，但具体权益和可用设备范围仍以购买说明为准。")
            ],
            footnote: String(localized: "如果当前版本临时开放了部分原会员能力，不代表未来一定永久免费，也不影响后续产品定价策略调整。")
        ),
        LegalDocumentSection(
            title: String(localized: "6. 第三方服务与系统能力"),
            body: String(localized: "本应用可能接入 Apple 登录、Apple Health、StoreKit、iCloud / CloudKit、定位、天气服务、云端 AI 服务或应用后端。你使用这些能力时，还应同时遵守对应第三方平台的条款、隐私政策和系统规则。"),
            icon: "link.circle.fill",
            tone: .mint,
            highlights: [
                String(localized: "第三方服务中断、限制、收费变化、账号异常或政策调整，可能影响应用部分功能。"),
                String(localized: "对于第三方平台自身造成的不可用、计费或数据问题，我们会尽力协助，但无法替代该平台承担其本应承担的责任。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "7. 知识产权与反馈"),
            body: String(localized: "除依法属于用户或第三方的内容外，应用界面、文案、设计、代码、图表组织方式与相关标识通常受知识产权法律保护。未经许可，你不得复制、修改、分发、出售或创建衍生作品。"),
            icon: "signature",
            tone: .green,
            highlights: [
                String(localized: "你向我们提交的建议、反馈或问题报告，可被我们用于修复、优化和迭代产品。"),
                String(localized: "但这并不当然转移你依法享有的个人信息或法定权利。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "8. 服务变更、中断与终止"),
            body: String(localized: "我们可能因维护、升级、合规要求、设备兼容性变化、网络问题、第三方依赖故障或不可抗力，导致服务暂时中断、响应延迟或部分能力不可用。我们也可能在合理情况下限制、暂停或终止违规账号的使用权。"),
            icon: "arrow.triangle.2.circlepath.circle.fill",
            tone: .orange,
            highlights: [
                String(localized: "我们会尽量降低中断影响，但无法保证服务始终无错误、无延迟或永久可用。"),
                String(localized: "若你停止使用本应用、删除应用或删除账号，部分本地或云端数据可能随之不可恢复。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "9. 责任限制"),
            body: String(localized: "在适用法律允许的范围内，对于因你对应用内容的理解、依赖、误操作、第三方服务故障、网络中断、设备兼容性问题或不可抗力导致的损失，我们的责任将以法律允许的最大范围进行限制。"),
            icon: "exclamationmark.triangle.fill",
            tone: .red,
            highlights: [
                String(localized: "本条不影响法律法规明确规定不得排除或限制的消费者权利。"),
                String(localized: "如果适用法律要求更高标准，则以该法律要求为准。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "10. 账户管理与删除"),
            body: String(localized: "你可以通过应用内设置管理你的账户。如你决定停止使用本服务，可随时删除应用。如你已创建账号或开启了 iCloud 同步，可通过以下方式删除关联数据。"),
            icon: "person.crop.circle.badge.xmark",
            tone: .blue,
            highlights: [
                String(localized: "删除应用会清除设备本地的全部数据（包括本地缓存和偏好设置）。"),
                String(localized: "如需删除 iCloud 中已同步的健康记录，请在应用内关闭对应同步开关，并通过 iCloud 存储管理或联系客服清理云端数据。"),
                String(localized: "账号删除请求可通过应用内反馈或 support@boundesu.com 提出；处理完成后，与你关联的可删除数据将在合理时间内清除。"),
                String(localized: "法律法规要求保留的日志信息（不含健康内容或个人文本）可能保留至法定期限届满。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "11. 用户内容"),
            body: String(localized: "你在使用应用过程中主动输入、上传或分享的内容（如健康备注、AI 对话文本、好友协作内容、反馈信息等）均由你自行负责。你应确保所提交的内容不违反法律法规或侵犯第三方权利。"),
            icon: "text.bubble.fill",
            tone: .green,
            highlights: [
                String(localized: "你不应在应用中输入或传播违法、有害、骚扰、诽谤或侵犯他人隐私的内容。"),
                String(localized: "对于你提交的反馈或建议，你授予我们非排他性、免费、全球范围的使用许可，用于产品改进。"),
                String(localized: "你的健康数据和个人输入内容不属于上述反馈许可范围，仍受隐私政策保护。"),
                String(localized: "如发现你提交的内容违反本条款，我们有权删除相关内容或限制相关功能。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "12. 订阅细则"),
            body: String(localized: "关于自动续订订阅和一次性购买的详细规则，以 App Store 购买页面展示的信息为准。以下为补充说明。"),
            icon: "creditcard.fill",
            tone: .orange,
            highlights: [
                String(localized: "自动续订订阅会在每个计费周期到期前 24 小时内自动扣款，除非你在到期前至少 24 小时在 App Store 订阅设置中取消。"),
                String(localized: "已购买的订阅在当前计费周期内继续有效；取消后下一周期不再续费。"),
                String(localized: "试用期（如有）期间取消不会扣款；试用期结束后未取消将自动转为付费订阅。"),
                String(localized: "家庭共享（如适用）以 App Store 展示的共享规则为准，部分订阅可能不支持家庭共享。"),
                String(localized: "退款请求需通过 Apple 报告问题页面（reportaproblem.apple.com）提交，应用方无权直接处理退款。"),
                String(localized: "恢复购买可用于在更换设备或重装应用后同步已有订阅状态。")
            ]
        ),
        LegalDocumentSection(
            title: String(localized: "13. 争议解决与适用法律"),
            body: String(localized: "本条款的解释、效力和争议解决均适用中华人民共和国法律（为本条款之目的，不包括中国香港、中国澳门和中国台湾地区的法律）。如发生争议，双方应首先通过友好协商解决。"),
            icon: "scalecube.fill",
            tone: .red,
            highlights: [
                String(localized: "协商不成的，任何一方均可向有管辖权的人民法院提起诉讼。"),
                String(localized: "如你在消费过程中作为消费者使用本服务，适用《消费者权益保护法》等相关法律法规赋予你的权利。"),
                String(localized: "本条款任何条款被认定为无效或不可执行，不影响其余条款的效力。")
            ],
            footnote: String(localized: "适用法律与管辖法院的约定不影响你作为消费者依法享有的法定权利。")
        ),
        LegalDocumentSection(
            title: String(localized: "14. 条款更新与联系"),
            body: String(localized: "我们可能根据产品变化、法律法规或服务安排更新本条款。更新后的版本会在应用内展示，并自展示或注明日期起生效。你继续使用服务，通常视为你已阅读并同意更新后的条款。"),
            icon: "envelope.fill",
            tone: .gray,
            highlights: [
                String(localized: "如果你不同意更新后的条款，请停止使用相关服务。"),
                String(localized: "如您对本服务条款有任何疑问，请查看下方联系方式。")
            ],
            footnote: String(localized: "联系我们：\nEmail：support@boundesu.com\n应用内：设置 → 帮助与反馈")
        )
    ]

    private let updatedSections: [LegalDocumentSection] = [
        LegalDocumentSection(title: String(localized: "接受与适用范围"), body: String(localized: "当你下载、安装、访问或使用眠屿，即表示你同意遵守本条款。不同版本、地区、系统或设备条件下，部分功能可能有所调整或暂不可用，具体以当前实际提供的版本为准。")),
        LegalDocumentSection(title: String(localized: "健康提示与免责声明"), body: String(localized: "眠屿提供睡眠、活动、压力、情绪、餐食和其他健康相关信息，用于帮助你理解自身数据与日常趋势。应用内的评分、分析、提醒和建议不构成医疗诊断、治疗方案或急救服务，也不能替代医生或其他专业医疗人员的判断。")),
        LegalDocumentSection(title: String(localized: "AI 内容与自动分析"), body: String(localized: "AI 生成的回答、总结和建议基于你主动提供的信息及已授权的数据，仅供健康管理和信息参考。AI 结果可能存在不完整、延迟或错误，不应作为医疗、药物、重大财务或其他高风险决策的唯一依据。")),
        LegalDocumentSection(title: String(localized: "订阅、购买与结算"), body: String(localized: "如你购买订阅或其他数字服务，付款、续订、取消和退款由 App Store 及 Apple 账户规则处理。你可以通过系统的订阅管理入口查看或取消订阅。订阅权益、价格和周期以购买页面实际展示的信息为准。")),
        LegalDocumentSection(title: String(localized: "账号、内容与使用规则"), body: String(localized: "你应妥善管理账号和设备访问权限，并对通过你的账号进行的操作负责。你主动记录、上传或分享的内容应合法、真实并具有相应授权，不得利用本应用从事违法、侵权、欺诈、骚扰或破坏服务稳定性的行为。")),
        LegalDocumentSection(title: String(localized: "第三方服务"), body: String(localized: "部分功能可能依赖 Apple HealthKit、iCloud、App Store 或其他第三方服务。第三方服务由其各自的服务条款和隐私规则约束，眠屿无法控制第三方服务的可用性、内容或政策变化。")),
        LegalDocumentSection(title: String(localized: "功能变更与服务可用性"), body: String(localized: "为了改进体验、安全性或适配系统变化，我们可能调整、增加、暂停或停止部分功能。不同设备、系统版本、网络条件和地区可能导致功能表现不同。")),
        LegalDocumentSection(title: String(localized: "账户删除与终止"), body: String(localized: "你可以按应用内提供的方式申请删除账户。若你严重违反本条款、法律法规或危害其他用户和服务安全，我们可能限制或终止相关功能。账户删除不会自动取消由 App Store 管理的有效订阅，请同时在 Apple 账户中处理。")),
        LegalDocumentSection(title: String(localized: "条款更新"), body: String(localized: "当功能、法律要求或服务方式发生变化时，我们可能更新本条款。更新后的版本会通过应用内页面或其他适当方式展示，并标明新的生效日期。")),
        LegalDocumentSection(title: String(localized: "适用规则"), body: String(localized: "本条款的解释和适用遵循适用的中国法律法规。若本条款某一部分被认定为无效或不可执行，不影响其他条款继续有效。"))
    ]

    var body: some View {
        LegalDocumentView(
            title: String(localized: "服务条款"),
            subtitle: String(localized: "把功能边界、风险提示和购买规则提前讲清楚。"),
            updatedAt: String(localized: "最后更新时间：2026-08-03"),
            intro: String(localized: "欢迎使用 眠屿。使用本应用前，请阅读以下条款，尤其是关于健康免责声明、AI 内容、订阅计费、账户管理、用户内容和第三方服务的部分。"),
            icon: "doc.text.fill",
            keyPoints: [
                String(localized: "健康建议不替代医生"),
                String(localized: "AI 回答仅供参考"),
                String(localized: "订阅由 Apple 结算"),
                String(localized: "第三方服务有独立规则")
            ],
            sections: updatedSections,
            sectionHeading: String(localized: "完整条款"),
            sectionCaption: String(localized: "继续使用代表你已阅读并同意"),
            closingTitle: String(localized: "使用眠屿即表示你理解这些规则"),
            closingDetail: String(localized: "正式生效版本以应用内当前展示的条款内容为准。")
        )
    }
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}

struct LegalDocumentSection: Identifiable, Hashable {
    let title: String
    let body: String
    let icon: String
    let tone: LegalDocumentTone
    let highlights: [String]
    let footnote: String?

    var id: String { title }

    init(
        title: String,
        body: String,
        icon: String = "text.alignleft",
        tone: LegalDocumentTone = .mint,
        highlights: [String] = [],
        footnote: String? = nil
    ) {
        self.title = title
        self.body = body
        self.icon = icon
        self.tone = tone
        self.highlights = highlights
        self.footnote = footnote
    }
}

enum LegalDocumentTone: Hashable {
    case mint
    case green
    case blue
    case orange
    case red
    case gray

    var color: Color {
        switch self {
        case .mint:
            return Theme.Colors.mintGreen
        case .green:
            return Color(hex: "34C759")
        case .blue:
            return Theme.Colors.accentBlue
        case .orange:
            return Theme.Colors.accentOrange
        case .red:
            return Theme.Colors.accentRed
        case .gray:
            return Theme.Colors.textTertiary
        }
    }

    var softBackground: Color {
        color.opacity(0.12)
    }
}

struct LegalDocumentQuickItem: Identifiable, Hashable {
    let title: String
    let subtitle: String
    let icon: String
    let tone: LegalDocumentTone

    var id: String { title }
}

/// 法律Document视图 由上级页面或路由调用，作为法律说明模块里的界面或内容组件。
/// 负责法律与合规说明。
struct LegalDocumentView: View {
    let title: String
    let subtitle: String
    let updatedAt: String
    let intro: String
    let icon: String
    let keyPoints: [String]
    var quickItems: [LegalDocumentQuickItem] = []
    let sections: [LegalDocumentSection]
    var sectionHeading: String = String(localized: "完整政策")
    var sectionCaption: String = String(localized: "以下内容为页面正式正文")
    var closingTitle: String? = nil
    var closingDetail: String? = nil

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    headerCard
                    HStack(alignment: .firstTextBaseline) {
                        Text(sectionHeading)
                            .font(.title3.weight(.bold))
                        Spacer()
                        Text(sectionCaption)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    contentCard
                    if let closingTitle, let closingDetail {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(closingTitle).font(.subheadline.weight(.bold)).foregroundStyle(Color(hex: "118A78"))
                            Text(closingDetail).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 88)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "118A78"))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(updatedAt.replacingOccurrences(of: "最后更新时间：", with: ""))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: "118A78"))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(hex: "EAF8F4"), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(intro)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineSpacing(5)

                if !keyPoints.isEmpty {
                    LegalKeyPointCloud(items: keyPoints)
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(Theme.Colors.surfaceBorder) }
    }

    private var quickSummaryGrid: some View {
        LegalQuickSummaryGrid(items: quickItems)
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                LegalSectionBlock(
                    index: index + 1,
                    section: section,
                    isLast: index == sections.count - 1
                )
            }
        }
    }
}

private struct LegalQuickSummaryGrid: View {
    let items: [LegalDocumentQuickItem]

    var body: some View {
        SettingsSectionCard(title: String(localized: "阅读重点")) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(item.tone.softBackground)
                        Image(systemName: item.icon)
                            .font(.appSystem(size: 17, weight: .bold))
                            .foregroundColor(item.tone.color)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(item.subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                if index != items.count - 1 {
                    Divider().padding(.leading, 66)
                }
            }
        }
    }
}

private struct LegalSectionBlock: View {
    let index: Int
    let section: LegalDocumentSection
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                sectionMarker

                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(section.body)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if !section.highlights.isEmpty {
                        LegalHighlightList(section: section)
                    }

                    if let footnote = section.footnote {
                        Text(footnote)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineSpacing(4)
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 2)

            if !isLast {
                Divider().overlay(Theme.Colors.surfaceBorder).padding(.leading, 40).padding(.top, 18)
            }
        }
    }

    private var sectionMarker: some View {
        VStack(spacing: 8) {
            Text(String(format: "%02d", index))
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(hex: "118A78"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(width: 28)
    }
}

private struct LegalHighlightList: View {
    let section: LegalDocumentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(section.highlights, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appSystem(size: 13, weight: .bold))
                        .foregroundColor(section.tone.color)
                        .padding(.top, 3)

                    Text(item)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(section.tone.softBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(section.tone.color.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct LegalKeyPointCloud: View {
    let items: [String]

    var body: some View {
        FlexibleTagFlow(items: items) { item in
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.appSystem(size: 11, weight: .bold))
                Text(item)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(Theme.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.Colors.surface.opacity(0.86))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
    }
}

private struct FlexibleTagFlow<Content: View>: View {
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    let items: [String]
    let content: (String) -> Content

    init(items: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let maxRowWidth = max(0, adaptiveLayout.containerWidth - 84)
            ForEach(computeRows(maxWidth: maxRowWidth), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    private func computeRows(maxWidth: CGFloat) -> [[String]] {
        var rows: [[String]] = [[]]
        var currentWidth: CGFloat = 0

        for item in items {
            let estimatedWidth = estimateWidth(for: item)
            if currentWidth + estimatedWidth > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([item])
                currentWidth = estimatedWidth + 8
            } else {
                rows[rows.count - 1].append(item)
                currentWidth += estimatedWidth + 8
            }
        }

        return rows.filter { !$0.isEmpty }
    }

    private func estimateWidth(for text: String) -> CGFloat {
        CGFloat(text.count * 15 + 40)
    }
}
