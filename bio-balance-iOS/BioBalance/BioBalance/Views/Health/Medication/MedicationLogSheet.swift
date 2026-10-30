/// MedicationLogSheet 由用药 Hub 调用，作为「用药记录」弹层。
/// 负责录入药品名、剂量、单位、服药时间、用途与体感反应追踪。

import SwiftUI

struct MedicationLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: MedicationEntryCategory
    @State private var medicineName: String
    @State private var dosageText: String
    @State private var unit: String
    @State private var takenAt: Date
    @State private var purpose: String
    @State private var note: String
    @State private var reactionState: MedicationReactionState?
    @State private var reactionNote: String
    @State private var followUpMinutes: Int?
    @State private var isSubmitting = false
    @State private var feedbackText: String?

    private let draft: MedicationDraft
    private let units = ["mg", "片", "ml", "粒", "袋", "滴"]
    private let followUpOptions = [15, 30, 60, 120]
    private let healthSupport = HealthKitManager.shared.medicationHealthSyncSupport()
    private let recentSuggestions = MedicationStore.shared.frequentMedicationSummaries(limit: 5)
    private let commonTemplates: [MedicationDraft] = [
        MedicationDraft(category: .medication, name: "布洛芬", amount: 200, unit: "mg", purpose: "缓解疼痛", note: "按需服用"),
        MedicationDraft(category: .supplement, name: "维生素 C", amount: 1, unit: "片", purpose: "日常补充", note: "早餐后"),
        MedicationDraft(category: .supplement, name: "益生菌", amount: 1, unit: "粒", purpose: "肠胃调理", note: "饭后"),
        MedicationDraft(category: .supplement, name: "褪黑素", amount: 1, unit: "片", purpose: "睡前支持", note: "睡前 30 分钟")
    ]

    init(draft: MedicationDraft = MedicationDraft()) {
        self.draft = draft
        _category = State(initialValue: draft.category)
        _medicineName = State(initialValue: draft.name ?? "")
        if let amount = draft.amount {
            if floor(amount) == amount {
                _dosageText = State(initialValue: "\(Int(amount))")
            } else {
                _dosageText = State(initialValue: String(format: "%.1f", amount))
            }
        } else {
            _dosageText = State(initialValue: "")
        }
        _unit = State(initialValue: draft.unit ?? "mg")
        _takenAt = State(initialValue: draft.takenAt)
        _purpose = State(initialValue: draft.purpose ?? "")
        _note = State(initialValue: draft.note ?? "")
        _reactionState = State(initialValue: draft.reactionState)
        _reactionNote = State(initialValue: draft.reactionNote ?? "")
        _followUpMinutes = State(initialValue: draft.followUpMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    formIntro

                    quickTemplatesSection

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("类型")
                                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "3D4A5C"))
                            HStack(spacing: 8) {
                                ForEach(MedicationEntryCategory.allCases, id: \.self) { item in
                                    categoryButton(item)
                                }
                            }
                        }

                        inputField(
                            title: category == .medication ? "药物名称" : "补剂名称",
                            placeholder: category == .medication ? "例如：布洛芬" : "例如：镁甘氨酸",
                            text: $medicineName
                        )

                        HStack(spacing: 12) {
                            inputField(title: "剂量", placeholder: "例如：200", text: $dosageText, keyboard: .decimalPad)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("单位")
                                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                Picker("单位", selection: $unit) {
                                    ForEach(units, id: \.self) { value in
                                        Text(value).tag(value)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("服用时间")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                            DatePicker(
                                "服用时间",
                                selection: $takenAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        inputField(
                            title: "用途 / 触发场景",
                            placeholder: "例如：头痛时、饭后调理、睡前支持",
                            text: $purpose
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("备注")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                            TextField("例如：饭后服用、运动后补充", text: $note, axis: .vertical)
                                .lineLimit(2, reservesSpace: true)
                                .padding(12)
                                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    reactionSection
                    healthSyncCard

                    if let feedbackText, !feedbackText.isEmpty {
                        Text(feedbackText)
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "A4503E"))
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }

            Button {
                submit()
            } label: {
                Text(isSubmitting ? "保存中..." : (draft.isExistingRecord ? "保存补录" : "保存记录"))
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "3F86DD"), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.45 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Theme.Colors.pageBackground.ignoresSafeArea())
    }

    private var sheetHeader: some View {
        ZStack {
            Text(draft.isExistingRecord ? "编辑记录" : "新增记录")
                .font(.appSystem(size: 17, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "1B2F4E"))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 15, weight: .black))
                        .foregroundColor(Color(hex: "3D4A5C"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "EDF2F8"), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")

                Spacer()

                Text(category.shortTitle)
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3F86DD"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "E7F0FC"), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var formIntro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: category.symbol)
                .font(.appSystem(size: 20, weight: .black))
                .foregroundColor(Color(hex: "3F86DD"))
                .frame(width: 46, height: 46)
                .background(Color(hex: "E7F0FC"), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(draft.isExistingRecord ? "补全这次记录" : "记录实际摄入")
                    .font(.appSystem(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "132B4F"))
                Text("保留名称、剂量和实际时间；用途与服用后体感可以稍后补充。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var quickTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷填充")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            if !recentSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recentSuggestions) { item in
                            quickSuggestionChip(
                                title: item.name,
                                subtitle: "\(item.category.title) · 最近 \(relativeTimeText(for: item.lastTakenAt))"
                            ) {
                                applyDraft(MedicationStore.shared.suggestedDraft(from: item))
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(commonTemplates) { item in
                        quickSuggestionChip(
                            title: item.name ?? "常用项",
                            subtitle: "\(item.category.title) · \(doseText(amount: item.amount, unit: item.unit))"
                        ) {
                            applyDraft(item)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var reactionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("服用后体感")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
                if reactionState != nil || !reactionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("清空") {
                        reactionState = nil
                        reactionNote = ""
                        followUpMinutes = nil
                    }
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "71829A"))
                }
            }

            Text("可以当下先不填，后面从时间线点进来补录也可以。")
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(MedicationReactionState.allCases, id: \.self) { item in
                    Button {
                        reactionState = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.appSystem(size: 12, weight: .bold))
                            Text(item.shortTitle)
                                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(reactionState == item ? .white : Color(hex: "5B6C87"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            reactionState == item ? Color(hex: "4F82DD") : Color.white,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("大约多久后有感觉")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                HStack(spacing: 8) {
                    ForEach(followUpOptions, id: \.self) { value in
                        Button {
                            followUpMinutes = value
                        } label: {
                            Text("\(value) 分钟")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(followUpMinutes == value ? .white : Color(hex: "5B6C87"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    followUpMinutes == value ? Color(hex: "3F86DD") : Color.white,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("体感备注")
                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                TextField("例如：30 分钟后头痛缓了一点，或胃里有点不舒服", text: $reactionNote, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .padding(12)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func categoryButton(_ item: MedicationEntryCategory) -> some View {
        let isSelected = category == item
        return Button {
            category = item
        } label: {
            Text(item.title)
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: "3D4A5C"))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    isSelected ? Color(hex: "3F86DD") : Color.white,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func inputField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickSuggestionChip(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "173056"))
                Text(subtitle)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "73839A"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var healthSyncCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("健康同步")
                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(healthSupport.headline)
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "153158"))
            Text(healthSupport.detail)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func submit() {
        let trimmedName = medicineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDose = dosageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReactionNote = reactionNote.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            feedbackText = category == .medication ? "请先填写药物名称" : "请先填写补剂名称"
            return
        }
        guard let amount = Double(trimmedDose), amount > 0 else {
            feedbackText = String(localized: "请填写有效剂量")
            return
        }

        isSubmitting = true
        feedbackText = nil

        let entry = MedicationEntry(
            id: draft.id,
            category: category,
            name: trimmedName,
            amount: amount,
            unit: unit,
            purpose: trimmedPurpose.isEmpty ? nil : trimmedPurpose,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            reactionState: reactionState,
            reactionNote: trimmedReactionNote.isEmpty ? nil : trimmedReactionNote,
            followUpMinutes: followUpMinutes,
            takenAt: takenAt,
            planID: draft.planID,
            logicalPlanID: draft.logicalPlanID,
            planRevision: draft.planRevision,
            backendRecordedAt: nil,
            healthAppRecordedAt: draft.healthAppRecordedAt,
            healthAppStatusNote: draft.healthAppStatusNote ?? healthSupport.timelineNote
        )

        MedicationStore.shared.save(entry)
        isSubmitting = false
        dismiss()
    }

    private func applyDraft(_ draft: MedicationDraft) {
        category = draft.category
        medicineName = draft.name ?? medicineName
        if let amount = draft.amount {
            if floor(amount) == amount {
                dosageText = "\(Int(amount))"
            } else {
                dosageText = String(format: "%.1f", amount)
            }
        }
        unit = draft.unit ?? unit
        purpose = draft.purpose ?? purpose
        note = draft.note ?? note
        reactionState = draft.reactionState
        reactionNote = draft.reactionNote ?? reactionNote
        followUpMinutes = draft.followUpMinutes
        takenAt = draft.takenAt
    }

    private func doseText(amount: Double?, unit: String?) -> String {
        guard let amount, let unit, !unit.isEmpty else { return String(localized: "点击填充") }
        if floor(amount) == amount {
            return "\(Int(amount)) \(unit)"
        }
        return "\(String(format: "%.1f", amount)) \(unit)"
    }

    private func relativeTimeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
