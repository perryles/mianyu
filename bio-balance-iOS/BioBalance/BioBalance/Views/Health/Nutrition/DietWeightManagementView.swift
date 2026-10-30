/// 饮食和体重管理主页，对照设计稿：
/// 冷灰紫底 + 顶部斜纹装饰 Header + 三列热量总览 + 三餐简表（状态色）+ 营养汇总（绿/紫/蓝）
/// + 饮食人生横向大卡（多色渐变边框）+ 饮食规律橙红渐变时间轴（空窗斜纹）。
/// 数据来源：DrinkExperienceStore 餐食记录 + HealthKit 能量消耗（不可用时降级提示）。

import PhotosUI
import SwiftUI
import UIKit

// MARK: - Design Tokens（采样自设计稿）

enum DietDesignTokens {
    // 基础色
    static let background = Theme.Colors.pageBackground
    static let textPrimary = Theme.Colors.textPrimary
    static let textSecondary = Theme.Colors.textSecondary
    static let textTertiary = Theme.Colors.textTertiary
    static let divider = Color(hex: "DFDEE4")
    static let glassWhite = Color.white.opacity(0.78)

    // 品牌色与状态色
    static let accentOrange = Color(hex: "FF8B2B")
    static let accentRed = Color(hex: "FD595A")
    static let accentPink = Color(hex: "FB5B95")
    static let accentBlue = Color(hex: "4B9CEB")
    static let accentGreen = Color(hex: "35C95A")
    static let accentPurple = Color(hex: "8B58DF")

    // 营养分类固定映射：蛋白=绿 / 脂肪=紫 / 碳水=蓝
    static let proteinTint = accentGreen
    static let fatTint = accentPurple
    static let carbTint = accentBlue

    // 柔和表面色
    static let warningSoft = Color(hex: "F3E0E2")
    static let breakfastSoft = Color(hex: "FFF4E8")
    static let lunchSoft = Color(hex: "EDF8EA")
    static let dinnerSoft = Color(hex: "EEF1FC")
    static let timelineSoft = Color(hex: "FEE1C1")

    // 时间轴
    static let timelineOrange = Color(hex: "FF922D")
    static let timelineRedOrange = Color(hex: "FF6535")

    /// 餐次卡片底色
    static func slotSurface(_ slot: MealSlot) -> Color {
        switch slot {
        case .breakfast: return breakfastSoft
        case .lunch: return lunchSoft
        case .dinner: return dinnerSoft
        case .snack: return timelineSoft
        }
    }

    /// 餐次强调色（进度渐变起点）
    static func slotAccent(_ slot: MealSlot) -> Color {
        switch slot {
        case .breakfast: return Color(hex: "FF8428")
        case .lunch: return Color(hex: "5FB86C")
        case .dinner: return Color(hex: "7195F9")
        case .snack: return Color(hex: "8B9D73")
        }
    }

    /// 餐次进度渐变终点（粉）
    static func slotGradientEnd(_ slot: MealSlot) -> Color {
        switch slot {
        case .breakfast: return accentPink
        case .lunch: return Color(hex: "3FA986")
        case .dinner: return Color(hex: "8B58DF")
        case .snack: return Color(hex: "6F9178")
        }
    }

    /// 餐次 emoji
    static func slotEmojis(_ slot: MealSlot) -> [String] {
        switch slot {
        case .breakfast: return ["☕️", "🍞", "🥛"]
        case .lunch: return ["🥣", "🍗", "🥗", "🥤"]
        case .dinner: return ["🍲", "🐟", "🥬"]
        case .snack: return ["🥛", "🥜"]
        }
    }
}

/// 一天的能量摄入与消耗摘要；HealthKit 数据不可用时保持 nil 以区分「未授权」和「为 0」。
struct DailyEnergyBalance: Equatable {
    var intakeCalories: Int = 0
    var basalCalories: Int?
    var activeCalories: Int?
    var proteinGrams: Double = 0
    var carbohydrateGrams: Double = 0
    var fatGrams: Double = 0

    var totalBurnCalories: Int? {
        guard let basalCalories, let activeCalories else { return nil }
        return basalCalories + activeCalories
    }
}

