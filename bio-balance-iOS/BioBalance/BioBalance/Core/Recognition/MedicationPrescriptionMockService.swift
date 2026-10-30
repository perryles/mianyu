import Foundation

nonisolated protocol MedicationPrescriptionMockProviding: Sendable {
    func recognize() async throws -> [RecognizedMedication]
}

nonisolated struct MedicationPrescriptionMockService: MedicationPrescriptionMockProviding {
    func recognize() async throws -> [RecognizedMedication] {
        try await Task.sleep(for: .milliseconds(700))
        return MedicationSampleData.recognized
    }
}
