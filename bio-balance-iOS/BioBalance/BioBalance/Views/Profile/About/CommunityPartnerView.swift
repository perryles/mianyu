import SwiftUI

struct CommunityPartnerView: View {
    var body: some View {
        MianyuPage(title: "社区伙伴") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuHeroCard(
                        eyebrow: String(localized: "社区伙伴"),
                        title: String(localized: "让健康理解，在真实社区里发生"),
                        detail: String(localized: "适合社群、活动组织、运动社区与创作者网络。"),
                        tint: Color(hex: "656FFF"),
                        background: Color(hex: "EEF1FF"),
                        eyebrowFontSize: 14,
                        titleFontSize: 24,
                        detailFontSize: 14
                    )

                    MianyuSectionTitle(title: "适合的伙伴", bottomSpacing: -10)
                    CooperationFeatureList(items: [
                        (String(localized: "健康与生活社群"), String(localized: "关注睡眠、情绪、习惯与自我管理的长期社区。"), "circle.circle", MianyuSupportPalette.green),
                        (String(localized: "运动与线下活动"), String(localized: "跑步、骑行、健身、户外和健康主题活动。"), "diamond", MianyuSupportPalette.orange),
                        (String(localized: "创作者与组织"), String(localized: "有稳定受众、愿意长期共创内容与体验。"), "sparkles", MianyuSupportPalette.violet)
                    ])

                    MianyuSectionTitle(title: "可以一起做", bottomSpacing: -10)
                    CooperationFeatureList(items: [
                        (String(localized: "主题挑战"), String(localized: "7–21 天睡眠 / 恢复挑战"), "flag.fill", MianyuSupportPalette.green),
                        (String(localized: "线下活动"), String(localized: "分享会、体验日、健康工作坊"), "person.3.fill", MianyuSupportPalette.orange),
                        (String(localized: "知识共创"), String(localized: "联合内容、数据解读与工具包"), "book.closed.fill", MianyuSupportPalette.violet)
                    ])

                    CooperationSupportCard(
                        title: String(localized: "眠屿可以提供"),
                        detail: String(localized: "内容工具包、产品体验支持、活动物料与联合传播。")
                    )

                    NavigationLink { CooperationApplicationView(cooperationType: .community) } label: {
                        Text("申请成为社区伙伴")
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
