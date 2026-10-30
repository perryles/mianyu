/// TrendSymptomsDetailComponents 作为趋势页「症状与病史」详情的支撑类型。
/// 负责定义维护目标枚举，复用健康页已维护的自我观察和用药资料。

import Charts
import SwiftUI

enum SymptomsIllnessMaintenanceTarget: String, Identifiable {
    case symptomObservation
    case healthRecords

    var id: String { rawValue }
}
/// “症状与病史”使用健康页已维护的自我观察、用药和处方资料，不依赖 HealthKit 占位指标。
struct SymptomsIllnessDetailContent: View {
    private struct SymptomFrequency: Identifiable {
        let symptom: SelfObservationSymptom
        let count: Int

        var id: String { symptom.id }
    }

    let range: TrendsRange
    let isStaticForExport: Bool
    let onOpenMaintenance: (SymptomsIllnessMaintenanceTarget) -> Void

    @State private var observationViewModel: SelfObservationViewModel
    @State private var prescriptionRecords: [MedicationPrescriptionRecord]
    @State private var medicationEntries: [MedicationEntry]

    private let accent = Color(hex: "C98BFF")
    private let symptomTint = SelfObservationCatalog.symptomTint

    init(
        range: TrendsRange,
        isStaticForExport: Bool = false,
        onOpenMaintenance: @escaping (SymptomsIllnessMaintenanceTarget) -> Void = { _ in }
    ) {
        self.range = range
        self.isStaticForExport = isStaticForExport
        self.onOpenMaintenance = onOpenMaintenance

        let observationViewModel = SelfObservationViewModel(summaryScope: .symptomObservations)
        observationViewModel.reload(days: range.windowDays, scope: .symptomObservations)
        _observationViewModel = State(initialValue: observationViewModel)
        _prescriptionRecords = State(initialValue: MedicationPrescriptionStore.shared.allRecords())
        _medicationEntries = State(initialValue: MedicationStore.shared.allEntries())
    }

    private var rangeDays: Int { range.windowDays }

    private var symptomRecords: [SelfObservationRecord] {
        observationViewModel.records
            .filter { record in
                record.isSymptomObservation &&
                    record.recordedAt >= range.startDate &&
                    record.recordedAt <= Date()
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    private var validSummaries: [SelfObservationDailySummary] {
        observationViewModel.summaries.filter(\.hasData)
    }

    private var symptomDayCount: Int {
        Set(symptomRecords.map { Calendar.current.startOfDay(for: $0.recordedAt) }).count
    }

    private var averageSeverity: Double? {
        guard !symptomRecords.isEmpty else { return nil }
        return symptomRecords.map { Double($0.symptomSeverity) }.reduce(0, +) / Double(symptomRecords.count)
    }

    private var topSymptoms: [SymptomFrequency] {
        Dictionary(grouping: symptomRecords.flatMap(\.selectedSymptoms), by: { $0 })
            .map { SymptomFrequency(symptom: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.symptom.title < $1.symptom.title }
                return $0.count > $1.count
            }
    }

    private var visibleSymptomRecords: [SelfObservationRecord] {
        Array(symptomRecords.prefix(6))
    }

    private var rangeMedicationEntries: [MedicationEntry] {
        medicationEntries.filter { $0.takenAt >= range.startDate && $0.takenAt <= Date() }
    }

    private var conditionNames: [String] {
        var seen = Set<String>()
        return prescriptionRecords
            .flatMap(\.conditions)
            .map(\.name)
            .filter { name in
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return false }
                return seen.insert(normalized).inserted
            }
    }

    var body: some View {
        VStack(spacing: 14) {
            symptomWindowCard
            historySummaryCard
            maintenanceSection
        }
        .onAppear(perform: reloadSharedData)
        .onChange(of: range) { _, _ in
            reloadSharedData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .medicationPrescriptionRecordsDidChange)) { _ in
            reloadSharedData()
        }
    }