struct DietWeightManagementView: View {
    @State private var balance = DailyEnergyBalance()
    @State private var slots: [MealSlot: MealRecognitionRecord] = [:]
    @State private var isLoadingEnergy = true
    @State private var targetCalories: Int = UserDefaults.standard.object(forKey: "dietTargetCalories") as? Int ?? 2000
    @State private var showingTargetEditor = false
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingResult: PhotoRecognitionResult?
    /// 识别中的原图，传给确认页做商品抠图展示。
    @State private var pendingPhotoImage: UIImage?
    @State private var showingManualEntry = false
    @State private var showingCoffeeConfirm = false
    @State private var isRecognizing = false
    @State private var recognitionError: String?
    @State private var selectedRecord: MealRecognitionRecord?
    @State private var habitViewModel = HabitViewModel()

    private let store = DrinkExperienceStore.shared
    private let recognitionService = PhotoRecognitionService.shared

    /// 三餐建议分配：早餐 30%、午餐 35%、晚餐 35% 按目标卡路里取整到 10。
    private var slotSuggestions: [MealSlot: Int] {
        [
            .breakfast: Int((Double(targetCalories) * 0.30 / 10).rounded() * 10),
            .lunch: Int((Double(targetCalories) * 0.35 / 10).rounded() * 10),
            .dinner: Int((Double(targetCalories) * 0.35 / 10).rounded() * 10)
        ]
    }

