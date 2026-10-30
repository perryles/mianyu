import SwiftUI

struct FAQListView: View {
    @State private var searchText = ""
    @State private var selectedCategory: FAQCategory?
    @State private var expandedItemID: SupportFAQItem.ID?
    @State private var showingAllQuestions = false

    private var visibleItems: [SupportFAQItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           selectedCategory == nil {
            return FAQDataSource.featuredItems
        }
        return FAQDataSource.filteredItems(searchText: searchText, category: selectedCategory)
    }

    var body: some View {
        MianyuPage(title: "常见问题") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MianyuSearchField(prompt: "搜索问题或关键词", text: $searchText)

                    MianyuSectionTitle(title: "常见主题", bottomSpacing: -10)
                    categoryCards

                    HStack {
                        MianyuSectionTitle(title: searchText.isEmpty ? "热门问题" : "搜索结果")
                        Button("全部") { showingAllQuestions = true }
                            .font(.appSystem(size: 14, weight: .bold))
                            .foregroundStyle(MianyuSupportPalette.green)
                            .buttonStyle(.plain)
                            .accessibilityHint("从底部打开全部问题")
                    }
                    .padding(.bottom, -10)

                    if visibleItems.isEmpty {
                        emptyState
                    } else {
                        FAQAccordionList(items: visibleItems, expandedItemID: $expandedItemID)
                    }

                    Button { showingAllQuestions = true } label: {
                        MianyuInfoRow(
                            title: String(localized: "全部帮助内容"),
                            detail: String(localized: "共 6 个主题，23 条内容"),
                            symbol: "questionmark",
                            showsChevron: true,
                            titleFontSize: 16,
                            detailFontSize: 14
                        )
                    }
                    .buttonStyle(MianyuPressButtonStyle())
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MianyuSupportPalette.border, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 11, y: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showingAllQuestions) {
            FAQAllSheet()
                .presentationDetents([.fraction(0.82)])
                .presentationCornerRadius(30)
                .presentationDragIndicator(.hidden)
                .presentationBackground(MianyuSupportPalette.background)
        }
        .onChange(of: searchText) { _, _ in
            expandedItemID = nil
        }
    }

    private var categoryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.small) {
            categoryCard(.stressRecovery, background: MianyuSupportPalette.paleMint)
            categoryCard(.watchSync, background: Color(hex: "F0F4FF"))
        }
    }

    private func categoryCard(_ category: FAQCategory, background: Color) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = isSelected ? nil : category
            expandedItemID = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: category.symbol)
                    .font(.appSystem(size: 15, weight: .bold))
                    .foregroundStyle(category.tint)
                    .frame(width: 36, height: 36)
                    .background(Theme.Colors.surface, in: Circle())
                Spacer(minLength: 0)
                Text(category.title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(MianyuSupportPalette.primaryText)
                Text("\(FAQDataSource.count(for: category)) 条")
                    .font(Theme.Typography.supporting)
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 104)
            .padding(Theme.Spacing.small)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(isSelected ? category.tint : MianyuSupportPalette.border, lineWidth: isSelected ? 1.5 : 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 5)
        }
        .buttonStyle(MianyuPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyState: some View {
        MianyuCard {
            ContentUnavailableView(
                "没有找到相关问题",
                systemImage: "magnifyingglass",
                description: Text("换一个关键词，或清除主题筛选后再试试。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }
}

struct FAQAccordionList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [SupportFAQItem]
    @Binding var expandedItemID: SupportFAQItem.ID?

    var body: some View {
        MianyuCard {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FAQAccordionRow(
                        item: item,
                        isExpanded: expandedItemID == item.id,
                        reduceMotion: reduceMotion
                    ) {
                        let next = expandedItemID == item.id ? nil : item.id
                        expandedItemID = next
                    }
                    if index < items.count - 1 {
                        Divider().padding(.leading, 59)
                    }
                }
            }
        }
    }
}

private struct FAQAccordionRow: View {
    let item: SupportFAQItem
    let isExpanded: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.category.symbol)
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundStyle(item.category.tint)
                    .frame(width: 36, height: 36)
                    .background(item.category.tint.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.question)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(MianyuSupportPalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if isExpanded {
                        Text(item.answer)
                            .font(Theme.Typography.body)
                            .foregroundStyle(MianyuSupportPalette.secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(item.summary)
                            .font(Theme.Typography.body)
                            .foregroundStyle(MianyuSupportPalette.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.secondaryText)
                    .rotationEffect(reduceMotion ? .zero : .degrees(isExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
                    .padding(.top, 9)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.question)
        .accessibilityValue(isExpanded ? item.answer : item.summary)
        .accessibilityHint(isExpanded ? "收起答案" : "展开答案")
    }
}

#Preview {
    NavigationStack { FAQListView() }
}
