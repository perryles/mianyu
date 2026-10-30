import SwiftUI
import UIKit

/// 餐食图片识别完成后的整餐确认页。
/// 图片仅用于当前确认流程，保存时仍只写入结构化餐食数据。
struct MealRecognitionResultView: View {
    @Environment(\.dismiss) private var dismiss

    let result: PhotoRecognitionResult?
    let photoImage: UIImage?
    /// 低置信度结果：整页顶部提示 + 单项食物标注，要求用户逐项核对。
    var isLowConfidence: Bool = false
    /// 用户修改任何食物/餐次后回调（Hub 用于退出确认）。
    var onEdited: () -> Void = {}
    let onReplacePhoto: () -> Void
    let onRetry: () -> Void
    let onSave: (MealSlot, [MealFoodItem]) -> Void

    @State private var selectedSlot: MealSlot
    @State private var foods: [MealFoodItem]
    @State private var editingFood: MealFoodItem?

    private let accent = Color(hex: "28B58A")
    private let pageBackground = Color(hex: "F5F7F9")
    private let cardBorder = Color(hex: "E7ECEA")

    init(
        result: PhotoRecognitionResult?,
        photoImage: UIImage?,
        initialSlot: MealSlot,
        isLowConfidence: Bool = false,
        onEdited: @escaping () -> Void = {},
        onReplacePhoto: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onSave: @escaping (MealSlot, [MealFoodItem]) -> Void
    ) {
        self.result = result
        self.photoImage = photoImage
        self.isLowConfidence = isLowConfidence
        self.onEdited = onEdited
        self.onReplacePhoto = onReplacePhoto
        self.onRetry = onRetry
        self.onSave = onSave
        _selectedSlot = State(initialValue: initialSlot)
        _foods = State(initialValue: result?.recognizedFoods ?? [])
    }

