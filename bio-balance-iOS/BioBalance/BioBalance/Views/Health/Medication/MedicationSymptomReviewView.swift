import SwiftUI

/// A compact, read-only summary of real medication and symptom records.
/// The values are derived on device and are never persisted as inferred relationships.
struct MedicationSymptomReviewView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var path: [MedicationRoute]
    @State private var review = MedicationSymptomReviewEngine.make(entries: [], symptomRecords: [])
    @State private var showingMedicationLog = false

    private let medicationStore: MedicationStore
    private let observationStore: SelfObservationStore

    init(
        path: Binding<[MedicationRoute]>,
        medicationStore: MedicationStore = .shared,
        observationStore: SelfObservationStore = .shared
    ) {
        _path = path
        self.medicationStore = medicationStore
        self.observationStore = observationStore
    }

    private var hasRecords: Bool {
        review.medicationEntryCount > 0 || review.symptomRecordCount > 0
    }

    private var metricColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: MedicationSymptomReviewLayout.metricColumnCount(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryHeader

                if hasRecords {
                    metricsCard
                    findingsCard
                } else {
                    emptyState
                }

                recordActions
                safetyNotice
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .medicationPage(
            title: String(localized: "14 天药症回看"),
            subtitle: String(localized: "只整理真实记录，不判断因果")
        )
        .onAppear(perform: reload)
        .sheet(isPresented: $showingMedicationLog, onDismiss: reload) {
            MedicationLogSheet(draft: MedicationDraft())
                .adaptiveSheetChrome(style: .reading, dragIndicator: .visible)
        }
    }

    private var summaryHeader: some View {
        MedicationCard(tint: Theme.Colors.mintGreen) {
            VStack(alignment: .leading, spacing: 10) {
                Label("14 天", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.mintGreen)
                Text("基于本机记录即时汇总，不补齐未记录的日期。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var metricsCard: some View {
        MedicationCard {
            VStack(alignment: .leading, spacing: 14) {
                MedicationSectionHeader(
                    title: String(localized: "记录概览"),
                    detail: String(localized: "14 天")
                )
                LazyVGrid(columns: metricColumns, spacing: 10) {
                    reviewMetric(String(localized: "用药"), String(localized: "\(review.medicationEntryCount) 条"))
                    reviewMetric(String(localized: "用药日"), String(localized: "\(review.medicationActiveDays) 天"))
                    reviewMetric(String(localized: "症状"), String(localized: "\(review.symptomRecordCount) 条"))
                    reviewMetric(String(localized: "症状日"), String(localized: "\(review.symptomActiveDays) 天"))
                    reviewMetric(String(localized: "体感覆盖"), reactionCoverageText)
                    reviewMetric(String(localized: "需补体感"), String(localized: "\(review.pendingReactionCount) 条"))
                    reviewMetric(String(localized: "不适体感"), String(localized: "\(review.uncomfortableCount) 条"))
                    reviewMetric(String(localized: "24 小时重叠"), String(localized: "\(review.overlapCount) 条"))
                }
            }
        }
        .accessibilityIdentifier("medication.symptom-review.metrics")
    }

    private var findingsCard: some View {
        MedicationCard {
            VStack(alignment: .leading, spacing: 14) {
                MedicationSectionHeader(title: String(localized: "回看线索"))

                Text(findingText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(findingText)

                if review.requiresMedicalAttention {
                    Label(
                        "记录中存在较高强度或胸部不适症状。若症状严重、持续或加重，请及时联系医疗专业人员；紧急情况请立即寻求急救。",
                        systemImage: "cross.case.fill"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.Colors.accentRed)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.accentRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("最近 14 天还没有记录。", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("记录实际发生的用药或症状后，这里会显示本机汇总；没有记录不代表没有服药或没有症状。")
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .padding(.horizontal, 16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("medication.symptom-review.empty")
    }

    private var recordActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            MedicationSectionHeader(title: String(localized: "补充真实记录"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actionButtons }
                VStack(spacing: 10) { actionButtons }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        BBSecondaryButton(title: String(localized: "记录用药")) { showingMedicationLog = true }
            .frame(maxWidth: .infinity, minHeight: 48)
            .accessibilityIdentifier("medication.symptom-review.log-medication")
        MedicationPrimaryButton(title: String(localized: "记录当前症状")) { path.append(.symptomLog) }
            .accessibilityIdentifier("medication.symptom-review.log-symptom")
    }

    private var safetyNotice: some View {
        Label(
            "时间重叠仅供就诊前整理，不代表药物导致症状；请勿据此自行停药、换药或调整剂量。",
            systemImage: "shield.checkered"
        )
        .font(.caption.bold())
        .foregroundStyle(Theme.Colors.accentOrange)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accentOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("medication.symptom-review.safety")
    }

    private var reactionCoverageText: String {
        review.reactionCoverage.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
    }

    private var findingText: String {
        guard let symptom = review.mostFrequentSymptom else {
            return String(localized: "窗口内还没有可汇总的症状记录。")
        }
        return String(
            localized: "最常记录：\(symptom.title)；\(review.overlapCount) 条症状记录的前 24 小时存在用药或补剂记录。"
        )
    }

    private func reviewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.pageBackground, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func reload() {
        review = MedicationSymptomReviewEngine.make(
            entries: medicationStore.allEntries(),
            symptomRecords: observationStore.allRecords()
        )
    }
}

#Preview {
    NavigationStack {
        MedicationSymptomReviewView(path: .constant([]))
    }
}
