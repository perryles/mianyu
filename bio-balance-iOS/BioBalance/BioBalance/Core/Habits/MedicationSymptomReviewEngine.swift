import Foundation

nonisolated struct MedicationSymptomReview: Sendable {
    let medicationEntryCount: Int
    let medicationActiveDays: Int
    let symptomRecordCount: Int
    let symptomActiveDays: Int
    let reactionTrackedCount: Int
    let uncomfortableCount: Int
    let pendingReactionCount: Int
    let overlapCount: Int
    let mostFrequentSymptom: SelfObservationSymptom?
    let requiresMedicalAttention: Bool

    var reactionCoverage: Double? {
        medicationEntryCount == 0 ? nil : Double(reactionTrackedCount) / Double(medicationEntryCount)
    }
}

nonisolated enum MedicationSymptomReviewEngine {
    static func make(
        entries: [MedicationEntry],
        symptomRecords: [SelfObservationRecord],
        referenceDate: Date = Date(),
        days: Int = 14,
        calendar: Calendar = .current
    ) -> MedicationSymptomReview {
        let safeDays = max(1, days)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -(safeDays - 1), to: referenceDay) ?? referenceDay
        let medication = entries.filter { $0.takenAt >= start && $0.takenAt <= referenceDate }
        let symptoms = symptomRecords.filter {
            $0.isSymptomObservation && $0.recordedAt >= start && $0.recordedAt <= referenceDate
        }

        let symptomCounts = symptoms.reduce(into: [SelfObservationSymptom: Int]()) { counts, record in
            record.selectedSymptoms.forEach { counts[$0, default: 0] += 1 }
        }
        let maxSymptomCount = symptomCounts.values.max() ?? 0
        let mostFrequent = maxSymptomCount == 0
            ? nil
            : SelfObservationSymptom.allCases.first { symptomCounts[$0, default: 0] == maxSymptomCount }

        let overlapCount = symptoms.filter { symptom in
            let lowerBound = symptom.recordedAt.addingTimeInterval(-24 * 60 * 60)
            return medication.contains { $0.takenAt >= lowerBound && $0.takenAt <= symptom.recordedAt }
        }.count

        return MedicationSymptomReview(
            medicationEntryCount: medication.count,
            medicationActiveDays: Set(medication.map { calendar.startOfDay(for: $0.takenAt) }).count,
            symptomRecordCount: symptoms.count,
            symptomActiveDays: Set(symptoms.map { calendar.startOfDay(for: $0.recordedAt) }).count,
            reactionTrackedCount: medication.compactMap(\.reactionState).count,
            uncomfortableCount: medication.filter { $0.reactionState == .uncomfortable }.count,
            pendingReactionCount: medication.filter { $0.reactionState == nil }.count,
            overlapCount: overlapCount,
            mostFrequentSymptom: mostFrequent,
            requiresMedicalAttention: symptoms.contains {
                $0.symptomSeverity >= 4 || ($0.selectedSymptoms.contains(.chest) && $0.symptomSeverity >= 3)
            }
        )
    }
}
