import SwiftUI
import UIKit

private let mealFlowAccent = Color(hex: "19B79A")
private let mealFlowBackground = Color(hex: "F5F7F9")

struct MealRecognitionHomeContent: View {
    let records: [MealRecognitionRecord]
    let isRecognizing: Bool
    let recognitionError: String?
    let onRecognize: () -> Void
    let onManualEntry: () -> Void
    let onHistory: () -> Void
    let onDailyAnalysis: () -> Void
    let onOpenRecord: (MealRecognitionRecord) -> Void

    private var todayRecords: [MealRecognitionRecord] {
        records.filter { Calendar.current.isDateInToday($0.capturedAt) }
    }

    private var totalCalories: Int { todayRecords.reduce(0) { $0 + $1.estimatedCalories } }
    private var totalProtein: Int {
        Int(todayRecords.flatMap(\.recognizedFoods).compactMap(\.proteinGrams).reduce(0, +).rounded())
    }
    private let primarySlots: [MealSlot] = [.breakfast, .lunch, .dinner]
    private var recordedSlotCount: Int { Set(todayRecords.map(\.mealSlot)).intersection(primarySlots).count }
    private var totalCarbohydrates: Int { Int(todayRecords.flatMap(\.recognizedFoods).compactMap(\.carbohydrateGrams).reduce(0, +).rounded()) }
    private var totalFat: Int { Int(todayRecords.flatMap(\.recognizedFoods).compactMap(\.fatGrams).reduce(0, +).rounded()) }
    private var recentRecords: [MealRecognitionRecord] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return records.filter { $0.capturedAt >= start }
    }
    private var recentLoggedDays: Int { Set(recentRecords.map { Calendar.current.startOfDay(for: $0.capturedAt) }).count }
    private var recentDailyAverage: Int {
        guard recentLoggedDays > 0 else { return 0 }
        return recentRecords.reduce(0) { $0 + $1.estimatedCalories } / recentLoggedDays
    }
    private var foodVarietyCount: Int { Set(recentRecords.flatMap(\.recognizedFoods).map(\.name).filter { !$0.isEmpty }).count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                startCard
                overviewCard
                todayMealsCard
                weeklyReviewCard
                recognitionGuideCard
                suggestionCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(mealFlowBackground)
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今天吃得怎么样？").font(.title2.weight(.bold))
                    Text("拍下餐食，AI 识别后由你确认保存。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image("ActionHeaderMascot")
                    .resizable().scaledToFit()
                    .frame(width: 82, height: 82)
                    .accessibilityHidden(true)
            }

            // 主 CTA：拍照识别。识别中禁用防重复请求。
            Button(action: onRecognize) {
                Label(isRecognizing ? "正在识别餐食" : "拍照识别餐食", systemImage: "camera")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(mealFlowAccent)
            .disabled(isRecognizing)
            .accessibilityLabel(isRecognizing ? "正在识别餐食" : "拍摄餐食照片")

            HStack(spacing: 8) {
                Button(action: onRecognize) {
                    Label("从相册选择", systemImage: "photo")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color(hex: "30343B"))
                .disabled(isRecognizing)

                Button(action: onManualEntry) {
                    Label("手动录入", systemImage: "square.and.pencil")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color(hex: "30343B"))
            }

            HStack {
                Button(action: onHistory) {
                    Label("餐食历史", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(mealFlowAccent)
                Spacer()
                Button(action: onDailyAnalysis) {
                    Label("每日营养分析", systemImage: "chart.pie")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(mealFlowAccent)
            }
            .padding(.top, 2)

            if let recognitionError, !recognitionError.isEmpty {
                Label(recognitionError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(Color(hex: "984B36"))
            }
        }
        .padding(16).mealFlowCard(cornerRadius: 28)
    }

    private var overviewCard: some View {
        Button(action: onDailyAnalysis) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("今日概览").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                HStack {
                    metric("\(recordedSlotCount) / 3", "已记录餐次")
                    metric("\(totalCalories)", "千卡")
                    metric(totalProtein == 0 ? "—" : "\(totalProtein)g", "蛋白质")
                }
                ProgressView(value: Double(recordedSlotCount), total: 3)
                    .tint(mealFlowAccent)
                HStack(spacing: 14) {
                    nutrientLabel("碳水", value: totalCarbohydrates)
                    nutrientLabel("脂肪", value: totalFat)
                    Spacer()
                    Text(recordedSlotCount == 3 ? "今日三餐已补齐" : "还差 \(3 - recordedSlotCount) 餐")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(recordedSlotCount == 3 ? mealFlowAccent : .secondary)
                }
            }
            .padding(16).mealFlowCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看每日营养分析")
    }

    private var todayMealsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("今日餐次").font(.headline)
                Spacer()
                Button("查看全部", action: onHistory).font(.caption.weight(.bold)).foregroundStyle(mealFlowAccent)
            }.padding(.bottom, 10)
            ForEach(Array(primarySlots.enumerated()), id: \.element.id) { index, slot in
                if index > 0 { Divider().padding(.leading, 58) }
                let record = todaySlotRecord(slot)
                todayMealRow(slot: slot, record: record)
            }
        }
        .padding(16).mealFlowCard(cornerRadius: 26)
    }

    /// 同一餐次可能有多条记录（加餐常见），概览行展示最近一条。
    private func todaySlotRecord(_ slot: MealSlot) -> MealRecognitionRecord? {
        todayRecords.filter { $0.mealSlot == slot }.max { $0.capturedAt < $1.capturedAt }
    }

    private func todayMealRow(slot: MealSlot, record: MealRecognitionRecord?) -> some View {
        Button {
            if let record { onOpenRecord(record) } else { onRecognize() }
        } label: {
            HStack(spacing: 12) {
                mealThumbnail(record: record, slot: slot)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.title).font(.caption.weight(.bold)).foregroundStyle(.primary)
                    Text(record.map { $0.capturedAt.formatted(.dateTime.hour().minute()) } ?? slotTime(slot))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.map { "\($0.estimatedCalories) 千卡" } ?? String(localized: "尚未记录"))
                    .font(.caption2.weight(.bold)).foregroundStyle(record == nil ? .secondary : mealFlowAccent)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }.frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recordAccessibilityLabel(slot: slot, record: record))
    }

    /// 餐次缩略图：优先本机缩略图文件，无照片时回退餐次图标。
    @ViewBuilder
    private func mealThumbnail(record: MealRecognitionRecord?, slot: MealSlot) -> some View {
        if let record,
           let url = MealPhotoStore.shared.url(for: record.thumbnailLocalFilename ?? record.photoLocalFilename),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: slotIcon(slot))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(mealFlowAccent)
                .frame(width: 44, height: 44)
                .background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func recordAccessibilityLabel(slot: MealSlot, record: MealRecognitionRecord?) -> String {
        guard let record else {
            return String(localized: "\(slot.title)，尚未记录，点按开始记录")
        }
        let foods = record.recognizedFoods.map(\.name).prefix(3).joined(separator: "、")
        return String(localized: "\(slot.title)，\(record.capturedAt.formatted(.dateTime.hour().minute()))，估算 \(record.estimatedCalories) 千卡，\(foods)")
    }

    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日建议").font(.caption.weight(.bold)).foregroundStyle(Color(hex: "168B7B"))
            Text(todayRecords.isEmpty ? "先记录一餐，眠屿会逐步形成你的饮食节奏。" : "继续补全三餐，今天的营养分析会更准确。")
                .font(.caption.weight(.bold))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weeklyReviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("近 7 天记录").font(.headline)
                    Text(recentRecords.isEmpty ? "从今天开始积累你的饮食节奏" : "已记录 \(recentLoggedDays) 天，共 \(recentRecords.count) 餐")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(mealFlowAccent)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "EAF8F4"), in: Circle())
            }
            HStack(spacing: 10) {
                weeklyMetric(value: recentDailyAverage == 0 ? "—" : "\(recentDailyAverage)", title: "日均千卡")
                weeklyMetric(value: "\(recentRecords.count)", title: "记录餐数")
                weeklyMetric(value: "\(foodVarietyCount)", title: "食物种类")
            }
            Button(action: onHistory) {
                HStack { Text("查看饮食变化").font(.caption.weight(.bold)); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                    .foregroundStyle(mealFlowAccent)
            }.buttonStyle(.plain)
        }
        .padding(16).mealFlowCard(cornerRadius: 24)
    }

    private var recognitionGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拍照更容易识别").font(.headline)
            HStack(alignment: .top, spacing: 10) {
                guideItem("light.max", "光线充足", "避免强烈反光")
                guideItem("viewfinder", "完整入镜", "餐盘保持清晰")
                guideItem("square.stack.3d.up", "分开摆放", "减少食物遮挡")
            }
        }
        .padding(16).mealFlowCard(cornerRadius: 24)
    }

    private func nutrientLabel(_ title: LocalizedStringKey, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value == 0 ? "—" : "\(value)g").fontWeight(.bold)
        }.font(.caption2)
    }

    private func weeklyMetric(value: String, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.bold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func guideItem(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(mealFlowAccent)
            Text(title).font(.caption.weight(.bold))
            Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slotIcon(_ slot: MealSlot) -> String {
        switch slot { case .breakfast: "sunrise.fill"; case .lunch: "sun.max.fill"; case .dinner: "moon.stars.fill"; case .snack: "cup.and.saucer.fill" }
    }

    private func slotTime(_ slot: MealSlot) -> String {
        switch slot { case .breakfast: "07:00–09:30"; case .lunch: "11:30–14:00"; case .dinner: "17:30–20:30"; case .snack: "15:00–17:00" }
    }
}

/// 识别流程容器：根据 MealRecognitionState 切换「识别中 / 结果确认 / 失败」三个阶段。
/// 会话由 Hub 持有，容器只负责展示与回调，退出统一走 onClose（Hub 决定是否弹未保存确认）。
struct MealRecognitionFlowContainer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: MealRecognitionSession
    @State private var appearedInResult = false
    let initialSlot: MealSlot
    let onEdited: () -> Void
    let onSave: (PhotoRecognitionResult, MealSlot, [MealFoodItem]) -> Void
    let onClose: () -> Void

    init(
        session: MealRecognitionSession,
        initialSlot: MealSlot,
        onEdited: @escaping () -> Void,
        onSave: @escaping (PhotoRecognitionResult, MealSlot, [MealFoodItem]) -> Void,
        onClose: @escaping () -> Void
    ) {
        // @Observable 实例在 init 里包进 State，保证后续 mutation 触发视图刷新。
        _session = State(initialValue: session)
        self.initialSlot = initialSlot
        self.onEdited = onEdited
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Group {
                switch session.state {
                case .idle:
                    // 理论上不会停留：Hub 判断后才弹出容器。空转时给一个可退出占位。
                    Color.clear.onAppear { onClose() }
                case .preparing, .recognizing:
                    MealRecognitionProgressView(
                        photoImage: session.photoImage,
                        reduceMotion: reduceMotion,
                        onCancel: onClose
                    )
                case .success, .lowConfidence:
                    MealRecognitionResultView(
                        result: session.result,
                        photoImage: session.photoImage,
                        initialSlot: initialSlot,
                        isLowConfidence: {
                            if case .lowConfidence = session.state { return true }
                            return false
                        }(),
                        onEdited: onEdited,
                        onReplacePhoto: onClose,
                        onRetry: { session.retry() },
                        onSave: { slot, foods in
                            guard let result = session.result else { return }
                            onSave(result, slot, foods)
                        }
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                case .failure(let failure):
                    MealRecognitionFailureView(
                        failure: failure,
                        photoImage: session.photoImage,
                        onRetry: { session.retry() },
                        onChooseLibrary: onClose,
                        onManualEntry: onClose,
                        onClose: onClose
                    )
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: sessionStateKey)
        }
    }

    /// 用于 animation 触发的轻量状态键（Equatable 而不暴露结果内容比较开销）。
    private var sessionStateKey: String {
        switch session.state {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recognizing: "recognizing"
        case .success: "success"
        case .lowConfidence: "lowConfidence"
        case .failure(let failure): "failure-\(failure.diagnosticCode)"
        }
    }
}

/// 识别失败 / 无网络 / 低质量图片的可恢复失败页。
struct MealRecognitionFailureView: View {
    let failure: MealRecognitionFailure
    let photoImage: UIImage?
    let onRetry: () -> Void
    /// 相册重选与手动录入需要 Hub 先关闭识别容器，再打开对应入口。
    let onChooseLibrary: () -> Void
    let onManualEntry: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                if let photoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.badge.exclamationmark")
                        .resizable()
                        .scaledToFit()
                        .padding(56)
                        .foregroundStyle(mealFlowAccent.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .background(Theme.Colors.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 8) {
                Image(systemName: failureIcon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color(hex: "C97A4A"))
                Text(failure.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(hex: "1B2320"))
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onRetry()
                } label: {
                    Label("重新识别", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(mealFlowAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("使用同一张图片再试一次")

                HStack(spacing: 10) {
                    Button {
                        onChooseLibrary()
                    } label: {
                        Text("换一张照片")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color(hex: "30343B"))

                    Button {
                        onManualEntry()
                    } label: {
                        Text("手动录入")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color(hex: "30343B"))
                }
            }
            .padding(.bottom, 18)
        }
        .padding(16)
        .background(mealFlowBackground.ignoresSafeArea())
        .navigationTitle("识别失败")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { onClose() }
            }
        }
    }
    }

    private var failureIcon: String {
        switch failure {
        case .networkUnavailable: "wifi.slash"
        case .timeout: "clock.badge.exclamationmark"
        default: "exclamationmark.bubble"
        }
    }
}
struct MealRecognitionProgressView: View {
    @Environment(\.dismiss) private var dismiss
    let photoImage: UIImage?
    /// Reduce Motion 开启时不用持续扫描线，仅保留状态文字与轻透明度。
    var reduceMotion: Bool = false
    let onCancel: () -> Void

