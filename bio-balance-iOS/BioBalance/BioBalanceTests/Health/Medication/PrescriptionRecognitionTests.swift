import Foundation
import XCTest
@testable import BioBalance

nonisolated final class PrescriptionRecognitionTests: XCTestCase {
    @MainActor func testCancellingPrescriptionEditRestoresPersistedDraft() {
        let record = MedicationPrescriptionRecord(
            id: "rx-edit",
            medications: [PrescriptionMedicationCandidate(name: "布洛芬", amount: 200, unit: "mg")],
            conditions: [PrescriptionConditionCandidate(name: "头痛", kind: .symptom)],
            chiefComplaint: "头痛两小时",
            medicalHistory: "无",
            documentDate: Date(timeIntervalSince1970: 100),
            institution: "测试医院"
        )
        var draft = PrescriptionEditDraft(record: record)
        draft.medications[0].name = "未保存的药名"
        draft.conditions[0].name = "未保存的症状"
        draft.chiefComplaint = "未保存的主诉"
        draft.institution = "未保存的机构"

        draft.discardChanges(restoring: record)

        XCTAssertEqual(draft.medications.map(\.name), ["布洛芬"])
        XCTAssertEqual(draft.conditions.map(\.name), ["头痛"])
        XCTAssertEqual(draft.chiefComplaint, "头痛两小时")
        XCTAssertEqual(draft.medicalHistory, "无")
        XCTAssertEqual(draft.institution, "测试医院")
        XCTAssertTrue(draft.includesDocumentDate)
        XCTAssertEqual(draft.documentDate, Date(timeIntervalSince1970: 100))
    }

    @MainActor func testMedicationCloudSyncDefaultsOnWithoutOverridingSavedChoice() throws {
        let suiteName = "PrescriptionRecognitionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled))

        defaults.set(false, forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled)
        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled))
    }

    @MainActor func testCloudAIRedactionDropsCommonIdentityFieldsAndKeepsMedicalFacts() {
        let text = """
        姓名：张三
        手机号：13800138000
        身份证：110101199001011234
        临床诊断：急性咽炎
        阿莫西林胶囊 0.5 g
        """

        let redacted = PrescriptionTextRedactor.redact(text)

        XCTAssertFalse(redacted.contains("张三"))
        XCTAssertFalse(redacted.contains("13800138000"))
        XCTAssertFalse(redacted.contains("110101199001011234"))
        XCTAssertTrue(redacted.contains("急性咽炎"))
        XCTAssertTrue(redacted.contains("阿莫西林胶囊"))
    }

    @MainActor func testStructuredDecoderExtractsMedicationAndConditionWithoutPatientIdentity() throws {
        let response = #"""
        {
          "status": "recognized",
          "patientName": "不应持久化",
          "medications": [
            {"name": "阿莫西林胶囊", "amount": 0.5, "unit": "g", "instructions": "每日三次", "purpose": "抗感染"}
          ],
          "conditions": [
            {"name": "急性咽炎", "type": "diagnosis"},
            {"name": "咽痛", "type": "symptom"}
          ],
          "documentDate": "2026-07-23",
          "institution": "测试医院",
          "confidence": 0.93,
          "warnings": []
        }
        """#

        let result = try PrescriptionStructuredResponseDecoder.decode(
            response,
            ocrExcerpt: "处方文字",
            providerID: .qwen,
            model: "test-model"
        )

        XCTAssertEqual(result.medications.count, 1)
        XCTAssertEqual(result.medications.first?.name, "阿莫西林胶囊")
        XCTAssertEqual(result.medications.first?.amount, 0.5)
        XCTAssertEqual(result.conditions.map(\.kind), [.diagnosis, .symptom])
        XCTAssertEqual(result.providerID, .qwen)
        XCTAssertEqual(result.providerModel, "test-model")
        XCTAssertFalse(result.descriptionForTesting.contains("不应持久化"))
    }

    @MainActor func testStructuredDecoderAcceptsMarkdownWrappedJSON() throws {
        let response = """
        ```json
        {"status":"needs_review","medications":[{"name":"布洛芬","amount":"200 mg","unit":"mg"}],"conditions":[],"confidence":0.7}
        ```
        """

        let result = try PrescriptionStructuredResponseDecoder.decode(
            response,
            ocrExcerpt: "布洛芬 200 mg",
            providerID: .qwen,
            model: "test-model"
        )

        XCTAssertEqual(result.medications.first?.amount, 200)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    @MainActor func testStructuredDecoderRejectsEmptyMedicalPayload() {
        XCTAssertThrowsError(
            try PrescriptionStructuredResponseDecoder.decode(
                #"{"status":"recognized","medications":[],"conditions":[]}"#,
                ocrExcerpt: "",
                providerID: .qwen,
                model: "test-model"
            )
        )
    }

    @MainActor func testCloudPayloadOmitsOCRAndAIMetadata() throws {
        let record = MedicationPrescriptionRecord(
            id: "rx-1",
            medications: [PrescriptionMedicationCandidate(name: "布洛芬", amount: 200, unit: "mg")],
            conditions: [
                PrescriptionConditionCandidate(name: "头痛", kind: .symptom),
                PrescriptionConditionCandidate(name: "姓名：不应上传", kind: .diagnosis)
            ],
            importedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            recognitionProviderID: .qwen,
            recognitionModel: "sensitive-model-name",
            recognitionConfidence: 0.9
        )

        let data = try JSONEncoder().encode(PrescriptionCloudRecordPayload(record: record))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let restored = try JSONDecoder().decode(PrescriptionCloudRecordPayload.self, from: data).makeRecord()

        XCTAssertFalse(json.contains("recognitionProviderID"))
        XCTAssertFalse(json.contains("sensitive-model-name"))
        XCTAssertFalse(json.contains("不应上传"))
        XCTAssertNil(restored?.recognitionProviderID)
        XCTAssertNil(restored?.recognitionModel)
        XCTAssertEqual(restored?.medications.first?.name, "布洛芬")
        XCTAssertEqual(restored?.conditions.first?.name, "头痛")
    }
}

private extension PrescriptionRecognitionResult {
    var descriptionForTesting: String {
        "\(medications)|\(conditions)|\(institution ?? "")|\(ocrExcerpt)|\(warnings)"
    }
}
