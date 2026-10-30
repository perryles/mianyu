/// Drink Checkin Sheet 负责统一饮品打卡体验，承载饮品选择、容量输入与快捷记录。
import SwiftUI

enum DrinkCategory: String, CaseIterable, Identifiable {
    case hydration
    case coffee
    case tea
    case milk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hydration: return String(localized: "补水")
        case .coffee: return String(localized: "咖啡")
        case .tea: return String(localized: "茶")
        case .milk: return String(localized: "奶饮")
        }
    }
}

struct DrinkRecordPayload: Sendable {
    let waterAmountMl: Int
    let caffeineAmountMg: Int
}

struct DrinkPreset: Identifiable, Equatable, Sendable {
    let id: String
    let category: DrinkCategory
    let title: String
    let subtitle: String
    let amountMl: Int
    let caffeineMgPer250Ml: Int
    let symbol: String
    let tintHex: String

    var payload: DrinkRecordPayload {
        let caffeineAmount = Int((Double(amountMl) / 250.0 * Double(caffeineMgPer250Ml)).rounded())
        return DrinkRecordPayload(
            waterAmountMl: amountMl,
            caffeineAmountMg: max(0, caffeineAmount)
        )
    }

    func payload(for amountMl: Int) -> DrinkRecordPayload {
        let normalizedAmount = max(0, amountMl)
        let caffeineAmount = Int((Double(normalizedAmount) / 250.0 * Double(caffeineMgPer250Ml)).rounded())
        return DrinkRecordPayload(
            waterAmountMl: normalizedAmount,
            caffeineAmountMg: max(0, caffeineAmount)
        )
    }

    static let water = DrinkPreset(
        id: "water",
        category: .hydration,
        title: "水",
        subtitle: "基础补水",
        amountMl: 100,
        caffeineMgPer250Ml: 0,
        symbol: "drop.fill",
        tintHex: "4E98E7"
    )

    static let mineralWater = DrinkPreset(
        id: "mineralWater",
        category: .hydration,
        title: "矿泉水",
        subtitle: "清爽补水",
        amountMl: 300,
        caffeineMgPer250Ml: 0,
        symbol: "waterbottle.fill",
        tintHex: "63A8F1"
    )

    static let americano = DrinkPreset(
        id: "americano",
        category: .coffee,
        title: "美式咖啡",
        subtitle: "120mg 咖啡因 / 250ml",
        amountMl: 250,
        caffeineMgPer250Ml: 120,
        symbol: "cup.and.saucer.fill",
        tintHex: "8F6645"
    )

    static let latte = DrinkPreset(
        id: "latte",
        category: .coffee,
        title: "拿铁",
        subtitle: "75mg 咖啡因 / 250ml",
        amountMl: 250,
        caffeineMgPer250Ml: 75,
        symbol: "mug.fill",
        tintHex: "A17A57"
    )

    static let tea = DrinkPreset(
        id: "tea",
        category: .tea,
        title: "茶",
        subtitle: "日常轻饮",
        amountMl: 180,
        caffeineMgPer250Ml: 0,
        symbol: "leaf.fill",
        tintHex: "86B55A"
    )

    static let blackTea = DrinkPreset(
        id: "blackTea",
        category: .tea,
        title: "红茶",
        subtitle: "45mg 咖啡因 / 250ml",
        amountMl: 355,
        caffeineMgPer250Ml: 45,
        symbol: "leaf.fill",
        tintHex: "B98545"
    )

    static let greenTea = DrinkPreset(
        id: "greenTea",
        category: .tea,
        title: "绿茶",
        subtitle: "30mg 咖啡因 / 250ml",
        amountMl: 355,
        caffeineMgPer250Ml: 30,
        symbol: "leaf.fill",
        tintHex: "86B55A"
    )

    static let milkTea = DrinkPreset(
        id: "milkTea",
        category: .coffee,
        title: "奶茶",
        subtitle: "60mg 咖啡因 / 250ml",
        amountMl: 355,
        caffeineMgPer250Ml: 60,
        symbol: "cup.and.saucer.fill",
        tintHex: "C79752"
    )

