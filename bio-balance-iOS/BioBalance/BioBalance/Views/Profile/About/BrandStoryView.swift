import SwiftUI

struct BrandStoryView: View {
    var body: some View {
        MianyuPage(title: "我们的故事") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    storyHero

                    MianyuSectionTitle(title: "我们怎么做", bottomSpacing: -10)
                    MianyuCard {
                        VStack(spacing: 0) {
                            storyStep(number: "01", title: String(localized: "先看见身体信号"), detail: String(localized: "把睡眠、压力、活动和日常记录放回同一段生活里。"), tint: MianyuSupportPalette.green)
                            Divider().padding(.leading, 59)
                            storyStep(number: "02", title: String(localized: "再理解一段变化"), detail: String(localized: "少盯一次高低，多看趋势、节律和前后关系。"), tint: MianyuSupportPalette.orange)
                            Divider().padding(.leading, 59)
                            storyStep(number: "03", title: String(localized: "最后轻轻行动"), detail: String(localized: "把复杂数据收成一件今天真正做得到的小事。"), tint: MianyuSupportPalette.green)
                        }
                    }

                    MianyuSectionTitle(title: "我们相信", bottomSpacing: -10)
                    MianyuCard {
                        MianyuInfoRow(
                            title: String(localized: "健康数字不该只停留在数字"),
                            detail: String(localized: "它们应该能被理解、被回看，也能带来一点行动的日常线索。"),
                            symbol: "sparkles",
                            titleFontSize: 16,
                            detailFontSize: 14
                        )
                    }

                    NavigationLink { AboutMianyuView() } label: {
                        MianyuInfoRow(
                            title: String(localized: "了解眠屿"),
                            detail: String(localized: "继续看看我们正在做什么"),
                            symbol: "arrow.up.right",
                            showsChevron: true,
                            titleFontSize: 16,
                            detailFontSize: 14
                        )
                    }
                    .buttonStyle(MianyuPressButtonStyle())
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 11, y: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
    }

    private var storyHero: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("为什么做眠屿")
                    .font(.appSystem(size: 14, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.green)
                Text("让身体的信号，\n变成看得懂的日常")
                    .font(.appSystem(size: 26, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("数字很多，重要的是理解它们和此刻的自己有什么关系。")
                    .font(.appSystem(size: 14, weight: .regular))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle().fill(.white).frame(width: 64, height: 64)
                Circle().fill(Color(hex: "BEE0FF")).frame(width: 36, height: 36)
                Circle().fill(Color(hex: "9DE8BC")).frame(width: 18, height: 18).offset(x: 20, y: 20)
                Circle().fill(MianyuSupportPalette.green).frame(width: 8, height: 8).offset(x: 18, y: -22)
            }
            .accessibilityHidden(true)
        }
        .padding(20)
        .background(MianyuSupportPalette.mint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 7, y: 4)
    }

    private func storyStep(number: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.appSystem(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.primaryText)
                Text(detail)
                    .font(.appSystem(size: 14, weight: .regular))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { BrandStoryView() }
}
