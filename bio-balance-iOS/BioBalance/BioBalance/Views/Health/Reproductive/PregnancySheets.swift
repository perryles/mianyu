/// PregnancySheets 由生理健康模块调用，作为「孕期设置」面板。
/// 负责管理预产期、末次月经日期，支持结束或删除孕期记录。

import SwiftUI

struct PregnancySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PregnancyViewModel
    @State private var dueDate: Date
    @State private var lastMenstrualPeriod: Date
    @State private var localError: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsEndConfirmation = false

    private let rose = Color(hex: "F35F9B")
    private let mint = Color(hex: "42BE9B")

    init(profile: PregnancyProfile?, viewModel: PregnancyViewModel) {
        self.viewModel = viewModel
        let today = Calendar.current.startOfDay(for: Date())
        let earliest = Calendar.current.date(byAdding: .weekOfYear, value: -44, to: today) ?? today
        let proposedLMP = profile?.lastMenstrualPeriod ?? Calendar.current.date(
            byAdding: .weekOfYear,
            value: -8,
            to: Date()
        ) ?? Date()
        let initialLMP = min(max(Calendar.current.startOfDay(for: proposedLMP), earliest), today)
        _lastMenstrualPeriod = State(initialValue: initialLMP)
        let dueLowerBound = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: today) ?? today
        let dueUpperBound = Calendar.current.date(byAdding: .weekOfYear, value: 44, to: today) ?? today
        let proposedDueDate = Calendar.current.startOfDay(
            for: profile?.dueDate ?? PregnancyDateCalculator.expectedDueDate(from: initialLMP)
        )
        _dueDate = State(initialValue: min(max(proposedDueDate, dueLowerBound), dueUpperBound))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                sheetBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.hasActivePregnancy ? "孕期日期" : "开始孕期记录")
                                .font(.appSystem(size: 24, weight: .black, design: .rounded))
                            Text("末次月经日期用于计算孕周；预产期可按医生校正后的日期独立设置。")
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "747983"))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        datePickerCard(
                            title: "预产期",
                            icon: "calendar.badge.clock",
                            selection: dueDateBinding,
                            range: dueDateRange
                        )

                        datePickerCard(
                            title: "最后一次月经日期",
                            icon: "calendar",
                            selection: lastMenstrualPeriodBinding,
                            range: lastMenstrualPeriodRange
                        )

                        Button {
                            dueDate = PregnancyDateCalculator.expectedDueDate(from: lastMenstrualPeriod)
                        } label: {
                            Label("按末次月经日期推算预产期", systemImage: "calendar.badge.clock")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(rose)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Theme.Colors.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if let localError {
                            errorLabel(localError)
                        }

                        Button {
                            save()
                        } label: {
                            HStack(spacing: 9) {
                                if viewModel.syncStatus.isBusy {
                                    ProgressView().tint(Theme.Colors.onAccent)
                                } else {
                                    Image(systemName: "checkmark.icloud.fill")
                                }
                                Text(viewModel.hasActivePregnancy ? "保存到 iCloud" : "开始孕期记录")
                            }
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(mint, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canMutate)

                        Label("仅保存到当前 Apple ID 的 CloudKit 私有数据库。", systemImage: "lock.icloud.fill")
                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "727984"))
                            .frame(maxWidth: .infinity, alignment: .center)

                        if viewModel.hasActivePregnancy {
                            Button {
                                showsEndConfirmation = true
                            } label: {
                                Label("结束当前孕期", systemImage: "checkmark.circle")
                                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "C63F78"))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Theme.Colors.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.canMutate)
                        }

                        if hasPregnancyData {
                            Button(role: .destructive) {
                                showsDeleteConfirmation = true
                            } label: {
                                Label("永久清除全部孕期数据", systemImage: "trash")
                                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Theme.Colors.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.canMutate)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(viewModel.hasActivePregnancy ? "孕期设置" : "开始孕期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 14, weight: .black))
                            .frame(width: 44, height: 44)
                            .background(Theme.Colors.surface, in: Circle())
                    }
                    .foregroundColor(Color(hex: "4A4D54"))
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .confirmationDialog(
            "结束当前孕期？",
            isPresented: $showsEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("结束孕期") {
                endPregnancy()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("结束后周期健康会恢复经期记录模式；现有孕期数据仍保留在当前 Apple ID 的 CloudKit 私有数据库中。")
        }
        .confirmationDialog(
            "永久清除全部孕期数据？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("从 iCloud 清除", role: .destructive) {
                deleteAllData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("预产期、末次月经日期、体重和胎动记录都会从当前 Apple ID 的 CloudKit 私有数据库永久删除，此操作无法撤销。")
        }
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { dueDate },
            set: { newDate in
                dueDate = Calendar.current.startOfDay(for: newDate)
            }
        )
    }

    private var lastMenstrualPeriodRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let earliest = Calendar.current.date(byAdding: .weekOfYear, value: -44, to: today) ?? today
        return earliest...today
    }

    private var dueDateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let lower = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: today) ?? today
        let upper = Calendar.current.date(byAdding: .weekOfYear, value: 44, to: today) ?? today
        return lower...upper
    }

    private var lastMenstrualPeriodBinding: Binding<Date> {
        Binding(
            get: { lastMenstrualPeriod },
            set: { newDate in
                lastMenstrualPeriod = Calendar.current.startOfDay(for: newDate)
            }
        )
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: [Color(hex: "FDE9F5"), Color(hex: "F8F8FA"), Color(hex: "EFF8F5")],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var hasPregnancyData: Bool {
        viewModel.profile != nil || !viewModel.weights.isEmpty || !viewModel.fetalMovements.isEmpty
    }

    private func datePickerCard(
        title: String,
        icon: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "454950"))

            DatePicker(
                title,
                selection: selection,
                in: range,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, Locale.autoupdatingCurrent)
            .tint(rose)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func save() {
        localError = nil
        Task {
            let saved = await viewModel.saveProfile(
                lastMenstrualPeriod: lastMenstrualPeriod,
                dueDate: dueDate
            )
            if saved {
                dismiss()
            } else if case .failed(let message) = viewModel.syncStatus {
                localError = message
            }
        }
    }

    private func deleteAllData() {
        localError = nil
        Task {
            let deleted = await viewModel.deleteAllPregnancyData()
            if deleted {
                dismiss()
            } else if case .failed(let message) = viewModel.syncStatus {
                localError = message
            }
        }
    }

    private func endPregnancy() {
        localError = nil
        Task {
            let ended = await viewModel.endPregnancy()
            if ended {
                dismiss()
            } else if case .failed(let message) = viewModel.syncStatus {
                localError = message
            }
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.icloud.fill")
            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(Color(hex: "B83D65"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "FCE9F0"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PregnancyWeightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PregnancyViewModel
    @State private var weightText = ""
    @State private var measuredAt = Date()
    @State private var localError: String?
    @FocusState private var weightFieldFocused: Bool

    private let rose = Color(hex: "F35F9B")
    private let mint = Color(hex: "42BE9B")

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.pageBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("体重")
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "4D5158"))

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                TextField("例如 65.0", text: $weightText)
                                    .keyboardType(.decimalPad)
                                    .font(.appSystem(size: 31, weight: .black, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .focused($weightFieldFocused)
                                Text("kg")
                                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                                    .foregroundColor(Color(hex: "717680"))
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 76)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("测量时间")
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "4D5158"))
                            DatePicker(
                                "测量时间",
                                selection: $measuredAt,
                                in: Date.distantPast...Date(),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .environment(\.locale, Locale.autoupdatingCurrent)
                            .tint(rose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                        if let localError {
                            inlineError(localError)
                        }

                        Button {
                            save()
                        } label: {
                            HStack(spacing: 9) {
                                if viewModel.syncStatus.isBusy {
                                    ProgressView().tint(Theme.Colors.onAccent)
                                } else {
                                    Image(systemName: "checkmark.icloud.fill")
                                }
                                Text("保存体重")
                            }
                            .font(.appSystem(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(canSave ? mint : Color(hex: "C9CDCF"), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave || !viewModel.canMutate)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("记录体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 14, weight: .black))
                    }
                    .accessibilityLabel("关闭")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { weightFieldFocused = false }
                        .font(.appSystem(size: 14, weight: .bold))
                }
            }
        }
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
        .onAppear { weightFieldFocused = true }
    }

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard let weight = parsedWeight else { return false }
        return (25...300).contains(weight)
    }

    private func save() {
        guard let weight = parsedWeight else { return }
        localError = nil
        weightFieldFocused = false
        Task {
            let saved = await viewModel.addWeight(weightKg: weight, measuredAt: measuredAt)
            if saved {
                dismiss()
            } else if case .failed(let message) = viewModel.syncStatus {
                localError = message
            }
        }
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(Color(hex: "B83D65"))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FetalMovementEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PregnancyViewModel
    @State private var occurredAt = Date()
    @State private var localError: String?
    @State private var showsCustomTime = false

    let earliestDate: Date?
    private let rose = Color(hex: "F35F9B")
    private let mint = Color(hex: "42BE9B")

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "FDE7F4"), Color(hex: "F8F8FA")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        Image(systemName: "figure.and.child.holdinghands")
                            .font(.appSystem(size: 44, weight: .semibold))
                            .foregroundColor(rose.opacity(0.72))
                            .frame(width: 88, height: 88)
                            .background(Theme.Colors.surface.opacity(0.75), in: Circle())

                        VStack(spacing: 7) {
                            Text("刚刚感受到胎动？")
                                .font(.appSystem(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "35383F"))
                            Text("点一下即可记录当前时间，不用填写其他内容。")
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            save(at: Date())
                        } label: {
                            HStack(spacing: 10) {
                                if viewModel.syncStatus.isBusy {
                                    ProgressView().tint(Theme.Colors.onAccent)
                                } else {
                                    Image(systemName: "hand.tap.fill")
                                }
                                Text("记录现在")
                            }
                            .font(.appSystem(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(rose, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canMutate)

                        Button {
                            showsCustomTime.toggle()
                        } label: {
                            Label(showsCustomTime ? "收起补记" : "补记其他时间", systemImage: "calendar.badge.plus")
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "A33767"))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Theme.Colors.surface.opacity(0.92), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if showsCustomTime {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("胎动时间")
                                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                                DatePicker(
                                    "胎动时间",
                                    selection: $occurredAt,
                                    in: fetalMovementDateRange,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .labelsHidden()
                                .datePickerStyle(.wheel)
                                .environment(\.locale, Locale.autoupdatingCurrent)
                                .tint(rose)
                                .frame(maxWidth: .infinity)
                                .clipped()

                                Button {
                                    save(at: occurredAt)
                                } label: {
                                    Label("保存补记", systemImage: "checkmark.icloud.fill")
                                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                        .background(mint, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canMutate)
                            }
                            .padding(17)
                            .background(Theme.Colors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        if let localError {
                            Label(localError, systemImage: "exclamationmark.triangle.fill")
                                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "B83D65"))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                    }
                    .padding(20)
                }
            }
            .navigationTitle("记录胎动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.appSystem(size: 14, weight: .black))
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func save(at date: Date) {
        localError = nil
        Task {
            let saved = await viewModel.addFetalMovement(occurredAt: date)
            if saved {
                dismiss()
            } else if case .failed(let message) = viewModel.syncStatus {
                localError = message
            }
        }
    }

    private var fetalMovementDateRange: ClosedRange<Date> {
        let now = Date()
        let fallback = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        return min(earliestDate ?? fallback, now)...now
    }
}

struct FetalMovementHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PregnancyViewModel
    @State private var pendingDeletion: FetalMovementEntry?
    @State private var showsDeleteConfirmation = false
    @State private var operationError: String?

    private let rose = Color(hex: "F35F9B")

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "FDE2F2"), Color(hex: "F7F7F9"), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if monthGroups.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.appSystem(size: 35, weight: .semibold))
                                    .foregroundColor(rose.opacity(0.60))
                                Text("暂无胎动记录")
                                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "737780"))
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                        } else {
                            ForEach(monthGroups) { group in
                                monthSection(group)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .confirmationDialog(
            "删除这条胎动记录？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let entry = pendingDeletion else { return }
                Task {
                    if !(await viewModel.deleteFetalMovement(id: entry.id)) {
                        operationError = viewModel.errorMessage
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert(
            "未能删除胎动记录",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(operationError ?? "请稍后重试。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("历史胎动")
                    .font(.appSystem(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3E4148"))
                Text("共 \(viewModel.fetalMovements.count) 条记录")
                    .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "777C85"))
            }

            Spacer(minLength: 8)

            Image(systemName: "figure.and.child.holdinghands")
                .font(.appSystem(size: 36, weight: .semibold))
                .foregroundColor(rose.opacity(0.45))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.appSystem(size: 14, weight: .black))
                    .foregroundColor(Color(hex: "45484E"))
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.surface.opacity(0.92), in: Circle())
            }
            .accessibilityLabel("关闭")
        }
    }

    private func monthSection(_ group: FetalMovementMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.monthFormatter.string(from: group.monthStart))
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "41444A"))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.appSystem(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "777C85"))
                            .frame(width: 20)
                        Text(Self.dateTimeFormatter.string(from: entry.occurredAt))
                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "3F4249"))
                        Spacer(minLength: 8)
                        Menu {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                pendingDeletion = entry
                                showsDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.appSystem(size: 16, weight: .bold))
                                .foregroundColor(Color(hex: "8A8E95"))
                                .frame(width: 44, height: 48)
                        }
                        .accessibilityLabel("管理 \(Self.dateTimeFormatter.string(from: entry.occurredAt)) 的胎动记录")
                        .disabled(!viewModel.canMutate)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)

                    if entry.id != group.entries.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var monthGroups: [FetalMovementMonthGroup] {
        PregnancyAnalytics.groupFetalMovementsByMonth(viewModel.fetalMovements)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "MM月"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
