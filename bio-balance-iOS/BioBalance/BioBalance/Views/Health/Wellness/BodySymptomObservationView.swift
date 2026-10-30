/// BodySymptomObservationView 由健康页或记录入口调用，作为「身体症状观察」页面。
/// 负责提供症状选择、严重程度设定、备注添加和可选详情记录。

import SwiftUI
import Charts

struct BodySymptomObservationView: View {
    @State private var viewModel = SelfObservationViewModel(summaryScope: .symptomObservations)
    @State private var selectedSymptoms: Set<SelfObservationSymptom> = []
    @State private var symptomSeverity = 0
    @State private var note = ""
    @State private var showsOptionalDetails = false
    @State private var showingSafetyAlert = false
    @State private var associationSnapshot: SelfObservationAssociationSnapshot?
    @State private var isLoadingAssociation = false
    @State private var lastSavedAt: Date?

    private let associationLoader = SelfObservationAssociationLoader()

    private var symptomRecords: [SelfObservationRecord] {
        viewModel.records.filter(\.isSymptomObservation)
    }

    private var recentRecords: [SelfObservationRecord] {
        Array(symptomRecords.prefix(8))
    }

    private var latestSymptomRecord: SelfObservationRecord? {
        symptomRecords.first
    }

    private var safetyAssessment: SelfObservationSafetyAssessment {
        SelfObservationSafetyEvaluator.evaluate(
            symptoms: selectedSymptoms,
            severity: symptomSeverity
        )
    }