    var body: some View {
        ZStack(alignment: .top) {
            DietDesignTokens.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    calorieOverviewSection
                    mealTimingSection
                    mealSlotList
                    nutritionSummaryRow
                    targetCaloriesRow
                    quickActionRow
                    dietLifeSection
                    rhythmCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }

            if isRecognizing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在识别餐食…")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(DietDesignTokens.textPrimary)
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .healthDetailNavigation(title: "饮食和体重管理")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSourcePicker = true
                } label: {
                    Image(systemName: "camera")
                        .font(.appSystem(size: 15, weight: .black))
                        .foregroundColor(DietDesignTokens.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(DietDesignTokens.glassWhite, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("拍照识别")
            }
        }
        .navigationDestination(item: $selectedRecord) { record in
            MealRecordDetailView(record: record)
        }
        .onAppear(perform: reload)
        .task {
            await loadEnergyBalance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileVitalityRecordsDidChange)) { _ in
            reload()
        }
        .confirmationDialog("选择图片来源", isPresented: $showingSourcePicker, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照") { showingCamera = true }
            }
            Button("从相册选择") { showingPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingCamera) {
            SystemImagePicker(sourceType: .camera) { image in
                handleCameraImage(image)
            }
        }   
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $selectedPhotoItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: selectedPhotoItem) { _, item in
            loadSelectedPhoto(item)
        }
        .sheet(item: $pendingResult) { result in
            FoodConfirmSheet(
                initialSlot: store.defaultMealSlot(),
                sourceTitle: "确认食物",
                stepText: "4/6",
                photoImage: pendingPhotoImage,
                initialFood: nil,
                recognizedFoods: result.recognizedFoods ?? [],
                aiSourceLabel: result.aiSourceLabel
            ) { slot, food in
                saveManualFood(slot: slot, food: food, recognition: result)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingManualEntry) {
            FoodConfirmSheet(
                initialSlot: store.defaultMealSlot(),
                sourceTitle: "手动录入",
                stepText: "3/6",
                initialFood: nil
            ) { slot, food in
                saveManualFood(slot: slot, food: food)
            }
            .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
        .sheet(isPresented: $showingCoffeeConfirm) {
            CoffeeConfirmSheet(viewModel: habitViewModel)
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }
}

// MARK: - 数据

private extension DietWeightManagementView {
    func reload() {
        let summary = store.todayMealSummary()
        slots = summary.slots

        var updated = balance
        updated.intakeCalories = summary.totalCalories
        let daily = store.meals(on: Date())
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        for record in daily {
            for food in record.recognizedFoods {
                protein += food.proteinGrams ?? 0
                carbs += food.carbohydrateGrams ?? 0
                fat += food.fatGrams ?? 0
            }
        }
        updated.proteinGrams = protein
        updated.carbohydrateGrams = carbs
        updated.fatGrams = fat
        balance = updated
    }

    func loadEnergyBalance() async {
        isLoadingEnergy = true
        let basal = try? await HealthKitManager.shared.fetchBasalEnergyBurnedOptional(on: Date())
        let active = try? await HealthKitManager.shared.fetchActiveEnergyBurnedOptional(on: Date())
        balance.basalCalories = basal ?? nil
        balance.activeCalories = active ?? nil
        isLoadingEnergy = false
    }

    func saveManualFood(slot: MealSlot, food: MealFoodItem, recognition: PhotoRecognitionResult? = nil) {
        let record = MealRecognitionRecord(
            id: UUID().uuidString,
            mealSlot: slot,
            recognizedFoods: [food],
            estimatedCalories: max(0, food.calories),
            photoFileID: nil,
            photoURL: nil,
            capturedAt: recognition?.capturedAt ?? Date(),
            locationSummary: recognition?.locationSummary?.displayText,
            aiProviderID: recognition?.aiProviderID,
            aiModel: recognition?.aiModel,
            aiConfidence: recognition?.confidence
        )
        store.saveMealRecord(record)
        pendingResult = nil
        pendingPhotoImage = nil
        reload()
    }

    func handleCameraImage(_ image: UIImage) {
        pendingPhotoImage = image
        guard let data = image.jpegData(compressionQuality: 0.95) else { return }
        recognizeImageData(data)
    }

    func recognizeImageData(_ data: Data) {
        isRecognizing = true
        recognitionError = nil
        if pendingPhotoImage == nil, let image = UIImage(data: data) {
            pendingPhotoImage = image
        }
        Task {
            let result = await recognitionService.recognize(imageData: data, useCase: .mealCalorie)
            await MainActor.run {
                isRecognizing = false
                switch result {
                case .success(let payload):
                    pendingResult = payload
                case .failure(let error):
                    recognitionError = error.localizedDescription
                }
            }
        }
    }

    func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isRecognizing = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    throw PhotoRecognitionServiceError.invalidPhotoData
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                    recognizeImageData(data)
                }
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
                    isRecognizing = false
                    recognitionError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 三列热量总览

private extension DietWeightManagementView {
    var calorieOverviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                calorieColumn(
                    title: "摄入",
                    symbol: "flame.fill",
                    symbolTint: DietDesignTokens.accentBlue,
                    value: balance.intakeCalories,
                    valueTint: DietDesignTokens.textPrimary
                )
                calorieColumnDivider
                calorieColumn(
                    title: "消耗",
                    symbol: "flame.fill",
                    symbolTint: DietDesignTokens.accentRed,
                    value: balance.totalBurnCalories ?? 0,
                    valueTint: DietDesignTokens.textPrimary,
                    caption: isLoadingEnergy ? "读取中…" : nil
                )
                calorieColumnDivider
                overeatenColumn
            }
            .frame(minHeight: 86)

            basalActiveCard
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    /// 第三列状态化：超支显示红「你多吃了」，缺口显示绿「热量缺口」，持平显示灰。
    var overeatenColumn: some View {
        let burn = balance.totalBurnCalories
        let delta = burn.map { balance.intakeCalories - $0 }
        let (title, symbol, symbolTint, value, valueTint): (String, String, Color, Int, Color)
        if let delta, delta > 0 {
            title = "你多吃了"
            symbol = "fork.knife"
            symbolTint = DietDesignTokens.accentRed
            value = delta
            valueTint = DietDesignTokens.accentRed
        } else if let delta, delta < 0 {
            title = "热量缺口"
            symbol = "figure.run"
            symbolTint = DietDesignTokens.accentGreen
            value = -delta
            valueTint = DietDesignTokens.accentGreen
        } else {
            title = "你多吃了"
            symbol = "fork.knife"
            symbolTint = DietDesignTokens.accentRed
            value = 0
            valueTint = DietDesignTokens.textTertiary
        }
        return calorieColumn(
            title: title,
            symbol: symbol,
            symbolTint: symbolTint,
            value: value,
            valueTint: valueTint
        )
    }

    var calorieColumnDivider: some View {
        Rectangle()
            .fill(DietDesignTokens.divider.opacity(0.6))
            .frame(width: 1, height: 44)
    }

    func calorieColumn(title: String, symbol: String, symbolTint: Color, value: Int, valueTint: Color, caption: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(symbolTint)
                Text(title)
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(DietDesignTokens.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.formatted())
                    .font(.appSystem(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(valueTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kcal")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }
            if let caption {
                Text(caption)
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 基础代谢 / 活动消耗虚线小卡：透明底 + 灰虚线边框，不抢三大指标层级。
    var basalActiveCard: some View {
        HStack(spacing: 0) {
            basalActiveItem(title: "基础代谢", value: balance.basalCalories)
            Rectangle()
                .fill(DietDesignTokens.divider)
                .frame(width: 1, height: 30)
            basalActiveItem(title: "活动消耗", value: balance.activeCalories)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    DietDesignTokens.dashBorder,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
    }

    func basalActiveItem(title: String, value: Int?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(DietDesignTokens.textTertiary)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map { $0.formatted() } ?? "--")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "242328"))
                Text("kcal")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }
}

// MARK: - 当前餐次提示

private extension DietWeightManagementView {
    var mealTimingSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text("当前 \(currentTimeText)")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(DietDesignTokens.textSecondary)
                    Text(currentTimingTitle)
                        .font(.appSystem(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(DietDesignTokens.textPrimary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(balance.intakeCalories.formatted())
                        .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(DietDesignTokens.accentRed)
                    Text("/ " + targetCalories.formatted())
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(DietDesignTokens.textTertiary)
                    Text("kcal · 今日目标")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(DietDesignTokens.textTertiary)
                }
            }

            // 淡粉提示卡：柔和提醒而非高危警告
            Text(timingAdviceText())
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "29272B"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    DietDesignTokens.warningSoft,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .padding(.horizontal, 16)
    }

    var currentTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    var currentTimingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return String(localized: "早餐时段") }
        if hour < 17 { return String(localized: "午餐时段") }
        return String(localized: "晚餐时段")
    }

    func timingAdviceText() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let slot = store.defaultMealSlot()
        let suggestion = slotSuggestions[slot] ?? (targetCalories / 3)
        let remaining = max(0, targetCalories - balance.intakeCalories)
        if hour >= 21 {
            return String(localized: "已进入深夜时段，尽量不再进食，给消化系统留出休息时间。")
        }
        switch slot {
        case .breakfast:
            return String(localized: "早餐时段，建议控制在 \(suggestion) kcal，蛋白质优先更能稳住上午状态。")
        case .lunch:
            return String(localized: "已进入午餐时段，建议午餐控制在 \(suggestion) kcal，避免过晚或过量。")
        case .dinner:
            return String(localized: "已进入晚餐时段，建议晚餐控制在 \(suggestion) kcal，睡前 3 小时完成进食。今日剩余 \(remaining) kcal。")
        case .snack:
            return String(localized: "当前更适合记录为加餐，请按实际份量补充记录。")
        }
    }
}

