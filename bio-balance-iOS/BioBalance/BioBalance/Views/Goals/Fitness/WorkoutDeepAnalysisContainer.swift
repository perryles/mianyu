/// WorkoutDeepAnalysisContainer 负责在训练报告页按会话加载深度分析（爬升/分段），
/// 并处理「无会话 / 加载中 / 样本不足」三种降级态。

import SwiftUI

private struct WorkoutAnalysisTaskID: Equatable {
    let date: Date
    let workoutID: UUID?
}

struct WorkoutDeepAnalysisContainer: View {
    let viewModel: FitnessCalendarViewModel
    let date: Date
    let accent: Color
    var preferredWorkoutID: UUID? = nil

    @State private var references: [WorkoutSessionReference] = []
    @State private var reports: [UUID: WorkoutAnalysisReport] = [:]
    @State private var selectedReferenceID: UUID?
    @State private var isLoading = true
    @State private var hasLoadedOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isLoading && !hasLoadedOnce {
                loadingCard
            } else if let report = selectedReport {
                if references.count > 1 {
                    sessionPicker
                }
                WorkoutAnalysisSection(report: report, accent: accent)
            }
            // references 为空或报告为 nil（样本不足）时不渲染任何区块，保持报告页干净。
        }
        .task(id: WorkoutAnalysisTaskID(date: date, workoutID: preferredWorkoutID)) {
            await loadReferences()
        }
    }

    private var selectedReport: WorkoutAnalysisReport? {
        if let selectedReferenceID, let report = reports[selectedReferenceID] {
            return report
        }
        // Prefer the exact workout that owns the surrounding report; otherwise use the
        // longest session for legacy report pages that do not provide an ID.
        let preferredReference = references.first { $0.id == preferredWorkoutID }
        let selectedReference = preferredReference ?? references.max(by: { $0.durationMinutes < $1.durationMinutes })
        return selectedReference.flatMap { reports[$0.id] }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在读取训练轨迹…")
                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(18)
        .background(Theme.Colors.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(accent.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(references) { reference in
                    Button {
                        selectedReferenceID = reference.id
                        Task { await loadReport(for: reference) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(reference.activityTitle)
                            Text("\(Int(reference.durationMinutes.rounded())) 分")
                                .opacity(0.72)
                        }
                        .font(.appSystem(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(selectedReferenceID == reference.id ? .white : accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedReferenceID == reference.id ? accent : accent.opacity(0.10),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func loadReferences() async {
        isLoading = true
        references = await viewModel.loadWorkoutSessionReferences(for: date)
        hasLoadedOnce = true
        // Prefer the exact workout that owns the surrounding report; fall back to the
        // longest session for report pages that do not provide a preferred ID.
        let preferredReference = references.first { $0.id == preferredWorkoutID }
        let selectedReference = preferredReference ?? references.max(by: { $0.durationMinutes < $1.durationMinutes })
        if let selectedReference {
            selectedReferenceID = selectedReference.id
            await loadReport(for: selectedReference)
        } else {
            isLoading = false
        }
    }

    private func loadReport(for reference: WorkoutSessionReference) async {
        isLoading = true
        if let report = await viewModel.loadWorkoutAnalysisReport(for: reference) {
            reports[reference.id] = report
        }
        isLoading = false
    }
}
