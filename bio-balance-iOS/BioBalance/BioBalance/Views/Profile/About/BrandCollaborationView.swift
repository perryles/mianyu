import SwiftUI

struct BrandCollaborationView: View {
    var body: some View {
        MianyuPage(title: "品牌联名") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuHeroCard(
                        eyebrow: String(localized: "品牌联名"),
                        title: String(localized: "不是贴一个 Logo，而是一起创造体验。"),
                        detail: String(localized: "我们更看重用户价值、品牌契合和长期体验。"),
                        tint: MianyuSupportPalette.coral,
                        background: MianyuSupportPalette.paleCoral,
                        eyebrowFontSize: 14,
                        titleFontSize: 24,
                        detailFontSize: 14
                    )

                    MianyuSectionTitle(title: "可以怎么合作", bottomSpacing: -10)
                    CooperationFeatureList(items: [
                        (String(localized: "主题联名"), String(localized: "围绕睡眠、恢复、健康习惯策划联合主题。"), "diamond", MianyuSupportPalette.orange),
                        (String(localized: "产品体验"), String(localized: "联合体验计划、专题内容或功能场景合作。"), "sparkles", MianyuSupportPalette.green),
                        (String(localized: "权益与活动"), String(localized: "会员权益、礼赠、线下活动或品牌触点联动。"), "circle.circle", Color(hex: "656FFF"))
                    ])

                    MianyuSectionTitle(title: "合作原则", bottomSpacing: -10)
                    CooperationProcessCard(steps: [
                        (String(localized: "适合彼此"), String(localized: "价值观一致")),
                        (String(localized: "用户优先"), String(localized: "不牺牲体验")),
                        (String(localized: "隐私清晰"), String(localized: "边界透明"))
                    ])

                    CooperationSupportCard(
                        title: String(localized: "先确认是否合适，再讨论具体资源与形式。"),
                        detail: "",
                        tint: MianyuSupportPalette.coral,
                        background: Color(hex: "FFF7F2")
                    )

                    NavigationLink { CooperationApplicationView(cooperationType: .brand) } label: {
                        Text("聊聊品牌合作")
                            .font(.appSystem(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(MianyuSupportPalette.green, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(MianyuPressButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
    }
}
