import Foundation

nonisolated enum MedicationCenterDoseStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case taken, upcoming, pending, missed, skipped

    var title: String {
        switch self {
        case .taken: return String(localized: "已服用")
        case .upcoming: return String(localized: "即将到时")
        case .pending: return String(localized: "待服用")
        case .missed: return String(localized: "漏服")
        case .skipped: return String(localized: "已跳过")
        }
    }
}

nonisolated struct MedicationScheduleItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var time: String
    var medicationID: String
    var name: String
    var dose: String
    var timing: String
    var status: MedicationCenterDoseStatus

    init(id: String = UUID().uuidString, time: String, medicationID: String, name: String, dose: String, timing: String, status: MedicationCenterDoseStatus) {
        self.id = id
        self.time = time
        self.medicationID = medicationID
        self.name = name
        self.dose = dose
        self.timing = timing
        self.status = status
    }
}

nonisolated struct MedicationInfo: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let genericName: String
    let dosageForm: String
    let specification: String
    let manufacturer: String
    let indications: String
    let usage: String
    let precautions: String
    let adverseReactions: String
    let contraindications: String
    let specialPopulation: String
}

nonisolated struct RecognizedMedication: Identifiable, Hashable, Sendable {
    let id: String
    let medicationID: String
    let name: String
    let specification: String
    let frequency: String
}

nonisolated enum PrescriptionRecognitionState: Equatable, Sendable {
    case idle
    case recognizing
    case result([RecognizedMedication])
    case failed(String)
}

/// Editable value state kept independently from a persisted prescription.
/// This remains a small model so cancelling recognition edits can restore the saved facts
/// without bringing back the retired prescription-detail screen.
nonisolated struct PrescriptionEditDraft: Hashable, Sendable {
    var medications: [PrescriptionMedicationCandidate]
    var conditions: [PrescriptionConditionCandidate]
    var chiefComplaint: String
    var medicalHistory: String
    var institution: String
    var includesDocumentDate: Bool
    var documentDate: Date

    init(record: MedicationPrescriptionRecord) {
        medications = record.medications
        conditions = record.conditions
        chiefComplaint = record.chiefComplaint ?? ""
        medicalHistory = record.medicalHistory ?? ""
        institution = record.institution ?? ""
        includesDocumentDate = record.documentDate != nil
        documentDate = record.documentDate ?? Date()
    }

    mutating func discardChanges(restoring record: MedicationPrescriptionRecord) {
        self = PrescriptionEditDraft(record: record)
    }
}

nonisolated enum MedicationRoute: Hashable {
    case plan
    case prescription
    case instruction(String)
    case symptomReview
    case symptomLog
}

nonisolated enum MedicationSymptomReviewLayout {
    static func metricColumnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 1 : 2
    }
}