// MARK: - 三餐简表

private extension DietWeightManagementView {
    var mealSlotList: some View {
        VStack(spacing: 18) {
            ForEach(MealSlot.allCases) { slot in
                mealSlotRow(slot: slot, record: slots[slot])
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
        .padding(.horizontal, 16)
    }

    func mealSlotRow(slot: MealSlot, record: MealRecognitionRecord?) -> some View {
        let suggestion = slotSuggestions[slot] ?? (targetCalories / 3)
        let calories = record?.estimatedCalories ?? 0
        let fraction = suggestion > 0 ? min(1, Double(calories) / Double(suggestion)) : 0
        // 状态色：正常/偏低=橙，明显超额=红，无数据=灰
        let barTint: Color = record == nil
            ? DietDesignTokens.divider
            : (calories > suggestion ? DietDesignTokens.accentRed : DietDesignTokens.accentOrange)

        return VStack(spacing: 9) {
            HStack(alignment: .center) {
                Text(DietDesignTokens.slotEmojis(slot).first ?? "🍽️")
                    .font(.appSystem(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.title)
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(DietDesignTokens.textPrimary)
                    Text("建议 \(suggestion) kcal")
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(DietDesignTokens.textTertiary)
                }

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(calories.formatted())
                        .font(.appSystem(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(record == nil ? DietDesignTokens.textTertiary : (calories > suggestion ? DietDesignTokens.accentRed : DietDesignTokens.textPrimary))
                    Text("kcal")
                        .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(DietDesignTokens.textTertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "E4E3E8"))
                    Capsule()
                        .fill(barTint.gradient)
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 7)

            if let record {
                Button {
                    selectedRecord = record
                } label: {
                    HStack(spacing: 5) {
                        Text(record.recognizedFoods.map(\.name).prefix(3).joined(separator: "、"))
                            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.appSystem(size: 9, weight: .black))
                    }
                    .foregroundColor(DietDesignTokens.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(slot.title)详情")
            } else {
                Button {
                    showingSourcePicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                            .font(.appSystem(size: 11, weight: .bold))
                        Text("拍照识别这一餐")
                            .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    }
                    .foregroundColor(DietDesignTokens.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if let record { selectedRecord = record }
        }
    }
}

// MARK: - 当日营养汇总 + 目标卡路里

private extension DietWeightManagementView {
    var nutritionSummaryRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.appSystem(size: 14, weight: .black))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Text("当日营养汇总")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Spacer()
                Text(hasMacroData ? "已记录" : "待记录")
                    .font(.appSystem(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(hasMacroData ? DietDesignTokens.accentGreen : DietDesignTokens.textTertiary)
            }

            VStack(spacing: 12) {
                // 营养目标按热量占比粗略折算：蛋白 20% / 脂肪 30% / 碳水 50%
                macroRow(title: "蛋白质", grams: balance.proteinGrams, ratio: 0.20, tint: DietDesignTokens.proteinTint)
                macroRow(title: "脂肪", grams: balance.fatGrams, ratio: 0.30, tint: DietDesignTokens.fatTint)
                macroRow(title: "碳水化合物", grams: balance.carbohydrateGrams, ratio: 0.50, tint: DietDesignTokens.carbTint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 5)
        .padding(.horizontal, 16)
    }

    var hasMacroData: Bool {
        balance.proteinGrams > 0 || balance.carbohydrateGrams > 0 || balance.fatGrams > 0
    }

    /// 营养行：色点 + 名称 + 迷你进度条 + 克数；目标按 ratio 折算。
    func macroRow(title: String, grams: Double, ratio: Double, tint: Color) -> some View {
        let targetGrams = Double(targetCalories) * ratio / 4
        let fraction = targetGrams > 0 ? min(1, grams / targetGrams) : 0
        return HStack(spacing: 10) {
            Circle().fill(tint).frame(width: 9, height: 9)
            Text(title)
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(DietDesignTokens.textPrimary)
                .frame(width: 72, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.12))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(4, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(grams.rounded()))")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Text("g")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
    }

    /// 目标卡路里设置行：橙色图标 + 灰数字，不用红色（非强调）。
    var targetCaloriesRow: some View {
        Button {
            showingTargetEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dna")
                    .font(.appSystem(size: 15, weight: .black))
                    .foregroundColor(Color(hex: "FF9134"))
                Text("调整目标卡路里")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Spacer()
                Text(targetCalories.formatted() + " kcal")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 11, weight: .black))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }
            .padding(16)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingTargetEditor) {
            DietTargetCaloriesSheet(target: targetCalories) { newTarget in
                targetCalories = newTarget
                UserDefaults.standard.set(newTarget, forKey: "dietTargetCalories")
            }
            .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.46), .medium], dragIndicator: .visible)
        }
    }
}

