import SwiftUI

/// 健康档案的主观评估面板。
/// 评估答案仍由 Wellness/SelfObservationSupport 中的观察模型与存储负责。
struct HealthProfileSelfAssessmentPanel: View {
    typealias Question = SelfObservationAnswerField

    let title: String
    let subtitle: String
    let selectedDate: Date
    var days: Int = 14
    let questions: [Question]
    var onSaved: (() -> Void)?

    init(
        title: String,
        subtitle: String,
        selectedDate: Date,
        days: Int = 14,
        questions: [Question],
        onSaved: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selectedDate = selectedDate
        self.days = days
        self.questions = Array(questions.reduce(into: [Question]()) { result, question in
            if !result.contains(question) { result.append(question) }
        }.prefix(3))
        self.onSaved = onSaved
    }

    @State private var viewModel = SelfObservationViewModel(summaryScope: .healthProfileAssessments)
    @State private var answers: [Question: Int] = [:]
    @State private var note = ""
    @State private var isSkipped = false
    @State private var didSave = false

    private var recordsForSelectedDay: [SelfObservationRecord] {
        viewModel.records.filter {
            $0.isHealthProfileAssessment && Calendar.current.isDate($0.recordedAt, inSameDayAs: selectedDate)
        }
    }

    private var latestRecordForSelectedDay: SelfObservationRecord? {
        recordsForSelectedDay.first
    }

    private var canSave: Bool {
        !questions.isEmpty && questions.allSatisfy { answers[$0] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isSkipped {
                skippedState
            } else {
                questionsBlock
                noteField
                actions

                if didSave {
                    Label("已更新健康档案依据", systemImage: "checkmark.circle.fill")
                        .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(SelfObservationCatalog.assessmentTint)
                }
            }
        }
        .modifier(HealthProfileAssessmentChrome())
        .onAppear {
            viewModel.reload(days: days, endingAt: selectedDate)
            syncDraftFromSelectedDay()
        }
        .onChange(of: selectedDate) { _, _ in
            viewModel.reload(days: days, endingAt: selectedDate)
            syncDraftFromSelectedDay()
            isSkipped = false
            didSave = false
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.appSystem(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "18253A"))
                Text(subtitle)
                    .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if latestRecordForSelectedDay != nil {
                    Label("今日已补充，可直接修改", systemImage: "checkmark.circle.fill")
                        .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(SelfObservationCatalog.assessmentTint)
                }
            }
        }
    }

    private var questionsBlock: some View {
        VStack(spacing: 14) {
            ForEach(Array(questions.enumerated()), id: \.element) { index, question in
                if index > 0 {
                    Divider()
                        .overlay(Color(hex: "DDE4ED").opacity(0.8))
                }
                questionRow(question)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("备注（可选）")
                .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
            TextField("例如：今天工作量偏高，晚饭后缓解", text: noteBinding, axis: .vertical)
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .lineLimit(2...4)
                .padding(12)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { note },
            set: { newValue in
                note = newValue
                didSave = false
            }
        )
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: saveAnswers) {
                Label("补充到档案依据", systemImage: "checkmark.circle.fill")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        canSave ? SelfObservationCatalog.assessmentTint : Color(hex: "AAB5C2"),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)

            Button {
                isSkipped = true
            } label: {
                Label("暂不补充", systemImage: "clock")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var skippedState: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("本次未补充，不会写入档案依据。")
                .font(.appSystem(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer(minLength: 0)

            Button("继续补充") {
                isSkipped = false
            }
            .font(.appSystem(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(SelfObservationCatalog.accent)
            .frame(minHeight: 44)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func questionRow(_ question: Question) -> some View {
        let tint = tint(for: question)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(prompt(for: question))
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "253B59"))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(answers[question].map { valueText(for: question, value: $0) } ?? "请选择")
                    .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(answers[question] == nil ? Theme.Colors.textTertiary : tint)
            }

            HStack(spacing: 6) {
                ForEach(options(for: question), id: \.self) { option in
                    let isSelected = answers[question] == option
                    Button {
                        answers[question] = option
                        didSave = false
                    } label: {
                        Text("\(option)")
                            .font(.appSystem(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                            .background(isSelected ? tint : Color(hex: "EEF2F6"), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(prompt(for: question))，\(valueText(for: question, value: option))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(endpointText(for: question).low)
                Spacer()
                Text(endpointText(for: question).high)
            }
            .font(.appSystem(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    private func reportRecordDate() -> Date {
        if Calendar.current.isDateInToday(selectedDate) {
            return Date()
        }
        let start = Calendar.current.startOfDay(for: selectedDate)
        return Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: start) ?? start
    }

    private func syncDraftFromSelectedDay() {
        guard let latest = latestRecordForSelectedDay else {
            answers = [:]
            note = ""
            return
        }
        answers = Dictionary(
            uniqueKeysWithValues: questions.compactMap { question in
                latest.answer(for: question).map { (question, $0) }
            }
        )
        note = latest.note
    }

    private func saveAnswers() {
        guard canSave else { return }
        viewModel.save(
            recordedAt: reportRecordDate(),
            symptoms: Set<SelfObservationSymptom>(),
            symptomSeverity: answers[.symptomSeverity] ?? 0,
            selfRating: answers[.selfRating] ?? 0,
            energy: answers[.energy] ?? 0,
            stressLoad: answers[.stressLoad] ?? 0,
            sleepQuality: answers[.sleepQuality] ?? 0,
            note: note,
            answeredFields: Set(questions),
            replacingProfileAssessmentOnSameDay: true
        )
        viewModel.reload(days: days, endingAt: selectedDate)
        syncDraftFromSelectedDay()
        didSave = true
        onSaved?()
    }

    private func prompt(for question: Question) -> String {
        switch question {
        case .selfRating: return "今天整体感觉如何？"
        case .energy: return "今天的精力怎么样？"
        case .stressLoad: return "今天的压力负荷如何？"
        case .sleepQuality: return "昨晚睡眠后的恢复感如何？"
        case .symptomSeverity: return "症状对今天的影响有多大？"
        }
    }

    private func options(for question: Question) -> [Int] {
        question == .symptomSeverity ? Array(0...5) : Array(1...5)
    }

    private func endpointText(for question: Question) -> (low: String, high: String) {
        switch question {
        case .selfRating: return ("很差", "很好")
        case .energy: return ("很低", "很足")
        case .stressLoad: return ("很低", "很高")
        case .sleepQuality: return ("很差", "很好")
        case .symptomSeverity: return ("无影响", "需重视")
        }
    }

    private func valueText(for question: Question, value: Int) -> String {
        switch question {
        case .stressLoad:
            return ["很低", "较低", "适中", "较高", "很高"][min(5, max(1, value)) - 1]
        case .symptomSeverity:
            return SelfObservationCatalog.severityText(value)
        default:
            return SelfObservationCatalog.ratingText(value)
        }
    }

    private func tint(for question: Question) -> Color {
        switch question {
        case .selfRating: return SelfObservationCatalog.assessmentTint
        case .energy: return SelfObservationCatalog.accent
        case .stressLoad: return Color(hex: "F3A53B")
        case .sleepQuality: return Color(hex: "7D6BEB")
        case .symptomSeverity: return SelfObservationCatalog.symptomTint
        }
    }
}

private struct HealthProfileAssessmentChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .bbTintedSurface(
                tint: SelfObservationCatalog.assessmentTint,
                in: RoundedRectangle(cornerRadius: BBCardStyle.standard.cornerRadius, style: .continuous),
                tintStrength: 0.045
            )
    }
}