    var body: some View {
        ZStack {
            HealthDetailPageBackground()

            AdaptivePageScrollView(style: .reading, topPadding: 18, bottomPadding: 96) {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    quickRecordCard

                    if let latestRecord = latestSymptomRecord {
                        associationCard(record: latestRecord)
                    }

                    SelfObservationSymptomTrendCard(days: 14, summaries: viewModel.summaries)
                    recentRecordsCard
                }
            }
        }
        .healthDetailNavigation(title: HealthPageName.symptomObservation)
        .task(id: latestSymptomRecord?.id) {
            guard let latestRecord = latestSymptomRecord else { return }
            await loadAssociation(for: latestRecord)
        }
        .alert("请先关注当前症状", isPresented: $showingSafetyAlert) {
            Button("保存记录") {
                saveObservation()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(safetyAssessment.detail)\n\n\(safetyAssessment.actionText)")
        }
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("身体症状观察")
                    .font(.appSystem(size: 27, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "2C333C"))
                    .fixedSize(horizontal: false, vertical: true)

                Text(lastSavedText)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(SelfObservationCatalog.symptomTint.opacity(0.11))
                Image(systemName: "cross.case.fill")
                    .font(.appSystem(size: 24, weight: .black))
                    .foregroundColor(SelfObservationCatalog.symptomTint)
            }
            .frame(width: 58, height: 58)
        }
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color(hex: "84A7D9").opacity(0.09), radius: 12, x: 0, y: 7)
    }

    private var quickRecordCard: some View {
        ReportsContentCard(spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                ReportsSectionHeader("15 秒快速记录", subtitle: currentObservationText)

                Spacer(minLength: 0)

                Text("\(selectedSymptoms.count)/3")
                    .font(.appSystem(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(SelfObservationCatalog.symptomTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SelfObservationCatalog.symptomTint.opacity(0.10), in: Capsule())
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(SelfObservationSymptom.allCases) { symptom in
                    symptomButton(symptom)
                }
            }

            if !selectedSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("不适强度")
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "4A515A"))

                    HStack(spacing: 8) {
                        intensityButton(value: 1, title: "轻微")
                        intensityButton(value: 3, title: "影响状态")
                        intensityButton(value: 5, title: "需要重视")
                    }
                }
            }

            if safetyAssessment.level != .none {
                safetyCard(safetyAssessment)
            }

            optionalNote
            saveButton
        }
    }

    private func symptomButton(_ symptom: SelfObservationSymptom) -> some View {
        let isSelected = selectedSymptoms.contains(symptom)
        let isDisabled = !isSelected && selectedSymptoms.count >= 3

        return Button {
            toggle(symptom)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symptom.systemImage)
                    .font(.appSystem(size: 16, weight: .black))
                Text(symptom.title)
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "4A515A"))
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                isSelected ? SelfObservationCatalog.symptomTint : Color(hex: "F5F6F3"),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SelfObservationCatalog.symptomTint.opacity(isSelected ? 0 : 0.10), lineWidth: 1)
            )
            .opacity(isDisabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func intensityButton(value: Int, title: String) -> some View {
        let isSelected = symptomSeverity == value

        return Button {
            symptomSeverity = value
        } label: {
            VStack(spacing: 3) {
                Text("\(value)")
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                Text(title)
                    .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "555D66"))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                isSelected ? SelfObservationCatalog.symptomTint : Color(hex: "F5F6F3"),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var optionalNote: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsOptionalDetails.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.appSystem(size: 14, weight: .black))
                    Text("补充备注")
                        .font(.appSystem(size: 13, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Image(systemName: showsOptionalDetails ? "chevron.up" : "chevron.down")
                        .font(.appSystem(size: 12, weight: .black))
                }
                .foregroundColor(Color(hex: "6F7780"))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)

            if showsOptionalDetails {
                VStack(alignment: .leading, spacing: 10) {
                    Text("触发场景或缓解方式")
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "555D66"))

                    TextField("触发场景或缓解方式（选填）", text: $note, axis: .vertical)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
                        )
                }
                .padding(12)
                .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
    }

    private func safetyCard(_ assessment: SelfObservationSafetyAssessment) -> some View {
        let tint = assessment.level == .urgent ? Color(hex: "E84D4D") : Color(hex: "E69B32")

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: assessment.level == .urgent ? "cross.case.fill" : "exclamationmark.triangle.fill")
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(assessment.title)
                    .font(.appSystem(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3F464E"))
                Text(assessment.detail)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "737B84"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var saveButton: some View {
        Button {
            attemptSave()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.appSystem(size: 17, weight: .bold))
                Text(selectedSymptoms.isEmpty ? "请先选择症状" : "保存症状记录")
                    .font(.appSystem(size: 15, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                selectedSymptoms.isEmpty ? Color(hex: "AAB5C2") : SelfObservationCatalog.symptomTint,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedSymptoms.isEmpty)
    }

    private func associationCard(record: SelfObservationRecord) -> some View {
        ReportsContentCard(spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ReportsSectionHeader("症状前 24 小时", subtitle: "\(record.symptomTitleText) · \(shortTime(record.recordedAt))")
                Spacer(minLength: 0)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.appSystem(size: 17, weight: .black))
                    .foregroundColor(SelfObservationCatalog.accent)
            }

            if isLoadingAssociation && associationSnapshot?.recordID != record.id {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在整理时间线索")
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else if let snapshot = associationSnapshot, snapshot.recordID == record.id {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.headline)
                        .font(.appSystem(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(snapshot.detail)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if snapshot.items.isEmpty {
                    ReportsInlineEmptyState(text: "继续积累睡眠、压力、咖啡因、用药和餐食记录")
                } else {
                    VStack(spacing: 9) {
                        ForEach(snapshot.items) { item in
                            associationRow(item)
                        }
                    }
                }
            }
        }
    }

    private func associationRow(_ item: SelfObservationAssociationItem) -> some View {
        let tint = associationTint(for: item.kind)

        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.kind.systemImage)
                .font(.appSystem(size: 14, weight: .black))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.kind.title)
                        .font(.appSystem(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "454D56"))
                    Text(item.valueText)
                        .font(.appSystem(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(tint)
                }
                Text(item.detail)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentRecordsCard: some View {
        ReportsContentCard(spacing: 12) {
            ReportsSectionHeader("最近观察", subtitle: "回看症状是否反复出现在相似时间和生活背景中。")

            if recentRecords.isEmpty {
                ReportsInlineEmptyState(text: "还没有身体症状与自我观察记录")
            } else {
                VStack(spacing: 9) {
                    ForEach(recentRecords) { record in
                        recordRow(record)
                    }
                }
            }
        }
    }

    private var currentObservationText: String {
        if selectedSymptoms.isEmpty {
            return "请选择当前需要记录的症状"
        }
        let titles = selectedSymptoms.map(\.title).sorted().joined(separator: "、")
        return "\(titles) · \(SelfObservationCatalog.severityText(symptomSeverity))"
    }

    private var lastSavedText: String {
        if let lastSavedAt {
            return String(localized: "刚刚已保存 · \(shortTime(lastSavedAt))")
        }
        if let latest = latestSymptomRecord {
            return String(localized: "最近记录：\(latest.symptomTitleText) · \(shortTime(latest.recordedAt))")
        }
        return String(localized: "记录身体信号，并回看发生前的生活线索")
    }

    private func toggle(_ symptom: SelfObservationSymptom) {
        if selectedSymptoms.contains(symptom) {
            selectedSymptoms.remove(symptom)
            if selectedSymptoms.isEmpty {
                symptomSeverity = 0
            }
        } else if selectedSymptoms.count < 3 {
            selectedSymptoms.insert(symptom)
            if symptomSeverity == 0 {
                symptomSeverity = 1
            }
        }
    }

    private func attemptSave() {
        guard !selectedSymptoms.isEmpty else { return }
        if safetyAssessment.requiresAcknowledgement {
            showingSafetyAlert = true
        } else {
            saveObservation()
        }
    }

    private func saveObservation() {
        guard !selectedSymptoms.isEmpty else { return }
        let record = viewModel.save(
            symptoms: selectedSymptoms,
            symptomSeverity: symptomSeverity,
            selfRating: 0,
            energy: 0,
            stressLoad: 0,
            sleepQuality: 0,
            note: note,
            answeredFields: [.symptomSeverity]
        )

        lastSavedAt = record.recordedAt
        selectedSymptoms.removeAll()
        symptomSeverity = 0
        note = ""
        showsOptionalDetails = false

    }

    @MainActor
    private func loadAssociation(for record: SelfObservationRecord) async {
        isLoadingAssociation = true
        associationSnapshot = await associationLoader.load(for: record)
        isLoadingAssociation = false
    }

    private func associationTint(for kind: SelfObservationAssociationKind) -> Color {
        switch kind {
        case .sleep: return Color(hex: "6D78E8")
        case .stress: return Color(hex: "F07167")
        case .caffeine: return Color(hex: "B48A58")
        case .medication: return Color(hex: "54A889")
        case .meal: return Color(hex: "E39A3B")
        }
    }

    private func recordRow(_ record: SelfObservationRecord) -> some View {
        let safety = SelfObservationSafetyEvaluator.evaluate(
            symptoms: Set(record.selectedSymptoms),
            severity: record.symptomSeverity
        )

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: safety.level == .urgent ? "exclamationmark.triangle.fill" : "cross.case.fill")
                .font(.appSystem(size: 15, weight: .bold))
                .foregroundColor(safety.level == .urgent ? Color(hex: "E84D4D") : SelfObservationCatalog.symptomTint)
                .frame(width: 36, height: 36)
                .background(SelfObservationCatalog.symptomTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.symptomTitleText)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("症状强度 · \(SelfObservationCatalog.severityText(record.symptomSeverity))")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(SelfObservationCatalog.symptomTint)
                if !record.note.isEmpty {
                    Text(record.note)
                        .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Text(shortTime(record.recordedAt))
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(12)
        .background(Theme.Colors.secondarySurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }
}