    private var symptomWindowCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: range == .day ? "今天的症状记录" : "症状强度与频次",
                subtitle: symptomWindowSummary,
                symbol: "waveform.path.ecg",
                tint: symptomTint
            )

            HStack(spacing: 8) {
                summaryPill(title: "记录", value: "\(symptomRecords.count) 次", tint: accent)
                summaryPill(title: "症状日", value: "\(symptomDayCount) 天", tint: symptomTint)
                summaryPill(
                    title: "平均强度",
                    value: averageSeverity.map { String(format: "%.1f/5", $0) } ?? "--",
                    tint: Color(hex: "F3A53B")
                )
            }

            if symptomRecords.isEmpty {
                emptySymptomsState
            } else if range == .day {
                todayTimeline
            } else {
                symptomTrendChart
                commonSymptomsRow
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var todayTimeline: some View {
        VStack(spacing: 0) {
            ForEach(visibleSymptomRecords) { record in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(severityTint(record.symptomSeverity))
                            .frame(width: 10, height: 10)
                        if record.id != visibleSymptomRecords.last?.id {
                            Rectangle()
                                .fill(Theme.Colors.secondaryBackground)
                                .frame(width: 2, height: 42)
                        }
                    }
                    .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(record.symptomTitleText)
                                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Spacer(minLength: 6)
                            Text(timeText(record.recordedAt))
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        Text("强度 · \(SelfObservationCatalog.severityText(record.symptomSeverity))")
                            .font(.appSystem(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(severityTint(record.symptomSeverity))

                        if !record.note.isEmpty {
                            Text(record.note)
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.bottom, record.id != visibleSymptomRecords.last?.id ? 10 : 0)
                }
            }
        }
    }

    private var symptomTrendChart: some View {
        Chart(validSummaries) { item in
            BarMark(
                x: .value("日期", item.date, unit: .day),
                y: .value("症状强度", item.symptomSeverity)
            )
            .foregroundStyle(symptomTint.opacity(0.24))
            .cornerRadius(4)

            LineMark(
                x: .value("日期", item.date, unit: .day),
                y: .value("症状强度", item.symptomSeverity)
            )
            .foregroundStyle(symptomTint)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            PointMark(
                x: .value("日期", item.date, unit: .day),
                y: .value("症状强度", item.symptomSeverity)
            )
            .foregroundStyle(symptomTint)
            .symbolSize(26)
        }
        .chartYScale(domain: 0...5)
        .chartXScale(domain: range.dateDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                AxisGridLine().foregroundStyle(Color(hex: "E8EAEE"))
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5]) { _ in
                AxisGridLine().foregroundStyle(Color(hex: "E8EAEE"))
                AxisValueLabel()
                    .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Theme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(height: range == .week ? 190 : 210)
        .accessibilityLabel("症状强度趋势")
        .accessibilityValue(symptomWindowSummary)
    }

    @ViewBuilder
    private var commonSymptomsRow: some View {
        if !topSymptoms.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("当前窗口常见症状")
                    .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.Colors.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(topSymptoms.prefix(5))) { item in
                            Label("\(item.symptom.title) · \(item.count)", systemImage: item.symptom.systemImage)
                                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "4D5B70"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(symptomTint.opacity(0.09), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var historySummaryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeader(
                title: "病史资料",
                subtitle: historySummary,
                symbol: "cross.case.fill",
                tint: accent
            )

            HStack(spacing: 8) {
                summaryPill(title: "处方资料", value: "\(prescriptionRecords.count) 份", tint: accent)
                summaryPill(title: "相关情况", value: "\(conditionNames.count) 项", tint: symptomTint)
                summaryPill(title: "窗口用药", value: "\(rangeMedicationEntries.count) 次", tint: Color(hex: "5DADE2"))
            }

            if conditionNames.isEmpty && prescriptionRecords.isEmpty && medicationEntries.isEmpty {
                Text("健康页还没有维护用药、处方或相关情况。补充后，这里会显示摘要，趋势页不会自行推断病史。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "F7F5FA"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !conditionNames.isEmpty {
                        historyFactRow(
                            symbol: "doc.text.magnifyingglass",
                            title: "已维护情况",
                            value: conditionNames.prefix(3).joined(separator: "、")
                        )
                    }
                    if let latestPrescription = prescriptionRecords.first {
                        historyFactRow(
                            symbol: "calendar",
                            title: "最近资料",
                            value: "\(latestPrescription.summaryTitle) · \(shortDateText(latestPrescription.importedAt))"
                        )
                    }
                    if !rangeMedicationEntries.isEmpty {
                        historyFactRow(
                            symbol: "pills.fill",
                            title: "当前窗口",
                            value: "记录了 \(rangeMedicationEntries.count) 次用药或补剂"
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.Colors.surfaceBorder, lineWidth: 1)
        )
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("维护健康记录")
                .font(.appSystem(size: 14, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            maintenanceControl(
                target: .symptomObservation,
                title: "记录或回看症状",
                detail: symptomRecords.first.map { "最近：\($0.symptomTitleText) · \(shortDateText($0.recordedAt))" } ?? "补充症状、强度和发生背景",
                symbol: "bandage.fill",
                tint: symptomTint
            )

            maintenanceControl(
                target: .healthRecords,
                title: "维护病史资料",
                detail: "管理用药、补剂、处方和症状联动记录",
                symbol: "folder.fill",
                tint: accent
            )
        }
    }

    @ViewBuilder
    private func maintenanceControl(
        target: SymptomsIllnessMaintenanceTarget,
        title: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        let label = maintenanceLabel(title: title, detail: detail, symbol: symbol, tint: tint)
        if isStaticForExport {
            label
        } else {
            Button {
                onOpenMaintenance(target)
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private func maintenanceLabel(title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.appSystem(size: 16, weight: .black))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appSystem(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !isStaticForExport {
                Image(systemName: "chevron.right")
                    .font(.appSystem(size: 12, weight: .black))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.13), lineWidth: 1)
        )
    }

    private var emptySymptomsState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.appSystem(size: 17, weight: .black))
                .foregroundColor(symptomTint)
                .frame(width: 38, height: 38)
                .background(symptomTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("当前窗口没有症状记录")
                    .font(.appSystem(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("这不等同于没有症状。按需记录后，页面会使用真实记录形成频次和强度趋势。")
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFF8F6"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var symptomWindowSummary: String {
        guard let latest = symptomRecords.first else {
            return range == .day
                ? "按事件回看今天记录的症状、强度和备注。"
                : "使用健康页的真实记录，按天观察出现频率与强度。"
        }
        if range == .day {
            return String(localized: "最近一次为 \(latest.symptomTitleText)，强度为\(SelfObservationCatalog.severityText(latest.symptomSeverity))。")
        }
        return SelfObservationCatalog.symptomTrendInsight(from: observationViewModel.summaries)
    }

    private var historySummary: String {
        if prescriptionRecords.isEmpty && medicationEntries.isEmpty {
            return String(localized: "仅展示健康页中由你维护的资料，不根据症状自动推断疾病。")
        }
        if let latest = prescriptionRecords.first {
            return String(localized: "最近资料为“\(latest.summaryTitle)”，症状和病史分别维护、按需对照。")
        }
        return String(localized: "已有 \(medicationEntries.count) 条用药或补剂记录，可与症状时间线按需对照。")
    }

    private func sectionHeader(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.appSystem(size: 15, weight: .black))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appSystem(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func summaryPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.appSystem(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func historyFactRow(symbol: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.appSystem(size: 12, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 18)
            Text(title)
                .font(.appSystem(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "33445D"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func severityTint(_ severity: Int) -> Color {
        switch severity {
        case 0...1: return Color(hex: "7CD992")
        case 2: return Color(hex: "F3C45A")
        case 3: return Color(hex: "F3A53B")
        default: return symptomTint
        }
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale.autoupdatingCurrent).hour().minute())
    }

    private func shortDateText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale.autoupdatingCurrent).month().day())
    }

    private func reloadSharedData() {
        observationViewModel.reload(days: rangeDays, scope: .symptomObservations)
        prescriptionRecords = MedicationPrescriptionStore.shared.allRecords()
        medicationEntries = MedicationStore.shared.allEntries()
    }
}
