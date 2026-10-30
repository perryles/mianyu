import SwiftUI

struct CooperationFeatureList: View {
    let items: [(title: String, detail: String, symbol: String, tint: Color)]

    var body: some View {
        MianyuCard {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MianyuInfoRow(title: item.title, detail: item.detail, symbol: item.symbol, tint: item.tint, titleFontSize: 16, detailFontSize: 14)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 59)
                    }
                }
            }
        }
    }
}

struct CooperationProcessCard: View {
    let steps: [(title: String, detail: String)]

    var body: some View {
        MianyuCard {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: "%02d", index + 1))
                            .font(.appSystem(size: 13, weight: .bold))
                            .foregroundStyle(index == 1 ? MianyuSupportPalette.orange : MianyuSupportPalette.green)
                            .frame(width: 36, height: 36)
                            .background((index == 1 ? MianyuSupportPalette.paleOrange : MianyuSupportPalette.mint), in: Circle())
                        Text(step.title)
                            .font(.appSystem(size: 14, weight: .bold))
                            .foregroundStyle(MianyuSupportPalette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(step.detail)
                            .font(.appSystem(size: 12, weight: .regular))
                            .foregroundStyle(MianyuSupportPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}

struct CooperationSupportCard: View {
    let title: String
    let detail: String
    var tint = MianyuSupportPalette.green
    var background = MianyuSupportPalette.paleMint
    var titleFontSize: CGFloat = 15
    var detailFontSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: titleFontSize, weight: .bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.appSystem(size: detailFontSize, weight: .regular))
                .foregroundStyle(MianyuSupportPalette.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
    }
}