    @State private var scanOffset: CGFloat = -1

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    if let photoImage {
                        Image(uiImage: photoImage).resizable().scaledToFill()
                    } else {
                        Image(systemName: "fork.knife.circle.fill").resizable().scaledToFit().padding(70).foregroundStyle(mealFlowAccent)
                    }
                    if reduceMotion {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(mealFlowAccent.opacity(0.55), lineWidth: 2)
                            .padding(14)
                    } else {
                        scanCorners
                        scanLine
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 330).clipped()
                .background(Theme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                VStack(spacing: 8) {
                    ProgressView().tint(mealFlowAccent).controlSize(.large)
                    Text("正在识别餐食").font(.title3.weight(.bold))
                    Text("正在分析食物组成和大致份量")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    recognitionStep("识别食物", detail: "定位餐盘中的不同食物", state: .complete)
                    Divider().padding(.leading, 42)
                    recognitionStep("估算分量", detail: "结合餐具比例估算份量", state: .active)
                    Divider().padding(.leading, 42)
                    recognitionStep("计算营养", detail: "汇总热量和宏量营养", state: .pending)
                }
                .padding(.horizontal, 14).mealFlowCard(cornerRadius: 22)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Text("取消识别")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color(hex: "30343B"))
            }
            .padding(16).background(mealFlowBackground.ignoresSafeArea())
            .navigationTitle("正在识别").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { onCancel() } } }
            .onAppear {
                guard !reduceMotion else { return }
                scanOffset = -1
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    scanOffset = 1
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("meal-recognition-progress")
        }
    }

    private var scanCorners: some View {
        RoundedRectangle(cornerRadius: 18).stroke(mealFlowAccent, style: StrokeStyle(lineWidth: 2, dash: [28, 210])).padding(14)
    }

    private var scanLine: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [mealFlowAccent.opacity(0), mealFlowAccent.opacity(0.34), mealFlowAccent.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 64)
            .offset(y: scanOffset < 0 ? -64 : proxy.size.height)
            .onAppear {
                // withAnimation 已由外层触发；这里只负责把初值放到顶端之外。
                scanOffset = -1
            }
        }
        .padding(14)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private enum RecognitionStepState: Equatable { case complete, active, pending }

    private func recognitionStep(_ title: LocalizedStringKey, detail: LocalizedStringKey, state: RecognitionStepState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state == .complete ? "checkmark.circle.fill" : state == .active ? "circle.dotted" : "circle")
                .foregroundStyle(state == .pending ? Color.secondary : mealFlowAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.bold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(state == .complete ? "已完成" : state == .active ? "进行中" : "等待")
                .font(.caption2.weight(.bold))
                .foregroundStyle(state == .pending ? Color.secondary : mealFlowAccent)
        }.frame(minHeight: 54)
    }
}