// MARK: - 快捷操作行

private extension DietWeightManagementView {
    var quickActionRow: some View {
        VStack(spacing: 10) {
            if let recognitionError, !recognitionError.isEmpty {
                Label(recognitionError, systemImage: "exclamationmark.circle.fill")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "984B36"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(DietDesignTokens.warningSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            HStack(spacing: 10) {
                quickActionButton(
                    title: "拍照识别",
                    subtitle: "记录一餐",
                    symbol: "camera.viewfinder",
                    tint: DietDesignTokens.accentOrange
                ) {
                    showingSourcePicker = true
                }
                quickActionButton(
                    title: "手动录入",
                    subtitle: "补一份食物",
                    symbol: "square.and.pencil",
                    tint: DietDesignTokens.accentBlue
                ) {
                    showingManualEntry = true
                }
                quickActionButton(
                    title: "记录咖啡",
                    subtitle: "咖啡因打卡",
                    symbol: "cup.and.saucer.fill",
                    tint: Color(hex: "8F6645")
                ) {
                    showingCoffeeConfirm = true
                }
            }
        }
        .padding(.horizontal, 16)
    }

    func quickActionButton(title: String, subtitle: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 19, weight: .black))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.10), in: Circle())
                Text(title)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 饮食人生（横向大卡）