    private var totalCalories: Int { foods.reduce(0) { $0 + $1.calories } }
    private var protein: Double? { sumMacro(\.proteinGrams) }
    private var carbohydrates: Double? { sumMacro(\.carbohydrateGrams) }
    private var fat: Double? { sumMacro(\.fatGrams) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if isLowConfidence {
                        lowConfidenceBanner
                    }
                    photoCard
                    recognitionCard
                    nutritionTotalCard
                    analysisCard
                    mealSlotCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 94)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .background(pageBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbar }
            .toolbarBackground(Color(hex: "EEF8F4"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .interactiveDismissDisabled()
        .sheet(item: $editingFood) { food in
            MealFoodEditorView(food: food) { updated in
                if let index = foods.firstIndex(where: { $0.id == updated.id }) {
                    foods[index] = updated
                } else {
                    // 新增遗漏食物的场景：编辑保存后补回列表。
                    foods.append(updated)
                }
                onEdited()
            } onDelete: {
                foods.removeAll { $0.id == food.id }
                onEdited()
            }
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("返回")
        }

        ToolbarItem(placement: .principal) {
            VStack(alignment: .leading, spacing: 0) {
                Text("餐食识别")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("识别餐食，记录营养摄入")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "7C8591"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onReplacePhoto) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("更换图片")
        }
    }

    /// 低置信度提示：明确告知"这是估算，需要核对"，不承诺准确率。
    private var lowConfidenceBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("识别置信度较低", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: "9A6A2F"))
            Text("以下食物名称和份量均为估算，请逐项核对：确认、修改或删除不符合的项目。")
                .font(.caption)
                .foregroundStyle(Color(hex: "7A6A50"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(hex: "FBF3E4"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "EDD9B4"), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var photoCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "fork.knife.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(46)
                        .foregroundStyle(accent.opacity(0.72))
                        .background(Theme.Colors.secondarySurface)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipped()

            Button(action: onReplacePhoto) {
                Text("更换图片")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color(hex: "2E3438").opacity(0.76), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .overlay(alignment: .topLeading) {
            Label("识别完成", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(hex: "239A70"))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color(hex: "EDF9F4"), in: Capsule())
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var recognitionCard: some View {
        VStack(spacing: 0) {
            cardHeader("识别结果", detail: "共识别 \(foods.count) 种食物")

            ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                if index > 0 { Divider().padding(.leading, 44) }
                foodRow(food, index: index)
            }

            // 补充 AI 遗漏的食物：复用手动编辑面板，新增项来源标记为用户输入。
            Button {
                let newItem = MealFoodItem(
                    id: "meal-food-manual-\(UUID().uuidString)",
                    name: "",
                    calories: 0,
                    nutritionSource: .userEntered,
                    wasEditedByUser: true
                )
                foods.append(newItem)
                editingFood = newItem
                onEdited()
            } label: {
                Label("添加遗漏食物", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)

            if foods.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("没有识别到明确食物")
                        .font(.subheadline.weight(.bold))
                    Text("可以重新拍摄、换一张照片，或手动录入这餐。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }
        }
        .resultCard()
    }

    private func foodRow(_ food: MealFoodItem, index: Int) -> some View {
        Button { editingFood = food } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(foodTint(index))
                    .frame(width: 34, height: 22)
                    .overlay { Circle().fill(.white).frame(width: 8, height: 8) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name.isEmpty ? "未命名食物" : food.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if isLowConfidenceItem(food) {
                        Label("待确认", systemImage: "questionmark.circle")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(hex: "B98A3C"))
                    }
                }
                Spacer(minLength: 6)
                Text(servingText(food))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(food.calories) 千卡")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "20252D"))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: "A1A9B2"))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 34)
        .padding(.horizontal, 16)
        .accessibilityLabel(foodAccessibilityLabel(food))
        .accessibilityHint("查看详情并修改")
    }

    /// 置信度低于阈值且用户尚未编辑过的识别项，在低置信度场景下需要重点核对。
    private func isLowConfidenceItem(_ food: MealFoodItem) -> Bool {
        isLowConfidence && !food.wasEditedByUser && (food.confidence ?? 0) < 0.7
    }

    /// 份量文案带"约"，避免伪精度（AI 估算无法给出精确克数）。
    private func servingText(_ food: MealFoodItem) -> String {
        guard let amount = food.servingAmount, amount > 0 else { return "" }
        let unit = food.servingUnit ?? "g"
        return String(localized: "约 \(Int(amount.rounded())) \(unit)")
    }

    private func foodAccessibilityLabel(_ food: MealFoodItem) -> String {
        let name = food.name.isEmpty ? String(localized: "未命名食物") : food.name
        var parts: [String] = [name]
        if let amount = food.servingAmount, amount > 0 {
            parts.append(String(localized: "约 \(Int(amount.rounded())) \(food.servingUnit ?? "g")"))
        }
        parts.append(String(localized: "估算 \(food.calories) 千卡"))
        parts.append(String(localized: "可编辑"))
        return parts.joined(separator: "，")
    }

    private var nutritionTotalCard: some View {
        VStack(spacing: 8) {
            cardHeader("营养总计", detail: "基于 AI 识别结果估算")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(totalCalories)")
                            .font(.title.weight(.bold))
                        Text("千卡").font(.caption2)
                    }
                    Text("本餐总热量")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(width: 110, height: 52, alignment: .leading)
                .background(Color(hex: "EFFAF5"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                macroColumn("蛋白质", value: protein, tint: Color(hex: "57BF91"))
                macroColumn("碳水", value: carbohydrates, tint: Color(hex: "57BF91"))
                macroColumn("脂肪", value: fat, tint: Color(hex: "E9B66D"))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .resultCard()
    }

    private func macroColumn(_ title: LocalizedStringKey, value: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(hex: "596273"))
            Text(value.map { "\(Int($0.rounded())) g" } ?? "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            ProgressView(value: value.map { min($0 / 60, 1) } ?? 0)
                .tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var analysisCard: some View {
        VStack(spacing: 6) {
            cardHeader("营养分析") {
                Text("AI 分析")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: "269A71"))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color(hex: "EEF8F4"), in: Capsule())
            }
            HStack(spacing: 12) {
                Image(systemName: analysisSymbol)
                    .font(.body.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: "EFFAF5"), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysisTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(analysisDetail)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(hex: "A1A9B2"))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .resultCard()
    }

    private var mealSlotCard: some View {
        HStack(spacing: 10) {
            Text("记录为哪一餐")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
            Picker("记录为哪一餐", selection: $selectedSlot) {
                ForEach(MealSlot.allCases) { slot in Text(slot.title).tag(slot) }
            }
            .pickerStyle(.segmented)
            .frame(width: 198)
            .onChange(of: selectedSlot) { _, _ in
                onEdited()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .resultCard(cornerRadius: 22)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: onRetry) {
                Text("重新识别")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Color(hex: "30343B"))

            Button {
                onSave(selectedSlot, foods)
            } label: {
                Text("记录本餐")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(foods.isEmpty)
            .opacity(foods.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func cardHeader(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        cardHeader(title) {
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func cardHeader<Trailing: View>(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func sumMacro(_ keyPath: KeyPath<MealFoodItem, Double?>) -> Double? {
        let values = foods.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func foodTint(_ index: Int) -> Color {
        ["F0C7A5", "A8D7B0", "CDBA95", "B8D989"].map { Color(hex: $0) }[index % 4]
    }

    private var analysisSymbol: String { protein == nil ? "sparkles" : "arrow.up.right" }
    private var analysisTitle: String {
        protein == nil ? String(localized: "已完成热量估算") : String(localized: "宏量营养素已完成估算")
    }
    private var analysisDetail: String {
        protein == nil
            ? String(localized: "食物份量和营养素仍需你确认。")
            : String(localized: "保存前请核对识别结果与实际份量。")
    }
}

struct MealFoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let food: MealFoodItem
    let onSave: (MealFoodItem) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var calories: Int
    @State private var protein: Double
    @State private var carbohydrates: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var amount: Double
    @State private var amountEnabled: Bool

    init(food: MealFoodItem, onSave: @escaping (MealFoodItem) -> Void, onDelete: @escaping () -> Void) {
        self.food = food
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: food.name)
        _calories = State(initialValue: food.calories)
        _protein = State(initialValue: food.proteinGrams ?? 0)
        _carbohydrates = State(initialValue: food.carbohydrateGrams ?? 0)
        _fat = State(initialValue: food.fatGrams ?? 0)
        _fiber = State(initialValue: food.fiberGrams ?? 0)
        _amount = State(initialValue: food.servingAmount ?? 100)
        // 无份量基准（手动新增项）不启用按比例换算，避免 0 克基准的除零缩放。
        _amountEnabled = State(initialValue: (food.servingAmount ?? 0) > 0)
    }

    /// 份量变化时按比例重算营养值；关闭份量时保持手工数值不动。
    private func applyAmountScale(_ newAmount: Double) {
        guard amountEnabled else {
            amount = newAmount
            return
        }
        let scaled = food.scaled(to: newAmount)
        calories = scaled.calories
        protein = scaled.proteinGrams ?? 0
        carbohydrates = scaled.carbohydrateGrams ?? 0
        fat = scaled.fatGrams ?? 0
        fiber = scaled.fiberGrams ?? 0
        amount = newAmount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("食物信息") {
                    TextField("食物名称", text: $name)
                    if amountEnabled {
                        Stepper("份量  约 \(Int(amount.rounded())) \(food.servingUnit ?? "g")", value: Binding(
                            get: { amount },
                            set: { applyAmountScale($0) }
                        ), in: 0...10_000, step: 5)
                    } else {
                        Stepper("份量  \(Int(amount.rounded())) \(food.servingUnit ?? "g")", value: $amount, in: 0...10_000, step: 5)
                    }
                    Stepper("热量  \(calories) 千卡", value: $calories, in: 0...5_000, step: 10)
                }
                Section("营养素") {
                    nutrientStepper("蛋白质", value: $protein)
                    nutrientStepper("碳水", value: $carbohydrates)
                    nutrientStepper("脂肪", value: $fat)
                    nutrientStepper("膳食纤维", value: $fiber)
                }
                Section {
                    Button("删除此食物", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = food
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.calories = calories
                        updated.proteinGrams = protein
                        updated.carbohydrateGrams = carbohydrates
                        updated.fatGrams = fat
                        updated.fiberGrams = fiber
                        updated.servingAmount = amount
                        updated.wasEditedByUser = true
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func nutrientStepper(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...500, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) g").foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    func resultCard(cornerRadius: CGFloat = 24) -> some View {
        background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
            }
    }
}
