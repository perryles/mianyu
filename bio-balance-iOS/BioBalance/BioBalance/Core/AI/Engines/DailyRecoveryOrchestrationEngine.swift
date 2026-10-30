import Foundation

/// 汇总恢复脚本和候选建议，并按优先级生成当天行动编排。
struct DailyRecoveryOrchestrationEngine {
    func makePlan(
        recoveryPlan: RecoveryScriptPlan,
        habitSuggestions: [String] = [],
        challengeSuggestions: [String] = [],
        goalSuggestions: [String] = [],
        suppressedSuggestionCategories: Set<String> = [],
        now: Date = Date()
    ) -> DailyRecoveryOrchestrationPlan {
        let candidates = recoveryPlan.immediateActions + habitSuggestions + challengeSuggestions + goalSuggestions
        let eligibleCandidates = candidates.filter {
            !suppressedSuggestionCategories.contains(DailyRecoverySuggestionClassifier.category(for: $0))
        }
        let normalized = deduplicated(eligibleCandidates)
        let resolved = resolveConflicts(normalized, band: recoveryPlan.readinessBand)
        let supporting = Array(resolved.accepted.prefix(2))
        let overflow = Array((Array(resolved.accepted.dropFirst(2)) + resolved.deferred).prefix(6))

        return DailyRecoveryOrchestrationPlan(
            date: Calendar.current.startOfDay(for: now),
            mainGoal: recoveryPlan.recoveryFocus,
            mainGoalDetail: recoveryPlan.headline,
            supportingActions: supporting,
            deferredSuggestions: overflow,
            readinessBand: recoveryPlan.readinessBand,
            reason: recoveryPlan.keyReasons.first ?? recoveryPlan.headline,
            generatedAt: now
        )
    }

    private func deduplicated(_ suggestions: [String]) -> [String] {
        var seen: Set<String> = []
        return suggestions.compactMap { suggestion in
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = DailyRecoverySuggestionClassifier.category(for: trimmed)
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func resolveConflicts(_ suggestions: [String], band: RecoveryReadinessBand) -> (accepted: [String], deferred: [String]) {
        var accepted: [String] = []
        var deferred: [String] = []
        let protectsRecovery = band == .protect || band == .recover

        for suggestion in suggestions {
            if protectsRecovery && isHighLoadSuggestion(suggestion) {
                deferred.append(suggestion)
            } else {
                accepted.append(suggestion)
            }
        }
        return (accepted, deferred)
    }

    private func isHighLoadSuggestion(_ text: String) -> Bool {
        ["加练", "高强度", "提高强度", "拉满", "硬冲", "加码"].contains { text.contains($0) }
    }
}