private extension DietWeightManagementView {
    var dietLifeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("饮食人生")
                .font(.appSystem(size: 26, weight: .black, design: .rounded))
                .foregroundColor(DietDesignTokens.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(MealSlot.allCases) { slot in
                        DietLifeSlotCard(
                            slot: slot,
                            record: slots[slot],
                            suggestion: slotSuggestions[slot] ?? (targetCalories / 3)
                        ) {
                            if slots[slot] == nil {
                                showingSourcePicker = true
                            }
                        }
                        .frame(width: 300)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// 饮食人生餐次大卡：餐次底色 + 多色渐变边框 + 渐变进度 + 食物 emoji 条。
struct DietLifeSlotCard: View {
    let slot: MealSlot
    let record: MealRecognitionRecord?
    let suggestion: Int
    let onRecord: () -> Void

    private var calories: Int { record?.estimatedCalories ?? 0 }
    private var fraction: Double { suggestion > 0 ? min(1, Double(calories) / Double(suggestion)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(slot.title)
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)

                Spacer()

                Text(timeRangeText)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "555159"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "EBE5DD"), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(calories)")
                        .font(.appSystem(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(DietDesignTokens.textPrimary)
                    Text("/ \(suggestion) kcal")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(DietDesignTokens.textTertiary)
                }
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(calories > suggestion ? DietDesignTokens.accentRed : DietDesignTokens.slotAccent(slot))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "EEE9E4"))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [DietDesignTokens.slotAccent(slot), DietDesignTokens.slotGradientEnd(slot)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 9)

            if let foodSummary = foodSummaryText {
                Text(foodSummary)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "555159"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                HStack(spacing: 6) {
                    ForEach(DietDesignTokens.slotEmojis(slot), id: \.self) { emoji in
                        Text(emoji)
                            .font(.appSystem(size: 17))
                    }
                }

                Spacer()

                Button(action: onRecord) {
                    Image(systemName: "camera.viewfinder")
                        .font(.appSystem(size: 14, weight: .black))
                        .foregroundColor(DietDesignTokens.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(DietDesignTokens.glassWhite, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("记录\(slot.title)")

                Button {
                    onRecord()
                } label: {
                    Image(systemName: "plus")
                        .font(.appSystem(size: 14, weight: .black))
                        .foregroundColor(DietDesignTokens.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(DietDesignTokens.glassWhite, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("手动录入\(slot.title)")
            }
        }
        .padding(16)
        .background(DietDesignTokens.slotSurface(slot), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            // 多色不规则渐变边框：Orange → Pink → Blue → Yellow
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hex: "FF9645"),
                            Color(hex: "F55A9A"),
                            Color(hex: "7195F9"),
                            Color(hex: "FFD05C")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.6
                )
        )
        .shadow(color: DietDesignTokens.slotAccent(slot).opacity(0.10), radius: 14, x: 0, y: 7)
    }

    /// 已记录时显示食物明细摘要；未记录返回 nil。
    private var foodSummaryText: String? {
        guard let record, !record.recognizedFoods.isEmpty else { return nil }
        return record.recognizedFoods.map { "\($0.name) \($0.calories)kcal" }.prefix(3).joined(separator: " · ")
    }

    private var timeRangeText: String {
        if let start = record?.capturedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: start)
        }
        switch slot {
        case .breakfast: return "07:00 - 09:00"
        case .lunch: return "11:30 - 13:30"
        case .dinner: return "18:00 - 20:00"
        case .snack: return "15:00 - 17:00"
        }
    }
}

// MARK: - 饮食规律时间轴

private extension DietWeightManagementView {
    var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("饮食规律")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(balance.intakeCalories.formatted())
                        .font(.appSystem(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "FFE9C8"))
                    Text("/ " + targetCalories.formatted() + " kcal")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.onAccent.opacity(0.72))
                }
            }

            DietRhythmTimeline(records: store.meals(on: Date()), now: Date())
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [DietDesignTokens.timelineOrange, DietDesignTokens.timelineRedOrange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .padding(.horizontal, 16)
    }
}

