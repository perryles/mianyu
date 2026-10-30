import SwiftUI

struct AboutMianyuView: View {
    var body: some View {
        MianyuPage(title: "了解眠屿") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuHeroCard(
                        eyebrow: String(localized: "眠屿 · 安静的小岛"),
                        title: String(localized: "把复杂健康数据，变成日常里看得懂的线索"),
                        detail: String(localized: "不是制造焦虑，而是帮助你理解变化。"),
                        eyebrowFontSize: 14,
                        titleFontSize: 24,
                        detailFontSize: 14
                    )

                    MianyuSectionTitle(title: "我们坚持", bottomSpacing: -10)
                    VStack(spacing: 8) {
                        principleCard(
                            title: String(localized: "数据有来源"),
                            detail: String(localized: "优先使用设备和系统提供的健康数据与授权。"),
                            symbol: "scope",
                            tint: MianyuSupportPalette.green
                        )
                        principleCard(
                            title: String(localized: "判断有边界"),
                            detail: String(localized: "健康信息用于理解与记录，不替代专业医疗诊断。"),
                            symbol: "diamond",
                            tint: MianyuSupportPalette.orange
                        )
                        principleCard(
                            title: String(localized: "建议要可执行"),
                            detail: String(localized: "少一点指标堆叠，多一点今天做得到的小行动。"),
                            symbol: "sparkles",
                            tint: MianyuSupportPalette.violet
                        )
                    }

                    MianyuSectionTitle(title: "我们正在做", bottomSpacing: -10)
                    MianyuCard {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("睡眠 · 压力 · 活动 · 生命体征")
                                    .font(.appSystem(size: 16, weight: .bold))
                                    .foregroundStyle(MianyuSupportPalette.primaryText)
                                Text("把零散指标放回趋势、节律和生活场景中。")
                                    .font(.appSystem(size: 14, weight: .regular))
                                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Apple Watch 与小组件")
                                    .font(.appSystem(size: 16, weight: .bold))
                                    .foregroundStyle(MianyuSupportPalette.primaryText)
                                Text("让关键状态更自然地出现在手腕和日常入口里。")
                                    .font(.appSystem(size: 14, weight: .regular))
                                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
    }

    private func principleCard(title: String, detail: String, symbol: String, tint: Color) -> some View {
        MianyuCard(cornerRadius: 20) {
            MianyuInfoRow(
                title: title,
                detail: detail,
                symbol: symbol,
                tint: tint,
                titleFontSize: 16,
                detailFontSize: 14
            )
        }
    }
}

#Preview {
    NavigationStack { AboutMianyuView() }
}
