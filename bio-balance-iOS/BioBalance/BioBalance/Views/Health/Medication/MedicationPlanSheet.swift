/// MedicationPlanSheet 由用药 Hub 调用，作为「用药计划」弹层。
/// 负责创建药品/补剂计划，设置剂量、单位、用途与提醒时间。

import SwiftUI

struct MedicationPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: MedicationEntryCategory
    @State private var name: String
    @State private var amountText: String
    @State private var unit: String
    @State private var purpose: String
    @State private var note: String
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var feedbackText: String?
    @State private var isSaving = false

    private let draft: MedicationPlanDraft
    private let units = ["mg", "片", "ml", "粒", "袋", "滴"]

    init(draft: MedicationPlanDraft = MedicationPlanDraft()) {
        self.draft = draft
        _category = State(initialValue: draft.category)
        _name = State(initialValue: draft.name)
        if let amount = draft.amount {
            if floor(amount) == amount {
                _amountText = State(initialValue: "\(Int(amount))")
            } else {
                _amountText = State(initialValue: String(format: "%.1f", amount))
            }
        } else {
            _amountText = State(initialValue: "")
        }
        _unit = State(initialValue: draft.unit)
        _purpose = State(initialValue: draft.purpose)
        _note = State(initialValue: draft.note)
        _reminderEnabled = State(initialValue: draft.reminderEnabled)

        var components = DateComponents()
        components.hour = draft.reminderHour
        components.minute = draft.reminderMinute
        let resolved = Calendar.current.date(from: components) ?? Date()
        _reminderTime = State(initialValue: resolved)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("计划与提醒")
                            .font(.appSystem(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "132B4F"))
                        Text("先把每天固定会吃的用药或补剂排进计划，后面就能直接从计划入口快速记录。")
                            .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("类型")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                            Picker("类型", selection: $category) {
                                ForEach(MedicationEntryCategory.allCases, id: \.self) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        inputField(
                            title: category == .medication ? "药物名称" : "补剂名称",
                            placeholder: category == .medication ? "例如：二甲双胍" : "例如：维生素 D3",
                            text: $name
                        )

                        HStack(spacing: 12) {
                            inputField(title: "剂量", placeholder: "可选", text: $amountText, keyboard: .decimalPad)
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

                        inputField(title: "计划用途", placeholder: "例如：早餐后维持、睡前支持", text: $purpose)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("备注")
                                .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                            TextField("例如：饭后服用、随餐、别空腹", text: $note, axis: .vertical)
                                .lineLimit(2, reservesSpace: true)
                                .padding(12)
                                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $reminderEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("开启每日提醒")
                                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
                                    .foregroundColor(Color(hex: "153158"))
                                Text("保存后会按固定时间推送提醒；如果系统通知没开，计划仍会先保存在本地。")
                                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        }
                        .tint(Color(hex: "3F86DD"))

                        if reminderEnabled {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("提醒时间")
                                    .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let feedbackText, !feedbackText.isEmpty {
                        Text(feedbackText)
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "A4503E"))
                    }

                    if draft.isExistingPlan {
                        Button(role: .destructive) {
                            MedicationStore.shared.removePlan(id: draft.id)
                            dismiss()
                        } label: {
                            Text("删除计划")
                                .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "C45142"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(isSaving ? "保存中..." : "保存计划")
                            .font(.appSystem(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "3F86DD"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
                .padding(20)
            }
            .background(Theme.Colors.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                }
            }
        }
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

    private func submit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            feedbackText = category == .medication ? "请先填写药物名称" : "请先填写补剂名称"
            return
        }

        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount: Double?
        if trimmedAmount.isEmpty {
            amount = nil
        } else if let parsed = Double(trimmedAmount), parsed > 0 {
            amount = parsed
        } else {
            feedbackText = String(localized: "剂量要么留空，要么填写有效数值")
            return
        }

        isSaving = true
        feedbackText = nil

        if reminderEnabled {
            _ = await LocalNotificationScheduler.requestAuthorizationIfNeeded()
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let plan = MedicationPlan(
            id: draft.id,
            category: category,
            name: trimmedName,
            amount: amount,
            unit: unit,
            purpose: trimmedPurpose.isEmpty ? nil : trimmedPurpose,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            reminder: MedicationReminderConfiguration(
                isEnabled: reminderEnabled,
                hour: components.hour ?? 8,
                minute: components.minute ?? 0
            )
        )

        MedicationStore.shared.savePlan(plan)
        isSaving = false
        dismiss()
    }
}