struct MealManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let recentFoods: [MealFoodItem]
    let onSave: (MealSlot, [MealFoodItem]) -> Void
    @State private var query = ""
    @State private var customName = ""
    @State private var selectedSlot: MealSlot
    @State private var selectedFoods: [MealFoodItem] = []
    @State private var manualCalories = 0
    /// AI 食物搜索状态与防抖任务。
    @State private var searchState: MealFoodSearchState = .idle
    @State private var searchTask: Task<Void, Never>?
    @State private var searchService = MealFoodSearchService()
    private let commonFoods: [MealFoodItem] = [
        MealFoodItem(id: "common-milk", name: "牛奶", calories: 65, proteinGrams: 3.4, carbohydrateGrams: 5, fatGrams: 3.6, servingAmount: 100, servingUnit: "ml", nutritionSource: .foodDatabase),
        MealFoodItem(id: "common-egg", name: "鸡蛋", calories: 78, proteinGrams: 6.3, carbohydrateGrams: 0.6, fatGrams: 5.3, servingAmount: 1, servingUnit: "个", nutritionSource: .foodDatabase),
        MealFoodItem(id: "common-rice", name: "米饭", calories: 116, proteinGrams: 2.6, carbohydrateGrams: 25.6, fatGrams: 0.3, servingAmount: 100, servingUnit: "g", nutritionSource: .foodDatabase),
        MealFoodItem(id: "common-apple", name: "苹果", calories: 52, carbohydrateGrams: 14, fiberGrams: 2.4, servingAmount: 100, servingUnit: "g", nutritionSource: .foodDatabase),
        MealFoodItem(id: "common-broccoli", name: "西兰花", calories: 35, proteinGrams: 2.4, carbohydrateGrams: 7.2, fiberGrams: 3.3, servingAmount: 100, servingUnit: "g", nutritionSource: .foodDatabase),
        MealFoodItem(id: "common-oats", name: "燕麦", calories: 389, proteinGrams: 16.9, carbohydrateGrams: 66.3, fatGrams: 6.9, fiberGrams: 10.6, servingAmount: 100, servingUnit: "g", nutritionSource: .foodDatabase)
    ]

    init(recentFoods: [MealFoodItem], initialSlot: MealSlot, onSave: @escaping (MealSlot, [MealFoodItem]) -> Void) {
        self.recentFoods = recentFoods
        self.onSave = onSave
        _selectedSlot = State(initialValue: initialSlot)
    }

    private var filteredRecent: [MealFoodItem] {
        query.isEmpty ? recentFoods : recentFoods.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("搜索食物").font(.headline)
                        TextField("搜索食物名称，例如 鸡胸肉", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .accessibilityLabel("搜索食物名称")
                        searchStateSection
                    }
                    .padding(16).mealFlowCard(cornerRadius: 20)

                    if !recentFoods.isEmpty {
                        Text("最近使用").font(.headline)
                        ForEach(filteredRecent) { food in foodRow(food) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("常见食物").font(.headline)
                            Spacer()
                            Text("按常见份量估算").font(.caption2).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(commonFoods) { food in commonFoodTile(food) }
                        }
                    }

                    if !selectedFoods.isEmpty { selectedFoodsCard }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("自定义食物").font(.headline)
                        TextField("输入食物名称", text: $customName)
                            .textFieldStyle(.roundedBorder)
                        Stepper("估算热量  \(manualCalories) 千卡", value: $manualCalories, in: 0...5_000, step: 10)
                        Button("添加自定义食物") {
                            let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            selectedFoods.append(MealFoodItem(id: UUID().uuidString, name: name, calories: manualCalories, nutritionSource: .userEntered, wasEditedByUser: true))
                            customName = ""
                            manualCalories = 0
                        }
                        .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(16).mealFlowCard(cornerRadius: 20)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("记录为").font(.caption.weight(.bold))
                        Picker("记录为", selection: $selectedSlot) {
                            ForEach(MealSlot.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    }.padding(16).mealFlowCard(cornerRadius: 20)
                }.padding(16).padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) {
                Button { onSave(selectedSlot, selectedFoods) } label: {
                    Text("添加到\(selectedSlot.title)").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48).background(mealFlowAccent, in: Capsule())
                }.buttonStyle(.plain).disabled(selectedFoods.isEmpty).opacity(selectedFoods.isEmpty ? 0.45 : 1)
                    .padding().background(.ultraThinMaterial)
            }
            .background(mealFlowBackground).navigationTitle("手动录入")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private var searchStateSection: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在查询营养估算…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        case .results(let items):
            VStack(spacing: 0) {
                ForEach(items) { food in
                    foodRow(food)
                    if food.id != items.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            Text("营养数值为 AI 估算，保存前可继续修改。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        case .empty:
            Text("没有找到该食物，可以在下方手动添加自定义食物。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        case .failure:
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Text("查询失败，可以直接手动录入名称和热量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("重试") { scheduleSearch(query, force: true) }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mealFlowAccent)
            }
            .padding(.vertical, 6)
        }
    }

    /// 300ms 防抖：避免逐字符触发网络请求；force 用于失败后的手动重试。
    private func scheduleSearch(_ text: String, force: Bool = false) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchState = .idle
            return
        }
        guard force || trimmed.count >= 2 else { return }
        searchState = .searching
        searchTask = Task {
            // 防抖窗口：等待期间新输入会 cancel 当前任务。
            try? await Task.sleep(for: .milliseconds(force ? 0 : 300))
            guard !Task.isCancelled else { return }
            do {
                let items = try await searchService.search(query: trimmed)
                guard !Task.isCancelled else { return }
                searchState = items.isEmpty ? .empty : .results(items)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // 失败不阻塞手动录入主流程，给出可重试提示。
                searchState = .failure(error.localizedDescription)
            }
        }
    }

    private func foodRow(_ food: MealFoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name).font(.caption.weight(.bold))
                HStack(spacing: 6) {
                    Text("约 \(food.calories) 千卡").font(.caption2).foregroundStyle(.secondary)
                    if food.normalizedSource == .aiEstimate {
                        Text("估算")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(hex: "168B7B"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "EAF8F4"), in: Capsule())
                    }
                }
            }
            Spacer(); addButton(food)
        }.padding(.horizontal, 14).frame(minHeight: 54).mealFlowCard(cornerRadius: 18)
    }

    private func commonFoodTile(_ food: MealFoodItem) -> some View {
        Button { appendFood(food) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.name).font(.caption.weight(.bold)).foregroundStyle(.primary)
                    Text("\(food.calories) 千卡 · \(servingSummary(food))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "plus.circle.fill").foregroundStyle(mealFlowAccent)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .mealFlowCard(cornerRadius: 18)
        }.buttonStyle(.plain)
    }

    private var selectedFoodsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本餐已选").font(.headline)
                Spacer()
                Text("\(selectedFoods.count) 项 · \(selectedFoods.reduce(0) { $0 + $1.calories }) 千卡")
                    .font(.caption.weight(.bold)).foregroundStyle(mealFlowAccent)
            }
            ForEach(selectedFoods) { food in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(mealFlowAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).font(.caption.weight(.bold))
                        Text("\(food.calories) 千卡").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selectedFoods.removeAll { $0.id == food.id } } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("移除\(food.name)")
                }
            }
        }.padding(16).background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func servingSummary(_ food: MealFoodItem) -> String {
        guard let amount = food.servingAmount else { return String(localized: "常见份量") }
        return "\(Int(amount.rounded()))\(food.servingUnit ?? "g")"
    }

    private func appendFood(_ food: MealFoodItem) {
        selectedFoods.append(MealFoodItem(id: UUID().uuidString, name: food.name, calories: food.calories, proteinGrams: food.proteinGrams, carbohydrateGrams: food.carbohydrateGrams, fatGrams: food.fatGrams, fiberGrams: food.fiberGrams, servingAmount: food.servingAmount, servingUnit: food.servingUnit, nutritionSource: food.nutritionSource, wasEditedByUser: true))
    }

    private func addButton(_ food: MealFoodItem) -> some View {
        Button { appendFood(food) } label: {
            Image(systemName: "plus.circle.fill").foregroundStyle(mealFlowAccent)
        }.buttonStyle(.plain).accessibilityLabel("添加\(food.name)")
    }
}

