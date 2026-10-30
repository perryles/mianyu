import SwiftUI

struct DailyRecoveryPlanCard: View {
    let title: String
    let plan: DailyRecoveryOrchestrationPlan

    @State private var actionStates: [String: DailyRecoveryActionStateRecord] = [:]
    @State private var actionPendingSkipReason: RecoveryPlanActionPresentation?

    private let store: DailyRecoveryOrchestrationStore

    init(
        title: String,
        plan: DailyRecoveryOrchestrationPlan,
        store: DailyRecoveryOrchestrationStore = .shared
    ) {
        self.title = title
        self.plan = plan
        self.store = store
    }

    var body: some View {
        BBCard(style: .standard) {
            VStack(alignment: .leading, spacing: 14) {
                header
                mainGoal

                if !supportingActions.isEmpty {
                    Divider()
                        .overlay(Color.black.opacity(0.05))

                    VStack(spacing: 10) {
                        ForEach(supportingActions) { action in
                            actionRow(action)
                        }
                    }
                }

                if !plan.deferredSuggestions.isEmpty {
                    Label("其余建议已暂缓，避免今天目标过多或互相冲突。", systemImage: "shield.lefthalf.filled")
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            reloadStates()
            refreshWatchProjection()
        }
        .onChange(of: plan.allActionIDs) { _, _ in
            reloadStates()
            refreshWatchProjection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyRecoveryActionStateDidChange)) { notification in
            guard let changedPlanID = notification.userInfo?["planID"] as? String,
                  changedPlanID == plan.planID else { return }
            reloadStates()
        }
        .confirmationDialog(
            "为什么暂时跳过？",
            isPresented: Binding(
                get: { actionPendingSkipReason != nil },
                set: { visible in
                    if !visible { actionPendingSkipReason = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            skipReasonButton("今天没有合适时间")
            skipReasonButton("当前状态不适合")
            skipReasonButton("这项建议对我帮助不大")
            Button("取消", role: .cancel) { actionPendingSkipReason = nil }
        } message: {
            Text(actionPendingSkipReason?.title ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: "scope")
                .font(.appSystem(size: 15, weight: .black, design: .rounded))
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer(minLength: 8)

            BBStatusBadge(
                title: "\(processedActionCount)/\(allActions.count)",
                systemImage: processedActionCount == allActions.count ? "checkmark" : "checklist",
                tint: processedActionCount == allActions.count ? Theme.Colors.mintGreen : Color(hex: "4C7DFF")
            )
            .accessibilityLabel("\(plan.completionBudgetText)，已处理 \(processedActionCount) 项")
        }
    }

    private var mainGoal: some View {
        actionRow(mainAction)
    }

    private var mainAction: RecoveryPlanActionPresentation {
        RecoveryPlanActionPresentation(
            id: plan.mainActionID,
            title: plan.mainGoal,
            detail: plan.mainGoalDetail,
            symbol: "flag.fill",
            isMain: true
        )
    }

    private var supportingActions: [RecoveryPlanActionPresentation] {
        zip(plan.supportingActionIDs, plan.supportingActions).enumerated().map { index, pair in
            RecoveryPlanActionPresentation(
                id: pair.0,
                title: pair.1,
                detail: nil,
                symbol: "\(index + 1).circle.fill",
                isMain: false
            )
        }
    }

    private var allActions: [RecoveryPlanActionPresentation] {
        [mainAction] + supportingActions
    }

    private var processedActionCount: Int {
        allActions.reduce(into: 0) { count, action in
            if let state = actionStates[action.id]?.state, state != .pending {
                count += 1
            }
        }
    }

    private func actionRow(_ action: RecoveryPlanActionPresentation) -> some View {
        let state = actionStates[action.id]?.state ?? .pending
        let style = RecoveryPlanActionStateStyle(state: state)

        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: style.symbol(for: action))
                .font(.appSystem(size: action.isMain ? 15 : 14, weight: .bold))
                .foregroundColor(style.tint)
                .frame(width: 28, height: 28)
                .background(style.tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(action.title)
                    .font(.appSystem(size: action.isMain ? 17 : 13, weight: .black, design: .rounded))
                    .foregroundColor(state == .completed ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .strikethrough(state == .completed, color: Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if state != .pending {
                    BBStatusBadge(
                        title: style.title,
                        systemImage: style.statusSymbol,
                        tint: style.tint
                    )
                }

                if let detail = action.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let reason = actionStates[action.id]?.reason, !reason.isEmpty {
                    Text("原因：\(reason)")
                        .font(.appSystem(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                if state == .completed {
                    feedbackPicker(for: action)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                if state == .pending {
                    Button {
                        setState(.completed, for: action)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.appSystem(size: 19, weight: .bold))
                            .foregroundColor(Theme.Colors.mintGreen)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("完成\(action.title)")
                }

                actionMenu(action, state: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func actionMenu(_ action: RecoveryPlanActionPresentation, state: DailyRecoveryActionState) -> some View {
        Menu {
            if state == .pending {
                Button {
                    setState(.completed, for: action)
                } label: {
                    Label("完成", systemImage: "checkmark.circle")
                }

                Button {
                    setState(.snoozed, for: action)
                } label: {
                    Label("稍后", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    actionPendingSkipReason = action
                } label: {
                    Label("跳过", systemImage: "forward.end")
                }

                Button {
                    setState(.notApplicable, for: action, reason: "当前不适用")
                } label: {
                    Label("不适用", systemImage: "nosign")
                }
            } else {
                Button {
                    store.undoActionState(for: action.id)
                    reloadStates()
                } label: {
                    Label("撤销处理", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.appSystem(size: 18, weight: .bold))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("处理\(action.title)")
    }

    private func skipReasonButton(_ reason: String) -> some View {
        Button(reason) {
            guard let action = actionPendingSkipReason else { return }
            setState(.skipped, for: action, reason: reason)
            actionPendingSkipReason = nil
        }
    }

    private func setState(
        _ state: DailyRecoveryActionState,
        for action: RecoveryPlanActionPresentation,
        reason: String? = nil
    ) {
        store.setActionState(
            state,
            actionID: action.id,
            planID: plan.planID,
            reason: reason,
            actionTitle: action.title,
            plannedFor: plan.date
        )
        reloadStates()
    }

    private func feedbackPicker(for action: RecoveryPlanActionPresentation) -> some View {
        let selected = actionStates[action.id]?.feedback
        return VStack(alignment: .leading, spacing: 7) {
            Text("完成后感觉（可选）")
                .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Theme.Colors.textTertiary)

            HStack(spacing: 6) {
                ForEach(DailyRecoveryActionFeedback.allCases, id: \.self) { feedback in
                    Button {
                        store.setFeedback(selected == feedback ? nil : feedback, actionID: action.id)
                        reloadStates()
                    } label: {
                        Label(feedback.title, systemImage: feedback.systemImage)
                            .font(.appSystem(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(selected == feedback ? .white : Theme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                selected == feedback ? Theme.Colors.mintGreen : Color(hex: "EEF3F1"),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("完成后感觉：\(feedback.title)")
                    .accessibilityAddTraits(selected == feedback ? .isSelected : [])
                }
            }
        }
    }

    private func reloadStates() {
        actionStates = store.actionStates(for: plan)
    }

    private func refreshWatchProjection() {
        Task { @MainActor in
            WatchConnectivitySyncService.shared.refreshLatestSnapshot()
        }
    }
}

private struct RecoveryPlanActionPresentation: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let symbol: String
    let isMain: Bool
}

private struct RecoveryPlanActionStateStyle {
    let state: DailyRecoveryActionState

    var title: String {
        switch state {
        case .pending: return "待处理"
        case .completed: return "已完成"
        case .snoozed: return "稍后"
        case .skipped: return "已跳过"
        case .notApplicable: return "不适用"
        }
    }

    var tint: Color {
        switch state {
        case .pending: return Theme.Colors.mintGreen
        case .completed: return Color(hex: "2F9D68")
        case .snoozed: return Color(hex: "4C7DFF")
        case .skipped: return Color(hex: "7C879B")
        case .notApplicable: return Color(hex: "8B6F9E")
        }
    }

    var statusSymbol: String {
        switch state {
        case .pending: return "circle"
        case .completed: return "checkmark"
        case .snoozed: return "clock"
        case .skipped: return "forward.end"
        case .notApplicable: return "nosign"
        }
    }

    func symbol(for action: RecoveryPlanActionPresentation) -> String {
        switch state {
        case .pending: return action.symbol
        case .completed: return "checkmark.circle.fill"
        case .snoozed: return "clock.fill"
        case .skipped: return "forward.end.fill"
        case .notApplicable: return "nosign"
        }
    }
}
