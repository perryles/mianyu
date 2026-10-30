/// 餐食记录详情页，对照设计稿：大标题食物名 + 热量 + 三大营养素分布。
/// 从饮食管理主页的三餐卡片进入。

import SwiftUI

struct MealRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var record: MealRecognitionRecord
    @State private var editingFood: MealFoodItem?
    @State private var confirmingDeletion = false
    private let onRecordChanged: () -> Void
    private let accent = Color(hex: "287A58")

    init(record: MealRecognitionRecord, onRecordChanged: @escaping () -> Void = {}) {
        _record = State(initialValue: record)
        self.onRecordChanged = onRecordChanged
    }

    var body: some View {
        ZStack {
            HealthDetailPageBackground(
                topGlow: Color(hex: "FFD9AD"),
                lowerGlow: Color(hex: "F8E7D5")
            )
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    nutritionCard
                    foodListCard
                    metaCard
                    actionSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .healthDetailNavigation(title: "记录详情")
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editingFood) { food in
            MealFoodEditorView(food: food) { updated in
                guard let index = record.recognizedFoods.firstIndex(where: { $0.id == updated.id }) else { return }
                record.recognizedFoods[index] = updated
                persistRecord()
            } onDelete: {
                record.recognizedFoods.removeAll { $0.id == food.id }
                persistRecord()
            }
        }
        .confirmationDialog("删除这条餐食记录？", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if DrinkExperienceStore.shared.deleteMealRecord(id: record.id) {
                    onRecordChanged()
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后，今日累计与营养分析会同步更新。") }
    }

    // MARK: - 子组件

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let url = MealPhotoStore.shared.url(for: record.photoLocalFilename), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)
            }

            ModernReportHero(
                eyebrow: String(localized: "餐食记录"),
                title: record.mealSlot.title,
                value: "\(record.estimatedCalories)",
                unit: "KCAL",
                ghostUnit: "KCAL",
                captions: [
                    ModernReportCaption(
                        symbol: "clock",
                        text: record.capturedAt.formatted(.dateTime.locale(Locale.autoupdatingCurrent).hour().minute())
                    ),
                    ModernReportCaption(
                        symbol: "sparkles",
                        text: record.aiSourceLabel ?? String(localized: "AI 营养估算")
                    )
                ],
                badge: ModernReportBadge(
                    symbol: "text.badge.checkmark",
                    text: String(localized: "已识别 \(record.recognizedFoods.count) 项"),
                    tint: accent
                ),
                accent: accent,
                symbol: slotIcon
            )
        }
    }

    private var primaryFoodName: String {
        record.recognizedFoods.first?.name ?? record.mealSlot.title
    }

    private var slotIcon: String {
        switch record.mealSlot {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "cup.and.saucer.fill"
        }
    }

    private var totalMacros: (protein: Double, carbs: Double, fat: Double) {
        record.recognizedFoods.reduce((0, 0, 0)) { acc, food in
            (
                acc.0 + (food.proteinGrams ?? 0),
                acc.1 + (food.carbohydrateGrams ?? 0),
                acc.2 + (food.fatGrams ?? 0)
            )
        }
    }

    private var nutritionCard: some View {
        ModernReportMetricsPanel(
            title: String(localized: "营养成分"),
            metrics: [
                ModernReportMetric(
                    title: String(localized: "热量"),
                    value: "\(record.estimatedCalories) kcal",
                    tint: accent,
                    symbol: "flame.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "蛋白质"),
                    value: "\(Int(totalMacros.protein.rounded())) g",
                    tint: Color(hex: "E68A3F"),
                    symbol: "bolt.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "碳水"),
                    value: "\(Int(totalMacros.carbs.rounded())) g",
                    tint: Color(hex: "4E98E7"),
                    symbol: "leaf.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "脂肪"),
                    value: "\(Int(totalMacros.fat.rounded())) g",
                    tint: Color(hex: "F3A53B"),
                    symbol: "drop.fill"
                ),
                ModernReportMetric(
                    title: String(localized: "膳食纤维"),
                    value: "\(Int(totalFiber.rounded())) g",
                    tint: Theme.Colors.mintGreen,
                    symbol: "allergens"
                )
            ]
        )
    }

    private var totalFiber: Double {
        record.recognizedFoods.reduce(0) { $0 + ($1.fiberGrams ?? 0) }
    }

    private func macroTile(value: Int, unit: String, title: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.appSystem(size: 20, weight: .black, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "5A6B62"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var foodListCard: some View {
        if !record.recognizedFoods.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("食物明细")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "1A2921"))
                VStack(spacing: 10) {
                    ForEach(record.recognizedFoods) { food in
                        Button { editingFood = food } label: {
                        HStack {
                            Text(food.name)
                                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "27384F"))
                            Spacer()
                            Text("\(food.calories) kcal")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "6F86A0"))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .dietSurface()
        }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sourceLabel = record.aiSourceLabel {
                Label(sourceLabel, systemImage: "sparkles")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "2C74C9"))
            }
            Label(
                record.capturedAt.formatted(.dateTime.locale(Locale.autoupdatingCurrent).year().month().day().hour().minute()),
                systemImage: "clock"
            )
            .font(.appSystem(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(Color(hex: "7C8D84"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dietSurface()
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button("复制这餐") { copyMeal() }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .tint(Color(hex: "30343B"))
                Button("编辑") { editingFood = record.recognizedFoods.first }
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .tint(Color(hex: "30343B"))
                    .disabled(record.recognizedFoods.isEmpty)
            }
            Button("删除", role: .destructive) { confirmingDeletion = true }
                .frame(maxWidth: .infinity).frame(height: 42)
                .buttonStyle(.bordered).buttonBorderShape(.capsule)

            NavigationLink {
                MealDailyNutritionView(records: DrinkExperienceStore.shared.meals(on: record.capturedAt))
            } label: {
                Text("查看今日营养分析")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "168B7B"))
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color(hex: "EAF8F4"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func persistRecord() {
        record.estimatedCalories = record.recognizedFoods.reduce(0) { $0 + $1.calories }
        DrinkExperienceStore.shared.saveMealRecord(record)
        onRecordChanged()
    }

    /// 复制这餐：新建独立记录（新 id、新时间），完整保留食物营养字段、
    /// 照片文件与识别元数据；照片复制一份新文件，避免删除原餐时连带丢失。
    private func copyMeal() {
        let newID = UUID().uuidString
        let copiedFoods = record.recognizedFoods.map { food in
            MealFoodItem(
                id: UUID().uuidString,
                name: food.name,
                calories: food.calories,
                proteinGrams: food.proteinGrams,
                carbohydrateGrams: food.carbohydrateGrams,
                fatGrams: food.fatGrams,
                fiberGrams: food.fiberGrams,
                servingAmount: food.servingAmount,
                servingUnit: food.servingUnit,
                confidence: food.confidence,
                nutritionSource: food.nutritionSource,
                wasEditedByUser: food.wasEditedByUser
            )
        }

        let photoCopy = copyPhotoFiles(for: newID)
        let copy = MealRecognitionRecord(
            id: newID,
            mealSlot: record.mealSlot,
            recognizedFoods: copiedFoods,
            estimatedCalories: record.estimatedCalories,
            photoFileID: nil,
            photoURL: nil,
            capturedAt: Date(),
            locationSummary: record.locationSummary,
            aiProviderID: record.aiProviderID,
            aiModel: record.aiModel,
            aiConfidence: record.aiConfidence,
            photoLocalFilename: photoCopy?.photo,
            thumbnailLocalFilename: photoCopy?.thumbnail,
            wasEditedByUser: record.wasEditedByUser
        )
        DrinkExperienceStore.shared.saveMealRecord(copy)
        onRecordChanged()
    }

    /// 把原记录的本机照片复制到新 recordID 下，返回新文件名。
    private func copyPhotoFiles(for newRecordID: String) -> (photo: String, thumbnail: String)? {
        guard let sourcePhoto = MealPhotoStore.shared.url(for: record.photoLocalFilename),
              let photoData = try? Data(contentsOf: sourcePhoto) else { return nil }
        return try? MealPhotoStore.shared.savePreparedJPEG(photoData, recordID: newRecordID)
    }
}