struct MealHistoryView: View {
    let records: [MealRecognitionRecord]
    @State private var currentRecords: [MealRecognitionRecord]
    @State private var range = 1
    @State private var slotFilter: MealSlot?

    init(records: [MealRecognitionRecord]) {
        self.records = records
        _currentRecords = State(initialValue: records)
    }

    private var grouped: [(Date, [MealRecognitionRecord])] {
        Dictionary(grouping: filteredRecords) { Calendar.current.startOfDay(for: $0.capturedAt) }
            .sorted { $0.key > $1.key }.map { ($0.key, $0.value.sorted { $0.capturedAt > $1.capturedAt }) }
    }

    private var filteredRecords: [MealRecognitionRecord] {
        let calendar = Calendar.current
        let now = Date()
        let start: Date = switch range {
        case 0: calendar.startOfDay(for: now)
        case 2: calendar.dateInterval(of: .month, for: now)?.start ?? .distantPast
        default: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? .distantPast
        }
        return currentRecords.filter { $0.capturedAt >= start && (slotFilter == nil || $0.mealSlot == slotFilter) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("时间范围", selection: $range) { Text("今日").tag(0); Text("7天").tag(1); Text("本月").tag(2) }.pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { filterButton("全部", slot: nil); ForEach(MealSlot.allCases) { filterButton($0.title, slot: $0) } }
                }
                summary
                if grouped.isEmpty {
                    VStack(spacing: 12) {
                        Image("ActionHeaderMascot").resizable().scaledToFit().frame(width: 118, height: 98).accessibilityHidden(true)
                        Text("这段时间还没有餐食记录").font(.headline)
                        Text("拍照识别或手动录入一餐后，会在这里看到每天的饮食变化。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 20).mealFlowCard(cornerRadius: 24)
                }
                ForEach(grouped, id: \.0) { date, meals in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(date.formatted(.dateTime.month().day().weekday(.wide))).font(.headline); Spacer(); Text("\(meals.reduce(0) { $0 + $1.estimatedCalories }) 千卡").font(.caption).foregroundStyle(.secondary) }
                        VStack(spacing: 0) { ForEach(meals) { record in NavigationLink { MealRecordDetailView(record: record) { currentRecords = DrinkExperienceStore.shared.allMealRecords() } } label: { historyRow(record) }; if record.id != meals.last?.id { Divider().padding(.leading, 44) } } }
                            .padding(.horizontal, 14).mealFlowCard(cornerRadius: 22)
                    }
                }
            }.padding(16)
        }.background(mealFlowBackground).navigationTitle("餐食记录")
            .toolbar(.hidden, for: .tabBar)
            .onAppear { currentRecords = DrinkExperienceStore.shared.allMealRecords() }
    }

    private var summary: some View {
        HStack { VStack(alignment: .leading) { Text(range == 0 ? "今日" : range == 2 ? "本月" : "过去 7 天").font(.caption.weight(.bold)).foregroundStyle(mealFlowAccent); Text("\(filteredRecords.count)").font(.title.weight(.bold)); Text("餐已记录").font(.caption2).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing, spacing: 3) { Text(historyAverageText).font(.caption.weight(.bold)); Text("记录越完整，趋势会越准确").font(.caption2).foregroundStyle(.secondary) } }
            .padding(16).background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 24))
    }

    private var historyAverageText: String {
        let days = Set(filteredRecords.map { Calendar.current.startOfDay(for: $0.capturedAt) }).count
        guard days > 0 else { return String(localized: "等待第一餐") }
        let average = filteredRecords.reduce(0) { $0 + $1.estimatedCalories } / days
        return String(localized: "日均 \(average) 千卡")
    }

    private func filterButton(_ title: String, slot: MealSlot?) -> some View {
        Button(title) { slotFilter = slot }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(slotFilter == slot ? mealFlowAccent : Color(hex: "788291"))
    }

    private func historyRow(_ record: MealRecognitionRecord) -> some View {
        HStack(spacing: 10) {
            historyThumbnail(record)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.mealSlot.title)  \(record.capturedAt.formatted(.dateTime.hour().minute()))").font(.caption.weight(.bold)).foregroundStyle(.primary)
                Text(historyFoodSummary(record)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("\(record.estimatedCalories) 千卡").font(.caption2.weight(.bold)).foregroundStyle(.primary)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(historyAccessibilityLabel(record))
    }

    /// 历史列表缩略图：使用本机 320px 缩略图文件，避免整页解码原图。
    @ViewBuilder
    private func historyThumbnail(_ record: MealRecognitionRecord) -> some View {
        if let url = MealPhotoStore.shared.url(for: record.thumbnailLocalFilename ?? record.photoLocalFilename),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Text(String(record.mealSlot.title.prefix(1)))
                .font(.caption.weight(.bold))
                .foregroundStyle(mealFlowAccent)
                .frame(width: 32, height: 32)
                .background(Color(hex: "EAF8F4"), in: Circle())
                .accessibilityHidden(true)
        }
    }

    private func historyFoodSummary(_ record: MealRecognitionRecord) -> String {
        let names = record.recognizedFoods.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "未填写食物明细" : names.prefix(3).joined(separator: " · ")
    }

    private func historyAccessibilityLabel(_ record: MealRecognitionRecord) -> String {
        String(localized: "\(record.mealSlot.title)，\(record.capturedAt.formatted(.dateTime.hour().minute()))，估算 \(record.estimatedCalories) 千卡，查看详情")
    }
}

