import SwiftUI

struct FAQAllSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: FAQCategory?
    @State private var expandedItemID: SupportFAQItem.ID?

    private var items: [SupportFAQItem] {
        FAQDataSource.filteredItems(searchText: searchText, category: selectedCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: "D6DCE1"))
                .frame(width: 42, height: 5)
                .padding(.top, 12)

            HStack(alignment: .top) {
                Text("全部问题")
                    .font(.appSystem(size: 22, weight: .bold))
                    .foregroundStyle(MianyuSupportPalette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 14, weight: .regular))
                        .foregroundStyle(Color(hex: "55606F"))
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surface, in: Circle())
                        .overlay(Circle().stroke(MianyuSupportPalette.border, lineWidth: 1))
                }
                .buttonStyle(MianyuPressButtonStyle())
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    MianyuSearchField(prompt: "搜索全部问题", text: $searchText)

                    Text("按主题筛选")
                        .font(.appSystem(size: 16, weight: .bold))
                        .foregroundStyle(MianyuSupportPalette.primaryText)
                        .padding(.bottom, -8)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        filterChip(title: String(localized: "全部 23"), category: nil)
                        ForEach(FAQCategory.allCases) { category in
                            filterChip(title: "\(category.title) \(FAQDataSource.count(for: category))", category: category)
                        }
                    }

                    HStack {
                        Text("全部问题")
                            .font(.appSystem(size: 16, weight: .bold))
                            .foregroundStyle(MianyuSupportPalette.primaryText)
                        Spacer()
                        Text("\(items.count) 条")
                            .font(.appSystem(size: 13, weight: .regular))
                            .foregroundStyle(MianyuSupportPalette.secondaryText)
                    }
                    .padding(.bottom, -8)

                    if items.isEmpty {
                        ContentUnavailableView(
                            "没有找到相关问题",
                            systemImage: "magnifyingglass",
                            description: Text("换一个关键词或主题再试试。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        FAQAccordionList(items: items, expandedItemID: $expandedItemID)
                    }

                    Text("上滑继续查看更多")
                        .font(.appSystem(size: 13, weight: .regular))
                        .foregroundStyle(MianyuSupportPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(MianyuSupportPalette.background)
    }

    private func filterChip(title: String, category: FAQCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
            expandedItemID = nil
        } label: {
            Text(title)
                .font(.appSystem(size: 12, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color(hex: "55606F"))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(isSelected ? MianyuSupportPalette.green : Color(hex: "F4F6F8"), in: Capsule())
                .overlay(Capsule().stroke(isSelected ? MianyuSupportPalette.green : MianyuSupportPalette.border, lineWidth: 1))
        }
        .buttonStyle(MianyuPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
