/// CareTaskEditView 是照护任务的编辑/创建表单。
/// 支持康复训练和健康习惯两类任务配置。
///
/// 服药任务不在此编辑——它们仍通过 MedicationPlanSheet 管理。
/// 症状日记是固定任务类型，不可自定义。

import SwiftUI

struct CareTaskEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category: CareTaskCategory
    @State private var title: String
    @State private var subtitle: String
    @State private var icon: String
    @State private var hour: Int
    @State private var minute: Int
    @State private var durationMinutes: Int
    @State private var enableReminder: Bool
    @State private var frequency: CareScheduleFrequency
    @State private var selectedWeekdays: Set<Int>
    @State private var customInterval: Int
    @State private var targetValue: String
    @State private var unit: String
    @State private var instructions: String
    @State private var linkedModule: String?

    private let existingTask: CareTask?
    private let presetCategory: CareTaskCategory?
    private let presetLinkedModule: String?
    private let onSave: (CareTask) -> Void

    init(
        task: CareTask? = nil,
        presetCategory: CareTaskCategory? = nil,
        presetLinkedModule: String? = nil,
        onSave: @escaping (CareTask) -> Void
    ) {
        self.existingTask = task
        self.presetCategory = presetCategory
        self.presetLinkedModule = presetLinkedModule
        self.onSave = onSave

        if let task {
            _category = State(initialValue: task.category)
            _title = State(initialValue: task.title)
            _subtitle = State(initialValue: task.subtitle ?? "")
            _icon = State(initialValue: task.icon)
            _enableReminder = State(initialValue: task.schedule.isEnabled)
            _frequency = State(initialValue: task.schedule.frequency)
            _selectedWeekdays = State(initialValue: task.schedule.weekdays)
            _customInterval = State(initialValue: task.schedule.customIntervalDays)
            _instructions = State(initialValue: task.instructions ?? "")
            _linkedModule = State(initialValue: task.linkedModule)
            if let firstSlot = task.schedule.slots.first {
                _hour = State(initialValue: firstSlot.hour)
                _minute = State(initialValue: firstSlot.minute)
                _durationMinutes = State(initialValue: firstSlot.durationMinutes)
            } else {
                _hour = State(initialValue: 8)
                _minute = State(initialValue: 0)
                _durationMinutes = State(initialValue: 0)
            }
            if let target = task.targetValue {
                _targetValue = State(initialValue: floor(target) == target ? "\(Int(target))" : String(format: "%.1f", target))
            } else {
                _targetValue = State(initialValue: "")
            }
            _unit = State(initialValue: task.unit ?? "")
        } else {
            let initialCategory = presetCategory ?? .habit
            _category = State(initialValue: initialCategory)
            _title = State(initialValue: "")
            _subtitle = State(initialValue: "")
            _icon = State(initialValue: initialCategory.symbol)
            _hour = State(initialValue: 8)
            _minute = State(initialValue: 0)
            _durationMinutes = State(initialValue: presetLinkedModule == "sunlight" ? 20 : 0)
            _enableReminder = State(initialValue: true)
            _frequency = State(initialValue: .daily)
            _selectedWeekdays = State(initialValue: [])
            _customInterval = State(initialValue: 1)
            _targetValue = State(initialValue: presetLinkedModule == "sunlight" ? "20" : "")
            _unit = State(initialValue: presetLinkedModule == "sunlight" ? String(localized: "分钟") : "")
            _instructions = State(initialValue: "")
            _linkedModule = State(initialValue: presetLinkedModule)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if existingTask == nil && presetCategory == nil {
                    Section(String(localized: "任务类型")) {
                        Picker(String(localized: "类别"), selection: $category) {
                            ForEach([CareTaskCategory.rehabilitation, .habit], id: \.self) { cat in
                                Label(cat.title, systemImage: cat.symbol).tag(cat)
                            }
                        }
                    }
                }

                Section(String(localized: "基本信息")) {
                    TextField(String(localized: "任务名称"), text: $title)
                    TextField(String(localized: "副标题（可选）"), text: $subtitle)

                    if linkedModule == nil {
                        LabeledContent(String(localized: "图标")) {
                            IconPicker(selection: $icon)
                        }
                    }

                    if category == .habit || linkedModule == "sunlight" {
                        TextField(String(localized: "目标值"), text: $targetValue)
                            .keyboardType(.decimalPad)
                        TextField(String(localized: "单位"), text: $unit)
                    }

                    TextField(String(localized: "操作说明（可选）"), text: $instructions, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(String(localized: "时间安排")) {
                    Toggle(String(localized: "启用提醒"), isOn: $enableReminder)

                    if enableReminder {
                        Picker(String(localized: "时间"), selection: $hour) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        Picker(String(localized: "分钟"), selection: $minute) {
                            ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                    }

                    if category == .rehabilitation || durationMinutes > 0 {
                        Stepper("\(String(localized: "持续时长")): \(durationMinutes)\(String(localized: "分钟"))", value: $durationMinutes, in: 0...180, step: 5)
                    }
                }

                Section(String(localized: "重复规则")) {
                    Picker(String(localized: "频率"), selection: $frequency) {
                        ForEach(CareScheduleFrequency.allCases, id: \.self) { freq in
                            Text(freq.title).tag(freq)
                        }
                    }

                    if frequency == .weekly {
                        WeekdayPicker(selection: $selectedWeekdays)
                    }

                    if frequency == .customInterval {
                        Stepper("\(String(localized: "间隔")): \(customInterval)\(String(localized: "天"))", value: $customInterval, in: 1...30)
                    }
                }

                if existingTask != nil {
                    Section {
                        Button(role: .destructive) {
                            if let task = existingTask {
                                CareTaskEngine.shared.removeTask(id: task.id)
                            }
                            dismiss()
                        } label: {
                            Label(String(localized: "结束任务"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(existingTask == nil ? String(localized: "新建任务") : String(localized: "编辑任务"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) { saveTask() }
                        .disabled(title.isEmpty)
                }
            }
        }
    }

    private func saveTask() {
        let slot = CareSchedule.TimeSlot(hour: hour, minute: minute, durationMinutes: durationMinutes)
        let schedule = CareSchedule(
            isEnabled: enableReminder,
            slots: [slot],
            weekdays: selectedWeekdays,
            frequency: frequency,
            customIntervalDays: customInterval,
            startDate: existingTask?.schedule.startDate ?? Date(),
            endDate: nil
        )

        let target = Double(targetValue.replacingOccurrences(of: ",", with: "."))

        let task = CareTask(
            id: existingTask?.id ?? UUID().uuidString,
            category: category,
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            icon: icon,
            schedule: schedule,
            targetValue: target,
            unit: unit.isEmpty ? nil : unit,
            instructions: instructions.isEmpty ? nil : instructions,
            linkedModule: linkedModule,
            logicalTaskID: existingTask?.logicalTaskID,
            revision: existingTask?.revision ?? 1,
            effectiveFrom: existingTask?.effectiveFrom ?? Date(),
            effectiveUntil: existingTask?.effectiveUntil,
            sourceImportID: existingTask?.sourceImportID
        )

        onSave(task)
        dismiss()
    }
}

// MARK: - 图标选择器

private struct IconPicker: View {
    @Binding var selection: String

    private let icons = [
        "figure.cooldown", "figure.walk", "figure.run", "figure.flexibility",
        "sun.max.fill", "moon.stars.fill", "leaf.fill", "wind",
        "drop.fill", "flame.fill", "heart.fill", "brain.head.profile",
        "bed.double.fill", "cup.and.saucer.fill", "dumbbell.fill", "bicycle"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(icons, id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.appSystem(size: 18))
                        .foregroundColor(selection == icon ? .white : Theme.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(selection == icon ? Theme.Colors.mintGreen : Color.gray.opacity(0.12))
                        )
                        .onTapGesture { selection = icon }
                }
            }
        }
    }
}

// MARK: - 星期选择器

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private let symbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selection.contains(day)
                Text(symbols[day - 1])
                    .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isSelected ? Theme.Colors.mintGreen : Color.gray.opacity(0.12))
                    )
                    .onTapGesture {
                        if isSelected {
                            selection.remove(day)
                        } else {
                            selection.insert(day)
                        }
                    }
            }
        }
    }
}
