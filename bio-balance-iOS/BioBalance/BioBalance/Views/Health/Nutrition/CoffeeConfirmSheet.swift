/// 确认咖啡页，对照设计稿：咖啡类型选择、容量调整、咖啡因换算与健康 App 打卡。
/// 复用 DrinkPreset 的咖啡因换算与 HabitViewModel.recordDrink 的 HealthKit 写入路径。

import SwiftUI

struct CoffeeConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: HabitViewModel
    @State private var selectedKind: CoffeeKind = .americano
    @State private var volumeText = "350"
    @State private var isSaving = false
    @State private var saveErrorText: String?

    init(viewModel: HabitViewModel) {
        self.viewModel = viewModel
    }

    private let accent = Color(hex: "8F6645")

    /// 咖啡类型 × 咖啡因密度（mg/250ml）与每 100ml 热量（黑咖啡约 2 kcal，奶咖更高）。
    enum CoffeeKind: String, CaseIterable, Identifiable {
        case espresso
        case americano
        case coldBrew
        case latte
        case instant
        case decaf

        var id: String { rawValue }

        var title: String {
            switch self {
            case .espresso: return String(localized: "浓缩")
            case .americano: return String(localized: "美式")
            case .coldBrew: return String(localized: "冷萃")
            case .latte: return String(localized: "拿铁/卡布")
            case .instant: return String(localized: "速溶")
            case .decaf: return String(localized: "低因")
            }
        }

        var symbol: String {
            switch self {
            case .espresso: return "circle.grid.2x2.fill"
            case .americano: return "cup.and.saucer.fill"
            case .coldBrew: return "snowflake"
            case .latte: return "mug.fill"
            case .instant: return "leaf.arrow.circlepath"
            case .decaf: return "moon.zzz.fill"
            }
        }

        var caffeineMgPer250Ml: Int {
            switch self {
            case .espresso: return 212
            case .americano: return 120
            case .coldBrew: return 155
            case .latte: return 75
            case .instant: return 62
            case .decaf: return 5
            }
        }

        var kcalPer100Ml: Double {
            switch self {
            case .latte: return 5.5
            default: return 2.0
            }
        }
    }

    private var volumeMl: Int {
        max(0, Int(volumeText) ?? 0)
    }

    private var caffeineMg: Int {
        Int((Double(volumeMl) / 250.0 * Double(selectedKind.caffeineMgPer250Ml)).rounded())
    }

    private var kcal: Int {
        Int((Double(volumeMl) / 100.0 * selectedKind.kcalPer100Ml).rounded())
    }

    private var canSave: Bool {
        volumeMl > 0 && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    kindGrid

                    volumeSection

                    if let saveErrorText {
                        Label(saveErrorText, systemImage: "exclamationmark.circle.fill")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "984B36"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }

            Button {
                save()
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView().tint(Theme.Colors.onAccent)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.appSystem(size: 16, weight: .black))
                    }
                    Text(isSaving ? "正在保存" : "保存")
                        .font(.appSystem(size: 17, weight: .black, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
    }

    /// 与确认食物页一致的头部：关闭 × / 步骤 / 居中标题。
    private var sheetHeader: some View {
        ZStack {
            Text("确认咖啡")
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

                Text("5/6")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 子组件

    private var kindGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("咖啡类型")
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "3D4A43"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(CoffeeKind.allCases) { kind in
                    kindButton(kind)
                }
            }
        }
    }

    private func kindButton(_ kind: CoffeeKind) -> some View {
        let isSelected = selectedKind == kind
        return Button {
            selectedKind = kind
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.appSystem(size: 16, weight: .black))
                Text(kind.title)
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "6B5744"))
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                isSelected ? accent : Color.white,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color(hex: "E3D9CE"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("容量")
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3D4A43"))
                Spacer()
                Text("+\(caffeineMg)mg 咖啡因 · \(kcal) kcal")
                    .font(.appSystem(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(accent)
            }

            HStack(spacing: 10) {
                ForEach([180, 250, 355, 473], id: \.self) { amount in
                    volumeButton(amount)
                }
            }

            HStack(spacing: 8) {
                TextField("350", text: $volumeText)
                    .keyboardType(.numberPad)
                    .font(.appSystem(size: 22, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("毫升")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                Text("\(kcal) kcal")
                    .font(.appSystem(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("按 \(selectedKind.title) 的典型咖啡因密度估算：\(selectedKind.caffeineMgPer250Ml)mg / 250ml。")
                .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func volumeButton(_ amount: Int) -> some View {
        let isSelected = volumeMl == amount
        return Button {
            volumeText = String(amount)
        } label: {
            Text("\(amount)")
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: "6B5744"))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    isSelected ? accent : Color.white,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color(hex: "E3D9CE"), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 保存

    /// 复用 HabitViewModel.recordDrink：水份 + 咖啡因写入健康 App。
    private func save() {
        guard canSave else { return }
        isSaving = true
        saveErrorText = nil
        let preset = DrinkPreset(
            id: "coffee.\(selectedKind.rawValue)",
            category: .coffee,
            title: String(localized: "\(selectedKind.title)咖啡"),
            subtitle: "",
            amountMl: volumeMl,
            caffeineMgPer250Ml: selectedKind.caffeineMgPer250Ml,
            symbol: "cup.and.saucer.fill",
            tintHex: "8F6645"
        )
        viewModel.recordDrink(preset: preset, amountMl: volumeMl) { success in
            isSaving = false
            if success {
                dismiss()
            } else {
                saveErrorText = String(localized: "保存失败，请检查健康 App 权限后重试。")
            }
        }
    }
}