    static let milk = DrinkPreset(
        id: "milk",
        category: .milk,
        title: "牛奶",
        subtitle: "奶饮补充",
        amountMl: 250,
        caffeineMgPer250Ml: 0,
        symbol: "carton.fill",
        tintHex: "73B5D7"
    )

    static let soyMilk = DrinkPreset(
        id: "soyMilk",
        category: .milk,
        title: "豆浆",
        subtitle: "植物奶饮",
        amountMl: 250,
        caffeineMgPer250Ml: 0,
        symbol: "takeoutbag.and.cup.and.straw.fill",
        tintHex: "C2A56A"
    )

    static let all: [DrinkPreset] = [
        .water,
        .mineralWater,
        .americano,
        .latte,
        .tea,
        .blackTea,
        .greenTea,
        .milkTea,
        .milk,
        .soyMilk
    ]

    static let quickFavorites: [DrinkPreset] = [
        .water,
        .milk,
        .americano,
        .tea
    ]
}

struct DrinkCheckinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: HabitViewModel
    let initialPreset: DrinkPreset?

    @State private var selectedCategory: DrinkCategory = .hydration
    @State private var selectedPresetID: String = DrinkPreset.water.id
    @State private var showingCustomAmount = false
    @State private var showingWaterSettings = false
    @State private var recentRecords: [DrinkRecentRecord] = []
    @State private var pendingDeleteRecord: DrinkRecentRecord?

    init(viewModel: HabitViewModel, initialPreset: DrinkPreset? = nil) {
        self.viewModel = viewModel
        self.initialPreset = initialPreset
    }

    var body: some View {
        ZStack {
            drinkPageBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    drinkPageHeader

                    if isHydrationMode {
                        waterTrackingHero
                        waterQuickAmountRow
                    } else {
                        caffeineTrackingHero
                        caffeinePresetGrid
                    }

                    drinkStatsSection
                    drinkRecordSection
                }
                .padding(.bottom, 34)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCustomAmount) {
            DrinkCustomAmountSheet(
                title: isHydrationMode ? "自定义添加" : "手动录入",
                helperText: isHydrationMode ? nil : "按饮品容量估算咖啡因，会同步写入健康 App。",
                unit: "ml",
                accent: activeAccentColor,
                defaultAmount: selectedPreset.amountMl
            ) { amount in
                record(amountMl: amount, preset: selectedPreset)
            }
            .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.42), .medium], dragIndicator: .visible)
        }
        .sheet(isPresented: $showingWaterSettings) {
            DrinkWaterSettingsSheet(
                targetMl: viewModel.waterTarget,
                accent: waterAccent,
                onSave: { target in
                    updateWaterTarget(target)
                }
            )
            .adaptiveSheetChrome(style: .reading, detents: [.fraction(0.52), .medium], dragIndicator: .hidden)
        }
        .confirmationDialog(
            "确定要删除这条记录吗？",
            isPresented: Binding(
                get: { pendingDeleteRecord != nil },
                set: { if !$0 { pendingDeleteRecord = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDeleteRecord {
                    deleteRecentRecord(pendingDeleteRecord)
                }
                pendingDeleteRecord = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteRecord = nil
            }
        }
        .onAppear(perform: configureInitialState)
    }
}

private struct DrinkRecentRecord: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let date: Date
    let symbol: String
    let tint: Color
    let waterAmountMl: Int
    let caffeineAmountMg: Int

    var time: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

private extension DrinkCheckinSheet {
    var isHydrationMode: Bool {
        selectedCategory == .hydration
    }

    var waterAccent: Color { Color(hex: "2FC4CF") }
    var caffeineAccent: Color { Color(hex: "E7A13A") }

    var activeAccentColor: Color {
        isHydrationMode ? waterAccent : caffeineAccent
    }

