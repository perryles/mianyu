import SwiftUI

enum MianyuSupportPalette {
    static let background = Theme.Colors.pageBackground
    static let card = Theme.Colors.surface
    static let primaryText = Theme.Colors.textPrimary
    static let secondaryText = Theme.Colors.textSecondary
    static let tertiaryText = Theme.Colors.textTertiary
    static let border = Theme.Colors.surfaceBorder
    static let field = Theme.Colors.secondarySurface
    static let green = Theme.Colors.mintGreen
    static let mint = Color(hex: "E7F8F1")
    static let paleMint = Color(hex: "F0FBF7")
    static let orange = Color(hex: "E19018")
    static let paleOrange = Color(hex: "FFF4E2")
    static let violet = Color(hex: "7156FF")
    static let paleViolet = Color(hex: "F1EFFF")
    static let blue = Color(hex: "1E7AED")
    static let paleBlue = Color(hex: "ECF4FF")
    static let coral = Color(hex: "C44F39")
    static let paleCoral = Color(hex: "FFF1EA")
}

struct MianyuPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MianyuSupportPalette.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(MianyuSupportPalette.green)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(MianyuSupportPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }
}

struct MianyuSectionTitle: View {
    let title: LocalizedStringKey
    var bottomSpacing: CGFloat = 0

    var body: some View {
        Text(title)
            .font(.appSystem(size: 18, weight: .bold))
            .foregroundStyle(MianyuSupportPalette.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, bottomSpacing)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MianyuCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(MianyuSupportPalette.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MianyuSupportPalette.border, lineWidth: 1)
            }
            .shadow(color: Color(hex: "101825").opacity(0.05), radius: 11, y: 8)
    }
}

struct MianyuPrimaryButton: View {
    let title: LocalizedStringKey
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(Theme.Colors.onAccent)
                }
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(MianyuSupportPalette.green.opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(MianyuPressButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
}

struct MianyuSelectionChip: View {
    let title: String
    let isSelected: Bool
    let tint: Color
    let background: Color
    var fontSize: CGFloat = 10
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: fontSize, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(minHeight: fontSize >= 12 ? 42 : 38)
                .background(isSelected ? tint : background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? tint : MianyuSupportPalette.border, lineWidth: 1)
                }
        }
        .buttonStyle(MianyuPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MianyuInfoRow: View {
    let title: String
    let detail: String
    let symbol: String
    var tint = MianyuSupportPalette.green
    var showsChevron = false
    var titleFontSize: CGFloat = 13
    var detailFontSize: CGFloat = 10

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: detailFontSize >= 14 ? 5 : 2) {
                Text(title)
                    .font(.appSystem(size: titleFontSize, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.appSystem(size: detailFontSize, weight: .regular))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .lineSpacing(detailFontSize >= 14 ? 2 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 11, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .padding(.top, 9)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, detailFontSize >= 14 ? 13 : 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MianyuPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.78 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.11), value: configuration.isPressed)
    }
}

struct MianyuSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.appSystem(size: 14, weight: .bold))
                .foregroundStyle(MianyuSupportPalette.primaryText)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(.appSystem(size: 14, weight: .regular))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MianyuSupportPalette.tertiaryText)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 7, y: 4)
    }
}

struct MianyuTextEditor: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var minimumHeight: CGFloat = 84

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .font(.appSystem(size: 14, weight: .regular))
                    .foregroundStyle(Color(hex: "9AA4B1"))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.appSystem(size: 14, weight: .regular))
                .foregroundStyle(MianyuSupportPalette.primaryText)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: minimumHeight)
        }
        .background(MianyuSupportPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
    }
}

struct MianyuHeroCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    var tint = MianyuSupportPalette.green
    var background = MianyuSupportPalette.paleMint
    var eyebrowFontSize: CGFloat = 11
    var titleFontSize: CGFloat = 20
    var detailFontSize: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: detailFontSize >= 14 ? 8 : 5) {
            Text(eyebrow)
                .font(.appSystem(size: eyebrowFontSize, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.appSystem(size: titleFontSize, weight: .bold))
                .foregroundStyle(MianyuSupportPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.appSystem(size: detailFontSize, weight: .regular))
                .foregroundStyle(MianyuSupportPalette.secondaryText)
                .lineSpacing(detailFontSize >= 14 ? 3 : 0)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(detailFontSize >= 14 ? 20 : 17)
        .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
    }
}