/// 饮食规律时间轴：每小时一节竖向胶囊；有记录显示食物 emoji，空窗期用斜纹。
struct DietRhythmTimeline: View {
    let records: [MealRecognitionRecord]
    let now: Date
    private let startHour = 7
    private let endHour = 22

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        timelineHourColumn(hour)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Text("横向滑动查看全天")
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent.opacity(0.66))
            }
        }
    }

    private func timelineHourColumn(_ hour: Int) -> some View {
        let hourRecords = records.filter { Calendar.current.component(.hour, from: $0.capturedAt) == hour }
        let currentHour = Calendar.current.component(.hour, from: now)
        let isCurrent = hour == currentHour
        let isFuture = currentHour < hour
        let height: CGFloat = hourRecords.isEmpty ? 46 : 76

        return VStack(spacing: 5) {
            ZStack {
                if hourRecords.isEmpty {
                    // 空窗期：浅桃色 + 斜纹
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(DietDesignTokens.timelineSoft.opacity(isFuture ? 0.45 : 0.9))
                    TimelineStripePattern()
                        .opacity(0.18)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(hex: "FFE1BF"))
                }

                if !hourRecords.isEmpty {
                    VStack(spacing: 3) {
                        ForEach(Array(hourRecords.prefix(3))) { record in
                            Text(DietDesignTokens.slotEmojis(record.mealSlot).first ?? "🍽️")
                                .font(.appSystem(size: 15))
                        }
                        if hourRecords.count > 3 {
                            Text("+\(hourRecords.count - 3)")
                                .font(.appSystem(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "8A5B33"))
                        }
                    }
                }

                // 当前小时描边指示
                if isCurrent {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.6)
                }
            }
            .frame(width: 42, height: height)

            if isCurrent {
                Text("现在")
                    .font(.appSystem(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.surface.opacity(0.24), in: Capsule())
            } else {
                Text(String(format: "%02d:00", hour))
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent.opacity(0.78))
            }
        }
    }
}

// MARK: - 样式与辅助

/// 时间轴空窗期斜纹。
struct TimelineStripePattern: View {
    var body: some View {
        Canvas { context, size in
            let stripe = Path { path in
                let step: CGFloat = 7
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += step
                }
            }
            context.stroke(stripe, with: .color(Color(hex: "DCA58E").opacity(0.35)), lineWidth: 2)
        }
        .clipped()
    }
}

extension DietDesignTokens {
    static let dashBorder = Color(hex: "C9C7CE")
}

extension View {
    /// 详情页卡片外观（MealRecordDetailView 复用）。
    func dietSurface() -> some View {
        background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}

/// 目标卡路里编辑 sheet。
struct DietTargetCaloriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Double
    let onSave: (Int) -> Void

    init(target: Int, onSave: @escaping (Int) -> Void) {
        _draft = State(initialValue: Double(target))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("调整目标卡路里")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 14, weight: .black))
                        .foregroundColor(DietDesignTokens.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Theme.Colors.secondarySurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(draft.rounded()))")
                    .font(.appSystem(size: 54, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textPrimary)
                Text("kcal / 日")
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(DietDesignTokens.textTertiary)
            }

            Text("推荐范围：1200 – 3500 kcal，可咨询专业人士后调整。")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(DietDesignTokens.textSecondary)

            Slider(value: $draft, in: 1000...4000, step: 50)
                .tint(DietDesignTokens.accentOrange)

            Button {
                onSave(Int(draft.rounded()))
                dismiss()
            } label: {
                Text("保 存")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DietDesignTokens.accentOrange, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
    }
}