    var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "M月d日 E"
        return formatter.string(from: Date())
    }

    var waterProgressPercent: Int {
        guard viewModel.waterTarget > 0 else { return 0 }
        return Int((min(1, Double(viewModel.waterAmount) / Double(max(1, viewModel.waterTarget))) * 100).rounded())
    }

    var caffeineProgressPercent: Int {
        Int((min(1, Double(viewModel.caffeineAmount) / Double(max(1, caffeineTargetMg))) * 100).rounded())
    }

    var activeAmount: Int {
        isHydrationMode ? viewModel.waterAmount : viewModel.caffeineAmount
    }

    var activeUnit: String {
        isHydrationMode ? "ml" : "mg"
    }

    var activeProgressPercent: Int {
        isHydrationMode ? waterProgressPercent : caffeineProgressPercent
    }

    var activeTargetText: String {
        isHydrationMode ? "\(viewModel.waterTarget.formatted())ml" : "\(caffeineTargetMg.formatted())mg"
    }

    var caffeineTargetMg: Int { 400 }

    var drinkPageBackground: some View {
        ZStack(alignment: .bottom) {
            Color.black
            (isHydrationMode ? Color(hex: "AAE5F3") : Color(hex: "EBCB98"))
                .ignoresSafeArea(edges: .bottom)
            Color(hex: "F7F7F7")
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    var drinkPageHeader: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 18, weight: .black))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 50, height: 50)
                        .background(Theme.Colors.surface.opacity(0.58), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
                .accessibilityLabel("关闭")

                Menu {
                    Button("饮水") {
                        selectedCategory = .hydration
                        selectedPresetID = DrinkPreset.water.id
                    }
                    Button("咖啡因") {
                        selectedCategory = .coffee
                        selectedPresetID = DrinkPreset.americano.id
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(dateTitle)
                            .font(.appSystem(size: 18, weight: .black, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.appSystem(size: 11, weight: .black))
                    }
                    .foregroundColor(Color(hex: "3C4043"))
                }

                Spacer(minLength: 0)

                Color.clear
                    .frame(width: 50, height: 50)
            }

            VStack(spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(activeAmount)")
                        .font(.appSystem(size: 54, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    Text(activeUnit)
                        .font(.appSystem(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                HStack(alignment: .center, spacing: 44) {
                    HStack(spacing: 5) {
                        Text("已完成")
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "8A8E91"))
                        Text(localizedPercent(activeProgressPercent))
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    Button {
                        if isHydrationMode {
                            showingWaterSettings = true
                        } else {
                            showingCustomAmount = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isHydrationMode ? "目标" : "建议上限")
                                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "8A8E91"))
                            Text(activeTargetText)
                                .font(.appSystem(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Image(systemName: "pencil")
                                .font(.appSystem(size: 14, weight: .black))
                                .foregroundColor(Color(hex: "B9BABC"))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            drinkModeSwitch
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(Theme.Colors.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var drinkModeSwitch: some View {
        HStack(spacing: 6) {
            drinkModeButton(title: "饮水", symbol: "drop.fill", isSelected: isHydrationMode, accent: waterAccent) {
                selectedCategory = .hydration
                selectedPresetID = DrinkPreset.water.id
            }

            drinkModeButton(title: "咖啡因", symbol: "cup.and.saucer.fill", isSelected: !isHydrationMode, accent: caffeineAccent) {
                selectedCategory = .coffee
                selectedPresetID = DrinkPreset.americano.id
            }
        }
        .padding(4)
        .background(Theme.Colors.surface.opacity(0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.86), lineWidth: 1)
        )
        .padding(.horizontal, 64)
    }

    func drinkModeButton(title: String, symbol: String, isSelected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 12, weight: .black))
                Text(title)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : Color(hex: "66727B"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isSelected ? accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    var waterTrackingHero: some View {
        ZStack(alignment: .bottom) {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .bottom) {
                    Color(hex: "F7F7F7")
                    waterWave(fill: Color(hex: "BFEFFF").opacity(0.88), phase: phase)
                        .frame(height: 112)
                    waterWave(fill: Color(hex: "8DDCED").opacity(0.62), phase: phase + 1.2)
                        .frame(height: 96)
                        .offset(y: 18)
                    floatingLemon
                        .offset(y: -36 - CGFloat(sin(phase * 1.4)) * 5)
                }
            }
        }
        .frame(height: 260)
    }

    var caffeineTrackingHero: some View {
        ZStack(alignment: .bottom) {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .bottom) {
                    Color(hex: "F7F7F7")
                    waterWave(fill: Color(hex: "EAC285").opacity(0.86), phase: phase)
                        .frame(height: 112)
                    waterWave(fill: Color(hex: "D49A5A").opacity(0.48), phase: phase + 1.2)
                        .frame(height: 96)
                        .offset(y: 18)
                    coffeeCup
                        .scaleEffect(0.78)
                        .offset(y: -42 - CGFloat(sin(phase * 1.2)) * 4)
                }
            }
        }
        .frame(height: 260)
    }

    var waterQuickAmountRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                customAmountButton(tint: waterAccent)
                ForEach([50, 100, 250, 500], id: \.self) { amount in
                    capsuleAmountButton(title: "\(amount)ml", tint: waterAccent) {
                        record(amountMl: amount, preset: .water)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .background(Color(hex: "AAE5F3"))
    }

    var caffeineQuickAmountRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                customAmountButton(tint: caffeineAccent)
                ForEach([DrinkPreset.americano, .latte, .blackTea, .milkTea, .greenTea]) { preset in
                    capsuleAmountButton(title: presetQuickTitle(preset), tint: caffeineAccent) {
                        selectedCategory = preset.category
                        selectedPresetID = preset.id
                        record(amountMl: preset.amountMl, preset: preset)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .background(Color(hex: "EBCB98"))
    }

    var caffeinePresetGrid: some View {
        caffeineQuickAmountRow
    }

    func customAmountButton(tint: Color) -> some View {
        Button {
            showingCustomAmount = true
        } label: {
            Image(systemName: "plus")
                .font(.appSystem(size: 26, weight: .black))
                .foregroundColor(.white)
                .frame(width: 68, height: 68)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("自定义用量")
    }

    func capsuleAmountButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: 25, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 26)
                .frame(height: 68)
                .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
    }

    func presetQuickTitle(_ preset: DrinkPreset) -> String {
        switch preset.id {
        case DrinkPreset.americano.id:
            return String(localized: "美式")
        case DrinkPreset.latte.id:
            return String(localized: "拿铁")
        case DrinkPreset.blackTea.id:
            return String(localized: "红茶")
        case DrinkPreset.milkTea.id:
            return String(localized: "奶茶")
        case DrinkPreset.greenTea.id:
            return String(localized: "绿茶")
        default:
            return preset.title
        }
    }

    var drinkRecordSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("历史")
                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "20242A"))

            VStack(spacing: 10) {
                if visibleRecentRecords.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: isHydrationMode ? "drop.fill" : "cup.and.saucer.fill")
                            .font(.appSystem(size: 32, weight: .black))
                            .foregroundColor(activeAccentColor.opacity(0.64))
                        Text("暂无记录")
                            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "9DA3A8"))
                    }
                    .frame(maxWidth: .infinity, minHeight: 116)
                } else {
                    ForEach(visibleRecentRecords) { record in
                        recentRecordRow(record)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(activeAccentColor)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .background(isHydrationMode ? Color(hex: "AAE5F3") : Color(hex: "EBCB98"))
    }

    var drinkStatsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            drinkStatsHeader
            drinkStatsProgressBar
            recentRecordMiniChart
            drinkStatsGrid
            Text(drinkStatsHintText)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .background(isHydrationMode ? Color(hex: "AAE5F3") : Color(hex: "EBCB98"))
    }

    var drinkStatsHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("图表统计")
                    .font(.appSystem(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "20242A"))
                Text(isHydrationMode ? "看今天补水是否追上目标。" : "看今天咖啡因是否接近建议上限。")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Text(isHydrationMode ? "今日" : "刺激负担")
                .font(.appSystem(size: 11, weight: .black, design: .rounded))
                .foregroundColor(activeAccentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(activeAccentColor.opacity(0.12), in: Capsule())
        }
    }

    var drinkStatsProgressBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(isHydrationMode ? "目标进度" : "上限占比")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text(localizedPercent(activeProgressPercent))
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(activeAccentColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(activeAccentColor.opacity(0.13))
                    Capsule()
                        .fill(activeAccentColor)
                        .frame(width: max(10, proxy.size.width * min(max(activeProgressFraction, 0), 1)))
                }
            }
            .frame(height: 10)
        }
    }

    var drinkStatsGrid: some View {
        LazyVGrid(columns: drinkStatsColumns, spacing: 10) {
            drinkStatTile(
                title: isHydrationMode ? "今日总量" : "今日摄入",
                value: "\(activeAmount)",
                unit: activeUnit,
                symbol: isHydrationMode ? "drop.fill" : "cup.and.saucer.fill",
                tint: activeAccentColor
            )
            drinkStatTile(
                title: isHydrationMode ? "剩余目标" : "剩余额度",
                value: "\(activeRemainingValue)",
                unit: activeUnit,
                symbol: isHydrationMode ? "target" : "speedometer",
                tint: isHydrationMode ? Color(hex: "5B8CFF") : Color(hex: "B87A3D")
            )
            drinkStatTile(
                title: "记录次数",
                value: "\(visibleRecentRecords.count)",
                unit: "次",
                symbol: "list.bullet.rectangle.fill",
                tint: Color(hex: "4FC7A6")
            )
            drinkStatTile(
                title: "最大单次",
                value: "\(activeLargestRecordValue)",
                unit: activeUnit,
                symbol: "chart.bar.fill",
                tint: Color(hex: "6B83E8")
            )
        }
    }

    var drinkStatsColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    var recentRecordMiniChart: some View {
        let values = activeRecentRecordValues
        let maxValue = max(values.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近记录")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text(values.isEmpty ? "暂无" : "\(values.count) 条")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(activeAccentColor)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if values.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(activeAccentColor.opacity(0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                    }
                } else {
                    ForEach(Array(values.prefix(5).enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == 0 ? activeAccentColor : activeAccentColor.opacity(0.24 + Double(index) * 0.08))
                            .frame(maxWidth: .infinity)
                            .frame(height: 18 + CGFloat(value) / CGFloat(maxValue) * 48)
                    }
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
        .padding(14)
        .background(activeAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func drinkStatTile(title: String, value: String, unit: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.appSystem(size: 13, weight: .black))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())

                Text(title)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.appSystem(size: 23, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "263238"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "9AA2AA"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var visibleRecentRecords: [DrinkRecentRecord] {
        recentRecords.filter { record in
            isHydrationMode ? record.waterAmountMl > 0 : record.caffeineAmountMg > 0
        }
    }

    var activeProgressFraction: Double {
        if isHydrationMode {
            guard viewModel.waterTarget > 0 else { return 0 }
            return min(1, Double(viewModel.waterAmount) / Double(max(1, viewModel.waterTarget)))
        }
        return min(1, Double(viewModel.caffeineAmount) / Double(max(1, caffeineTargetMg)))
    }

    var activeRemainingValue: Int {
        if isHydrationMode {
            return max(0, viewModel.waterTarget - viewModel.waterAmount)
        }
        return max(0, caffeineTargetMg - viewModel.caffeineAmount)
    }

    var activeRecentRecordValues: [Int] {
        visibleRecentRecords.map { record in
            isHydrationMode ? record.waterAmountMl : record.caffeineAmountMg
        }
    }

    var activeLargestRecordValue: Int {
        activeRecentRecordValues.max() ?? 0
    }

    var drinkStatsHintText: String {
        if visibleRecentRecords.isEmpty {
            return isHydrationMode ? "记录一杯水后，这里会出现最近记录柱状图。" : "记录一杯咖啡或茶后，这里会显示摄入负担。"
        }
        if isHydrationMode {
            if viewModel.waterAmount >= viewModel.waterTarget {
                return String(localized: "今天已达到饮水目标，后续按口渴感少量补充即可。")
            }
            return String(localized: "今天还差 \(activeRemainingValue)ml，建议分成几次小杯补齐。")
        }
        if viewModel.caffeineAmount >= caffeineTargetMg {
            return String(localized: "今日咖啡因已经接近或超过建议上限，后面适合切换到无咖啡因饮品。")
        }
        return String(localized: "今日还剩约 \(activeRemainingValue)mg 建议额度，下午后尽量少补刺激。")
    }

    func recentRecordRow(_ record: DrinkRecentRecord) -> some View {
        HStack(spacing: 16) {
            Image(systemName: record.symbol)
                .font(.appSystem(size: 18, weight: .black))
                .foregroundColor(record.tint)
                .frame(width: 48, height: 48)
                .background(record.tint.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(record.value)
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(record.time)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                pendingDeleteRecord = record
            } label: {
                Image(systemName: "trash")
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(Color(hex: "FA6B6F"), in: RoundedRectangle(cornerRadius: 0, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    func record(amountMl: Int, preset: DrinkPreset) {
        let amount = max(0, amountMl)
        guard amount > 0 else { return }
        let payload = preset.payload(for: amount)
        viewModel.recordDrink(preset: preset, amountMl: amount) { success in
            guard success else { return }
            appendRecentRecord(amountMl: amount, caffeineMg: payload.caffeineAmountMg, preset: preset)
        }
    }

    func appendRecentRecord(amountMl: Int, caffeineMg: Int, preset: DrinkPreset) {
        let isWaterRecord = preset.category == .hydration
        let value = isWaterRecord ? "+\(amountMl)ml" : "+\(caffeineMg)mg"
        let record = DrinkRecentRecord(
            title: preset.title,
            value: value,
            date: Date(),
            symbol: isWaterRecord ? "drop.fill" : "mug.fill",
            tint: isWaterRecord ? waterAccent : caffeineAccent,
            waterAmountMl: amountMl,
            caffeineAmountMg: caffeineMg
        )
        recentRecords.insert(record, at: 0)
        recentRecords = Array(recentRecords.prefix(5))
    }

    func deleteRecentRecord(_ record: DrinkRecentRecord) {
        recentRecords.removeAll { $0.id == record.id }
        if record.waterAmountMl > 0 {
            viewModel.waterAmount = max(0, viewModel.waterAmount - record.waterAmountMl)
            viewModel.waterCompletionRate = viewModel.waterTarget > 0
                ? min(1.0, Double(viewModel.waterAmount) / Double(max(1, viewModel.waterTarget)))
                : 0
        }
        if record.caffeineAmountMg > 0 {
            viewModel.caffeineAmount = max(0, viewModel.caffeineAmount - record.caffeineAmountMg)
        }
        viewModel.syncSelectedDayActionRecord()
        viewModel.persistHabitSummaryToAppGroup()
    }

    func updateWaterTarget(_ target: Int) {
        let sanitizedTarget = min(max(target, 500), 5000)
        viewModel.waterTarget = sanitizedTarget
        viewModel.waterCompletionRate = sanitizedTarget > 0
            ? min(1.0, Double(viewModel.waterAmount) / Double(max(1, sanitizedTarget)))
            : 0
        viewModel.syncSelectedDayActionRecord()
        viewModel.persistHabitSummaryToAppGroup()
    }

    func waterWave(fill: Color, phase: TimeInterval) -> some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                let baseY = height * 0.55
                path.move(to: CGPoint(x: 0, y: baseY))
                for x in stride(from: 0, through: width, by: 8) {
                    let progress = x / max(width, 1)
                    let y = baseY + CGFloat(sin(progress * .pi * 2 + phase)) * 20
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(fill)
        }
    }

    var floatingLemon: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: "C8F0FF").opacity(0.72))
                .frame(width: 170, height: 88)
                .overlay {
                    Ellipse()
                        .stroke(Color.white.opacity(0.76), lineWidth: 20)
                }
                .offset(y: 44)
            Ellipse()
                .fill(Color(hex: "FFE500"))
                .frame(width: 118, height: 102)
                .rotationEffect(.degrees(-8))
                .offset(y: -4)
            Circle()
                .fill(Color(hex: "FFE500"))
                .frame(width: 36, height: 36)
                .offset(x: -54, y: 24)
            Circle()
                .fill(Color(hex: "42BFF0"))
                .frame(width: 38, height: 42)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color(hex: "AEEBFF"))
                        .frame(width: 34, height: 8)
                        .offset(y: 2)
                }
                .offset(x: -32, y: -30)
            Capsule()
                .fill(Color(hex: "5DBB59"))
                .frame(width: 36, height: 22)
                .rotationEffect(.degrees(48))
                .offset(x: 44, y: -34)
            HStack(spacing: 14) {
                Circle().fill(Color(hex: "7C563D")).frame(width: 4, height: 4)
                Circle().fill(Color(hex: "7C563D")).frame(width: 4, height: 4)
            }
            .offset(y: -6)
            Capsule()
                .stroke(Color(hex: "7C563D"), lineWidth: 2)
                .frame(width: 18, height: 10)
                .clipShape(Rectangle().offset(y: 5))
                .offset(y: 4)
        }
    }

    func bubbleField(phase: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .stroke(Color(hex: "9AE9FF").opacity(0.52), lineWidth: 2)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .frame(width: CGFloat([24, 14, 34, 18, 28, 11, 38, 16][index]))
                    .offset(
                        x: CGFloat([-180, -70, 40, 130, 185, -15, 160, 75][index]),
                        y: CGFloat([-120, -210, -96, -178, -60, -270, -250, -25][index]) + CGFloat(sin(phase + Double(index)) * 10)
                    )
            }
        }
    }

    var coffeeCup: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: "EFE8CC"))
                .frame(width: 260, height: 42)
                .offset(y: 104)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "FFF9D8"))
                .frame(width: 240, height: 150)
                .overlay(alignment: .bottom) {
                    WaveShape()
                        .fill(LinearGradient(colors: [Color(hex: "B77A42"), Color(hex: "F0B46A")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 58)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .stroke(Color(hex: "FFF9D8"), lineWidth: 28)
                .frame(width: 92, height: 92)
                .offset(x: -142, y: 22)
        }
    }

    var selectedPreset: DrinkPreset {
        DrinkPreset.all.first(where: { $0.id == selectedPresetID }) ?? .water
    }

    func configureInitialState() {
        let preset = initialPreset ?? .water
        selectedCategory = preset.category
        selectedPresetID = preset.id
    }
}

