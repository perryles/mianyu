import SwiftUI

struct ContentCollaborationView: View {
    var body: some View {
        MianyuPage(title: "内容共创") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuHeroCard(
                        eyebrow: String(localized: "内容共创"),
                        title: String(localized: "把复杂健康话题，做成用户愿意看的内容"),
                        detail: String(localized: "适合科普、产品体验与生活方式内容。"),
                        eyebrowFontSize: 14,
                        titleFontSize: 24,
                        detailFontSize: 14
                    )

                    MianyuSectionTitle(title: "适合一起做", bottomSpacing: -10)
                    CooperationFeatureList(items: [
                        (String(localized: "健康科普"), String(localized: "围绕睡眠、压力、活动和健康数据做易懂内容。"), "scope", MianyuSupportPalette.green),
                        (String(localized: "产品体验"), String(localized: "真实体验眠屿与 Apple Watch 场景，强调使用价值。"), "diamond", MianyuSupportPalette.orange),
                        (String(localized: "生活方式"), String(localized: "把健康管理融入通勤、工作、运动和休息。"), "sparkles", MianyuSupportPalette.violet)
                    ])

                    MianyuSectionTitle(title: "合作流程", bottomSpacing: -10)
                    CooperationProcessCard(steps: [
                        (String(localized: "提出方向"), String(localized: "主题与目标")),
                        (String(localized: "一起打磨"), String(localized: "内容与表达")),
                        (String(localized: "发布复盘"), String(localized: "数据与反馈"))
                    ])

                    CooperationSupportCard(
                        title: String(localized: "眠屿可以提供"),
                        detail: String(localized: "产品资料、数据解释、体验支持与联合传播。")
                    )

                    NavigationLink { CooperationApplicationView(cooperationType: .content) } label: {
                        Text("发起内容合作")
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
