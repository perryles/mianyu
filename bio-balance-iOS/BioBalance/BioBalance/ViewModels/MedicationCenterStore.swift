import Foundation
import Observation

@MainActor
@Observable
final class MedicationCenterStore {
    var schedules: [MedicationScheduleItem]
    var recognitionState: PrescriptionRecognitionState = .idle
    var transientMessage: String?

    private let recognitionService: any MedicationPrescriptionMockProviding

    init(schedules: [MedicationScheduleItem] = MedicationSampleData.schedules, recognitionService: any MedicationPrescriptionMockProviding = MedicationPrescriptionMockService()) {
        self.schedules = schedules
        self.recognitionService = recognitionService
    }

    var nextDose: MedicationScheduleItem? {
        schedules.first { $0.status == .upcoming } ?? schedules.first { $0.status == .pending }
    }

    var completedCount: Int { schedules.filter { $0.status == .taken }.count }

    func updateStatus(id: String, status: MedicationCenterDoseStatus) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].status = status
    }

    func recognizePrescription() async {
        recognitionState = .recognizing
        do { recognitionState = .result(try await recognitionService.recognize()) }
        catch { recognitionState = .failed(String(localized: "没有识别到可用药品，请换一张清晰的处方照片。")) }
    }

    func resetRecognition() { recognitionState = .idle }

    func addRecognizedToPlan(_ items: [RecognizedMedication]) {
        for (index, item) in items.enumerated() where !schedules.contains(where: { $0.medicationID == item.medicationID }) {
            schedules.append(.init(time: String(format: "%02d:00", min(23, 9 + index * 3)), medicationID: item.medicationID, name: item.name, dose: item.specification, timing: item.frequency, status: .pending))
        }
    }
}