nonisolated private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.36))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.34),
            control1: CGPoint(x: rect.width * 0.18, y: rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.34, y: rect.height * 0.54)
        )
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.22),
            control1: CGPoint(x: rect.width * 0.66, y: rect.height * 0.14),
            control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.44)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct DrinkCustomAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let helperText: String?
    let unit: String
    let accent: Color
    let defaultAmount: Int
    let onComplete: (Int) -> Void
    @State private var amountText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(title)
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "20242A"))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 14, weight: .black))
                        .foregroundColor(Color(hex: "30343A"))
                        .frame(width: 34, height: 34)
                        .background(Theme.Colors.secondarySurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            TextField("\(defaultAmount)", text: $amountText)
                .keyboardType(.numberPad)
                .font(.appSystem(size: 28, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 18)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .trailing) {
                    Text(unit)
                        .font(.appSystem(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "4B4F55"))
                        .padding(.trailing, 22)
                }

            if let helperText {
                Text(helperText)
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "73787E"))
                    .lineSpacing(3)
            }

            Button {
                let amount = Int(amountText) ?? defaultAmount
                onComplete(max(0, amount))
                dismiss()
            } label: {
                Text("完 成")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(
                        Capsule()
                            .stroke(accent, lineWidth: 1.4)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 30)
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
        .onAppear {
            amountText = "\(defaultAmount)"
        }
    }
}

private struct DrinkWaterSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let targetMl: Int
    let accent: Color
    let onSave: (Int) -> Void
    @State private var draftTarget: Double = 2000

    var body: some View {
        VStack(spacing: 26) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 18, weight: .black))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 50, height: 50)
                        .background(Theme.Colors.secondarySurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")

                Spacer()
            }

            VStack(spacing: 16) {
                Text("每日饮水目标")
                    .font(.appSystem(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(Int(draftTarget.rounded()))")
                        .font(.appSystem(size: 58, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("ML")
                        .font(.appSystem(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "9A9FA4"))
                }

                Text("推荐：1500ml - 2500ml")
                    .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "8D9297"))
            }

            Slider(value: $draftTarget, in: 500...5000, step: 250)
                .tint(accent)

            Button {
                onSave(Int(draftTarget.rounded()))
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.appSystem(size: 22, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 112, height: 76)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("保存")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
        .onAppear {
            draftTarget = Double(targetMl)
        }
    }
}
