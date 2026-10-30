/// 确认食物 Sheet，对照设计稿布局：
/// 顶部（关闭 × / 步骤 n/6 / 居中标题）→ 商品图居中 → 食物名 / 热量 / 三列营养素 / 份量
/// → 餐次分段（早/午/晚）→ 橙色大圆角保存按钮。
/// 服务三个入口：AI 识别结果确认、手动录入、扫描预填。

import SwiftUI

struct FoodConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialSlot: MealSlot
    let sourceTitle: String
    /// 设计稿中的步骤指示；不同入口传入不同序号。
    var stepText: String = "1/6"
    /// 识别照片；识别入口传入原图，手动录入时为空。
    var photoImage: UIImage? = nil
    /// 预填食物（如扫描或历史记录）；nil 时视为新建。
    let initialFood: MealFoodItem?
    /// AI 识别出的多种食物草稿；非空时先选择要保存的条目。
    var recognizedFoods: [MealFoodItem] = []
    var aiSourceLabel: String? = nil
    let onSave: (MealSlot, MealFoodItem) -> Void

    @State private var selectedSlot: MealSlot
    @State private var foodName: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var portionText = ""
    @State private var selectedRecognizedID: String?
    /// 抠图完成后的去背景商品主体图；失败时回退原图。
    @State private var cutoutPhoto: UIImage? = nil
    @State private var isCuttingOut = false

    private let saveTint = Color(hex: "F08A3C")

    init(
        initialSlot: MealSlot,
        sourceTitle: String,
        stepText: String = "1/6",
        photoImage: UIImage? = nil,
        initialFood: MealFoodItem?,
        recognizedFoods: [MealFoodItem] = [],
        aiSourceLabel: String? = nil,
        onSave: @escaping (MealSlot, MealFoodItem) -> Void
    ) {
        self.initialSlot = initialSlot
        self.sourceTitle = sourceTitle
        self.stepText = stepText
        self.photoImage = photoImage
        self.initialFood = initialFood
        self.recognizedFoods = recognizedFoods
        self.aiSourceLabel = aiSourceLabel
        self.onSave = onSave
        self.selectedSlot = initialSlot
        self.foodName = initialFood?.name ?? ""
        self.caloriesText = initialFood.map { String($0.calories) } ?? ""
        self.proteinText = initialFood?.proteinGrams.map { String(Int($0.rounded())) } ?? ""
        self.carbsText = initialFood?.carbohydrateGrams.map { String(Int($0.rounded())) } ?? ""
        self.fatText = initialFood?.fatGrams.map { String(Int($0.rounded())) } ?? ""
        self.selectedRecognizedID = recognizedFoods.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if !recognizedFoods.isEmpty {
                        recognizedFoodsPicker
                    }

                    photoSection

                    if let aiSourceLabel {
                        Label(aiSourceLabel, systemImage: "sparkles")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "2C74C9"))
                    }

                    fieldSection(title: "食物名") {
                        TextField("例如：桂格牛乳蒸糯燕麦片", text: $foodName)
                            .textInputAutocapitalization(.never)
                    }

                    fieldSection(title: "热量") {
                        HStack(spacing: 8) {
                            TextField("0", text: $caloriesText)
                                .keyboardType(.numberPad)
                            Text("kcal")
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    macroTripleSection

                    fieldSection(title: "份量") {
                        TextField("例如：一份（约40g干麦片）", text: $portionText)
                    }

                    mealSlotSection

                    if !isValid, showsValidationError {
                        Text("请填写食物名和 0 至 10000 kcal 的热量。")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "9A5A14"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }

            Button {
                save()
            } label: {
                saveButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
            .opacity(isValid ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
        .task {
            if let photoImage {
                await cutoutSubject(from: photoImage)
            }
        }
    }

    /// Vision 抠图在后台执行；失败保持原图展示，不阻塞确认流程。
    private func cutoutSubject(from image: UIImage) async {
        guard cutoutPhoto == nil else { return }
        isCuttingOut = true
        let result = await SubjectCutoutService.cutoutSubject(from: image)
        cutoutPhoto = result
        isCuttingOut = false
    }

    // MARK: - Header（关闭 × / 步骤 / 居中标题）

    private var sheetHeader: some View {
        ZStack {
            Text(sourceTitle)
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1B2F4E"))

            HStack(alignment: .top) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 15, weight: .black))
                        .foregroundColor(Color(hex: "3D4A5C"))
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.secondarySurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")

                Spacer()

                Text(stepText)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 商品图（抠出主体，透明背景居中）

    @ViewBuilder
    private var photoSection: some View {
        let image = cutoutPhoto ?? photoImage
        if let image {
            ZStack {
                if cutoutPhoto != nil {
                    // 抠图成功：浅色渐变衬托透明主体
                    LinearGradient(
                        colors: [Color(hex: "F3F8FF"), Color(hex: "EAF2FB")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.black.opacity(cutoutPhoto == nil ? 0 : 0.10), radius: 12, x: 0, y: 6)

                if isCuttingOut {
                    VStack(spacing: 6) {
                        ProgressView()
                        Text("正在抠出商品…")
                            .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "5A6B62"))
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .accessibilityLabel("商品照片")
        }
    }

    // MARK: - 识别候选（横向胶囊）

    private var recognizedFoodsPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("识别结果")
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3D4A5C"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recognizedFoods) { food in
                        Button {
                            selectedRecognizedID = food.id
                            applyRecognized(food)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(food.name)
                                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                                    .lineLimit(1)
                                Text("\(food.calories) kcal")
                                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(selectedRecognizedID == food.id ? .white : Color(hex: "2C74C9"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                selectedRecognizedID == food.id ? Color(hex: "2C74C9") : Color(hex: "2C74C9").opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 三列营养素

    private var macroTripleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("蛋白质 · 碳水化合物 · 脂肪")
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3D4A5C"))
            HStack(spacing: 10) {
                macroColumn(title: "蛋白质", text: $proteinText, tint: Color(hex: "E68A3F"))
                macroColumn(title: "碳水化合物", text: $carbsText, tint: Color(hex: "4E98E7"))
                macroColumn(title: "脂肪", text: $fatText, tint: Color(hex: "F3A53B"))
            }
        }
    }

    private func macroColumn(title: String, text: Binding<String>, tint: Color) -> some View {
        VStack(spacing: 6) {
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("g")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "5A6B62"))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 餐次分段

    private var mealSlotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("餐次")
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3D4A5C"))
            HStack(spacing: 0) {
                ForEach(MealSlot.allCases) { slot in
                    slotButton(slot)
                }
            }
            .padding(4)
            .background(Color(hex: "EDF1F6"), in: Capsule())
        }
    }

    private func slotButton(_ slot: MealSlot) -> some View {
        let isSelected = selectedSlot == slot
        return Button {
            selectedSlot = slot
        } label: {
            Text(slot.title)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: "5A6B62"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isSelected ? saveTint : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 字段

    private func fieldSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3D4A5C"))
            content()
                .font(.appSystem(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "2B3B4E"))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - 保存

    private var saveButtonLabel: some View {
        Text("保存")
            .font(.appSystem(size: 17, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(saveTint, in: Capsule())
    }

    private var showsValidationError: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !caloriesText.isEmpty
    }

    private var normalizedCalories: Int? {
        guard let value = Int(caloriesText), (0...10_000).contains(value) else { return nil }
        return value
    }

    private var isValid: Bool {
        !normalizedName.isEmpty && normalizedCalories != nil
    }

    private var normalizedName: String {
        foodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applyRecognized(_ food: MealFoodItem) {
        foodName = food.name
        caloriesText = String(food.calories)
        proteinText = food.proteinGrams.map { String(Int($0.rounded())) } ?? ""
        carbsText = food.carbohydrateGrams.map { String(Int($0.rounded())) } ?? ""
        fatText = food.fatGrams.map { String(Int($0.rounded())) } ?? ""
    }

    private func save() {
        guard let calories = normalizedCalories else { return }
        let protein = Double(proteinText)
        let carbs = Double(carbsText)
        let fat = Double(fatText)
        let food = MealFoodItem(
            id: selectedRecognizedID ?? UUID().uuidString,
            name: normalizedName,
            calories: calories,
            proteinGrams: protein.flatMap { $0 >= 0 ? $0 : nil },
            carbohydrateGrams: carbs.flatMap { $0 >= 0 ? $0 : nil },
            fatGrams: fat.flatMap { $0 >= 0 ? $0 : nil }
        )
        onSave(selectedSlot, food)
        dismiss()
    }
}
