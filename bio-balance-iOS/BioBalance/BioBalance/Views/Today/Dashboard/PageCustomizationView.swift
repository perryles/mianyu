/// PageCustomizationSheet 由今日页/健康页底部入口调用，作为「页面模块定制」弹层。
/// 负责管理页面模块的显隐编辑与一键恢复。

import SwiftUI

/// PageCustomizationSheet 负责承载模块显隐编辑的主页面。
/// Page customization 相关视图由今日页、健康页等页面底部入口调用，用来管理页面模块显隐。
struct PageCustomizationSheet: View {
    private let page: PageCustomizationKind = .today
    @Environment(\.dismiss) private var dismiss
    @State private var toggleValues: [String: Bool] = [:]
    @State private var showHideAllConfirmation = false

    private var definitions: [PageCustomizationToggleDefinition] {
        page.definitions
    }

    private var visibleCount: Int {
        definitions.filter { toggleValues[$0.storageKey, default: $0.defaultValue] }.count
    }

    var body: some View {
        ZStack {
            Theme.Colors.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("自定义面板")
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "1F2126"))

                    Spacer(minLength: 0)

                    Button("完成") {
                        dismiss()
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "5B6ED6"))
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 16)

                        modulesList
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }

                footerActions
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .background(Theme.Colors.secondarySurface)
            }
        }
        .onAppear(perform: loadValues)
        .confirmationDialog("隐藏\(page.title)全部模块？", isPresented: $showHideAllConfirmation, titleVisibility: .visible) {
            Button("全部隐藏", role: .destructive) {
                definitions.forEach { updateValue(false, for: $0.storageKey) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("隐藏后不会删除数据，只会让这个页面先变成一个可恢复的空状态。")
        }
    }

    private func loadValues() {
        let defaults = UserDefaults.standard
        toggleValues = Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let value = defaults.object(forKey: definition.storageKey) as? Bool ?? definition.defaultValue
            return (definition.storageKey, value)
        })
    }

    private func updateValue(_ newValue: Bool, for storageKey: String) {
        toggleValues[storageKey] = newValue
        UserDefaults.standard.set(newValue, forKey: storageKey)
    }

    private var modulesList: some View {
        VStack(spacing: 6) {
            ForEach(definitions) { definition in
                minimalistRow(for: definition)
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button {
                definitions.forEach { updateValue($0.defaultValue, for: $0.storageKey) }
            } label: {
                Text("恢复默认")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "30333A"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                showHideAllConfirmation = true
            } label: {
                Text("全部隐藏")
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "F15A57"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "FFF1F1"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(visibleCount == 0)
            .opacity(visibleCount == 0 ? 0.45 : 1)
        }
    }

    private func minimalistRow(for definition: PageCustomizationToggleDefinition) -> some View {
        let isVisible = toggleValues[definition.storageKey, default: definition.defaultValue]

        return Button {
            updateValue(!isVisible, for: definition.storageKey)
        } label: {
            HStack(spacing: 18) {
                Image(systemName: "line.3.horizontal")
                    .font(.appSystem(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: "C5C8CE"))
                    .frame(width: 30, alignment: .center)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(definition.tint.opacity(0.13))
                        .frame(width: 44, height: 44)

                    Image(systemName: definition.symbol)
                        .font(.appSystem(size: 20, weight: .semibold))
                        .foregroundColor(definition.tint)
                }

                Text(definition.title)
                    .font(.appSystem(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "1F2126"))

                Spacer(minLength: 0)

                if !isVisible {
                    Text("已隐藏")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "A4A8B1"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Colors.secondarySurface, in: Capsule())
                }
            }
            .opacity(isVisible ? 1 : 0.42)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// PageCustomizationFooterLink 由各页面底部调用，作为进入布局编辑页的轻入口。
struct PageCustomizationFooterLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.appSystem(size: 15, weight: .black))

                Text(title)
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
            }
            .foregroundColor(Color(hex: "7D8792"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.72), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// PageCustomizationEmptyCard 由页面首页调用，用来承接“全部隐藏后”的空状态提示。
struct PageCustomizationEmptyCard: View {
    private let page: PageCustomizationKind = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: page.icon)
                    .font(.appSystem(size: 20, weight: .bold))
                    .foregroundColor(page.accent)
                    .frame(width: 46, height: 46)
                    .bbTintedChip(tint: page.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous), tintOpacity: 0.08)

                VStack(alignment: .leading, spacing: 6) {
                    Text(page.emptyTitle)
                        .font(.appSystem(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(page.emptySubtitle)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("下方入口可随时恢复布局。")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .bbTintedChip(tint: page.accent, in: Capsule(), tintOpacity: 0.05)
        }
        .padding(18)
        .todayCardSurface(tint: page.accent)
    }
}

#Preview {
    PageCustomizationSheet()
}