struct MealDailyNutritionView: View {
    @Environment(\.dismiss) private var dismiss
    let records: [MealRecognitionRecord]
    /// AI 总结的确定性问题拌（失败时仍展示基础统计）。
    @State private var aiSummaryText: String?
    @State private var isSummaryLoading = false
    private var total: Int { records.reduce(0) { $0 + $1.estimatedCalories } }
    private var summary: MealNutritionSummary { .calculate(from: records.flatMap(\.recognizedFoods)) }

    var body: some View {
        ScrollView { VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("今日总摄入").font(.headline)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(total)").font(.largeTitle.weight(.bold))
                    Text("千卡（估算）").foregroundStyle(.secondary)
                    Spacer()
                    // 项目未设置营养目标时不得编造目标值，仅提示可设置。
                    Text("尚未设置营养目标").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).mealFlowCard()
            VStack(alignment: .leading, spacing: 14) {
                Text("宏量营养").font(.headline)
                HStack {
                    macro("蛋白质", summary.proteinGrams)
                    macro("碳水", summary.carbohydrateGrams)
                    macro("脂肪", summary.fatGrams)
                    macro("纤维", summary.fiberGrams)
                }
            }.padding(16).mealFlowCard()
            VStack(alignment: .leading, spacing: 14) {
                Text("三餐分布").font(.headline)
                ForEach(MealSlot.allCases) { slot in let value = records.filter { $0.mealSlot == slot }.reduce(0) { $0 + $1.estimatedCalories }; HStack { Text(slot.title).font(.caption.weight(.bold)).frame(width: 44, alignment: .leading); ProgressView(value: total == 0 ? 0 : Double(value) / Double(total)).tint(mealFlowAccent); Text(distributionText(value: value, total: total)).font(.caption2).foregroundStyle(.secondary).frame(width: 84, alignment: .trailing) } }
            }.padding(16).mealFlowCard()
            nutritionHighlightsCard
            aiSummaryCard
            HStack(spacing: 12) {
                NavigationLink { MealHistoryView(records: DrinkExperienceStore.shared.allMealRecords()) } label: { Text("查看餐食记录").frame(maxWidth: .infinity).frame(height: 42) }.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color(hex: "30343B"))
                Button { dismiss() } label: { Text("继续记录").foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 42).background(mealFlowAccent, in: Capsule()) }.buttonStyle(.plain)
            }
            Text("营养数据来自拍照识别与手动记录的估算结果，仅作健康管理参考，不构成医疗建议。")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(12).mealFlowCard(cornerRadius: 20)
        }.padding(16) }.background(mealFlowBackground).navigationTitle("每日营养分析")
            .toolbar(.hidden, for: .tabBar)
            .task { await loadSummary() }
    }

    /// 三餐分布百分比 + 千卡；总摄入为 0 时不显示百分比。
    private func distributionText(value: Int, total: Int) -> String {
        guard total > 0 else { return "0 千卡" }
        let percent = Int((Double(value) / Double(total) * 100).rounded())
        return String(localized: "\(percent)% · \(value) 千卡")
    }

    private var nutritionHighlightsCard: some View {
        let mealCount = records.count
        let foodCount = records.flatMap(\.recognizedFoods).count
        let namedVariety = Set(records.flatMap(\.recognizedFoods).map(\.name).filter { !$0.isEmpty }).count
        let completeMacros = records.flatMap(\.recognizedFoods).filter {
            $0.proteinGrams != nil && $0.carbohydrateGrams != nil && $0.fatGrams != nil
        }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("记录完整度").font(.headline)
            HStack(spacing: 10) {
                highlightMetric("\(mealCount)", "餐次", "fork.knife")
                highlightMetric("\(namedVariety)", "食物种类", "leaf.fill")
                highlightMetric(foodCount == 0 ? "—" : "\(completeMacros)/\(foodCount)", "营养完整", "checkmark.seal.fill")
            }
            Text(foodCount == 0 ? "记录第一餐后，可以看到食物多样性和营养字段完整度。" : completeMacros == foodCount ? "今天记录的食物均包含完整宏量营养信息。" : "还有 \(foodCount - completeMacros) 项食物缺少完整营养信息，可进入单餐详情补充。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).mealFlowCard()
    }

    private func highlightMetric(_ value: String, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.caption).foregroundStyle(mealFlowAccent)
            Text(value).font(.title3.weight(.bold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    /// 基于结构化营养数据的确定性总结；不请求网络，保证页面始终有内容。
    private var deterministicSummary: String? {
        guard !records.isEmpty else { return nil }
        var parts: [String] = []
        if summary.proteinGrams >= 50 {
            parts.append(String(localized: "今天蛋白质摄入相对充足。"))
        } else if total > 0 {
            parts.append(String(localized: "今天蛋白质摄入还有补充空间。"))
        }
        if let dinnerShare = slotShare(.dinner), dinnerShare > 0.45 {
            parts.append(String(localized: "晚餐在今天总摄入中的占比较高。"))
        }
        if summary.fiberGrams < 15 {
            parts.append(String(localized: "今天记录的蔬菜和全谷类偏少，可以留意膳食纤维。"))
        }
        return parts.isEmpty ? String(localized: "今天的记录结构比较均衡，继续保持规律记录即可。") : parts.joined(separator: " ")
    }

    private func slotShare(_ slot: MealSlot) -> Double? {
        guard total > 0 else { return nil }
        let value = records.filter { $0.mealSlot == slot }.reduce(0) { $0 + $1.estimatedCalories }
        return Double(value) / Double(total)
    }

    private var aiSummaryCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("今日营养总结").font(.headline).foregroundStyle(Color(hex: "168B7B"))
                if records.isEmpty {
                    Text("还没有今日记录，先完成一餐记录后这里会给出结构总结。")
                        .font(.caption.weight(.bold))
                } else if let aiSummaryText {
                    Text(aiSummaryText).font(.caption.weight(.bold))
                } else if isSummaryLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在生成总结…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let deterministicSummary {
                    // AI 总结失败时的兜底：显示本地确定性统计结论。
                    Text(deterministicSummary).font(.caption.weight(.bold))
                }
            }
            Spacer(minLength: 0)
            Image("VitalityHeaderMascot")
                .resizable().scaledToFit().frame(width: 86, height: 86).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "EAF8F4"), in: RoundedRectangle(cornerRadius: 24))
    }

    /// 今日总结：基于结构化营养上下文的确定性结论。
    /// 项目尚未接入独立的饮食分析 LLM 通道，这里不发起网络请求；
    /// 结论只描述记录结构（蛋白质水平、晚餐占比、纤维），不构成医学建议。
    private func loadSummary() async {
        guard !records.isEmpty else { return }
        isSummaryLoading = true
        // 轻微延迟避免进度闪烁；结论本身是本地计算。
        try? await Task.sleep(for: .milliseconds(200))
        aiSummaryText = deterministicSummary
        isSummaryLoading = false
    }

    private func macro(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))g").font(.headline)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 每日营养 AI 总结的结构化上下文（当前用确定性规则生成结论，字段保留供后续接入）。
nonisolated struct MealDailyAnalysisContext {
    let date: Date
    let mealCount: Int
    let totalCalories: Int
    let proteinGrams: Double
    let carbohydrateGrams: Double
    let fatGrams: Double
    let fiberGrams: Double
    let slotDistribution: [MealSlot: Int]

    init(records: [MealRecognitionRecord], date: Date = Date()) {
        self.date = date
        let foods = records.flatMap(\.recognizedFoods)
        let summary = MealNutritionSummary.calculate(from: foods)
        mealCount = records.count
        totalCalories = summary.calories
        proteinGrams = summary.proteinGrams
        carbohydrateGrams = summary.carbohydrateGrams
        fatGrams = summary.fatGrams
        fiberGrams = summary.fiberGrams
        var distribution: [MealSlot: Int] = [:]
        for record in records {
            distribution[record.mealSlot, default: 0] += record.estimatedCalories
        }
        slotDistribution = distribution
    }
}

private extension View {
    func mealFlowCard(cornerRadius: CGFloat = 24) -> some View {
        background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color(hex: "E3EAE7"), lineWidth: 1) }
    }
}
