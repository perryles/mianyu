import Foundation
import SwiftData

nonisolated struct MedicationPrescriptionRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var medications: [PrescriptionMedicationCandidate]
    var conditions: [PrescriptionConditionCandidate]
    var chiefComplaint: String?
    var medicalHistory: String?
    var documentDate: Date?
    var institution: String?
    var importedAt: Date
    var updatedAt: Date
    var recognitionProviderID: AIProviderID?
    var recognitionModel: String?
    var recognitionConfidence: Double?

    init(
        id: String = UUID().uuidString,
        medications: [PrescriptionMedicationCandidate],
        conditions: [PrescriptionConditionCandidate],
        chiefComplaint: String? = nil,
        medicalHistory: String? = nil,
        documentDate: Date? = nil,
        institution: String? = nil,
        importedAt: Date = Date(),
        updatedAt: Date = Date(),
        recognitionProviderID: AIProviderID? = nil,
        recognitionModel: String? = nil,
        recognitionConfidence: Double? = nil
    ) {
        self.id = id
        self.medications = medications
        self.conditions = conditions
        self.chiefComplaint = chiefComplaint
        self.medicalHistory = medicalHistory
        self.documentDate = documentDate
        self.institution = institution
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.recognitionProviderID = recognitionProviderID
        self.recognitionModel = recognitionModel
        self.recognitionConfidence = recognitionConfidence
    }

    var summaryTitle: String {
        let conditionNames = conditions.prefix(2).map(\.name)
        if !conditionNames.isEmpty { return conditionNames.joined(separator: "、") }
        let medicationNames = medications.prefix(2).map(\.name)
        return medicationNames.isEmpty ? "处方资料" : medicationNames.joined(separator: "、")
    }

    var hasChiefComplaintOrHistory: Bool {
        let hasComplaint = chiefComplaint.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let hasHistory = medicalHistory.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        return hasComplaint || hasHistory
    }

    var detailSummary: String {
        var parts: [String] = []
        if !medications.isEmpty { parts.append("\(medications.count) 种药物") }
        if !conditions.isEmpty { parts.append("\(conditions.count) 项病症") }
        if hasChiefComplaintOrHistory { parts.append("含病历信息") }
        if let institution, !institution.isEmpty { parts.append(institution) }
        return parts.joined(separator: " · ")
    }
}

extension Notification.Name {
    static let medicationPrescriptionRecordsDidChange = Notification.Name("medicationPrescriptionRecordsDidChange")
}

final class MedicationPrescriptionStore {
    static let shared = MedicationPrescriptionStore()

    private struct Payload: Codable {
        var records: [MedicationPrescriptionRecord]
    }

    private let defaults: UserDefaults
    private let records: SwiftDataRecordStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageKey = "medicationPrescriptionStore.v1"
    private let domain = "medication-prescription"
    private let kind = "record"

    init(
        defaults: UserDefaults = .standard,
        container: ModelContainer = MianyuModelContainer.shared
    ) {
        self.defaults = defaults
        records = SwiftDataRecordStore(container: container)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        migrateLegacyDataIfNeeded()
    }

    func allRecords() -> [MedicationPrescriptionRecord] {
        load().records.sorted { $0.importedAt > $1.importedAt }
    }

    func record(with id: String) -> MedicationPrescriptionRecord? {
        load().records.first { $0.id == id }
    }

    func save(_ record: MedicationPrescriptionRecord) {
        var payload = load()
        var normalized = record
        normalized.updatedAt = Date()
        normalized.medications = Array(normalized.medications.prefix(20))
        normalized.conditions = Array(normalized.conditions.prefix(20))
        if let index = payload.records.firstIndex(where: { $0.id == normalized.id }) {
            payload.records[index] = normalized
        } else {
            payload.records.append(normalized)
        }
        persist(Payload(records: Array(payload.records.sorted { $0.importedAt > $1.importedAt }.prefix(80))))
        MedicationHealthCloudSyncCoordinator.shared.schedule()
    }

    func delete(_ id: String) {
        var payload = load()
        payload.records.removeAll { $0.id == id }
        persist(payload)
    }

    /// 云端 snapshot 已在 Repository 做过白名单解码；再次与同步期间的新本地记录合并，
    /// 避免 actor 重入时用较旧 snapshot 覆盖刚完成的人工确认。
    func mergeCloudRecords(_ cloudRecords: [MedicationPrescriptionRecord]) {
        var merged = Dictionary(
            cloudRecords.map { ($0.id, $0) },
            uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second }
        )
        for local in allRecords() {
            guard let remote = merged[local.id] else {
                merged[local.id] = local
                continue
            }
            if local.updatedAt >= remote.updatedAt {
                merged[local.id] = local
            }
        }
        persist(Payload(records: Array(merged.values.sorted { $0.importedAt > $1.importedAt }.prefix(80))))
    }

    private func load() -> Payload {
        if let rows = records.records(domain: domain, kind: kind) {
            return Payload(records: rows.compactMap { try? decoder.decode(MedicationPrescriptionRecord.self, from: $0.payload) })
        }
        return loadLegacy()
    }

    private func loadLegacy() -> Payload {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return Payload(records: [])
        }
        return payload
    }

    private func persist(_ payload: Payload) {
        let seeds = payload.records.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: kind,
                occurredAt: record.importedAt,
                updatedAt: record.updatedAt,
                payload: data
            )
        }
        guard seeds.count == payload.records.count,
              records.replace(domain: domain, kind: kind, with: seeds) else { return }
        NotificationCenter.default.post(name: .medicationPrescriptionRecordsDidChange, object: self)
    }

    private func migrateLegacyDataIfNeeded() {
        let migrationID = "medicationPrescriptionStore.v1-to-swiftdata.v1"
        if records.isMigrationComplete(migrationID) {
            defaults.removeObject(forKey: storageKey)
            return
        }
        let legacyData = defaults.data(forKey: storageKey)
        let legacyRecords: [MedicationPrescriptionRecord]
        if let legacyData {
            guard let payload = try? decoder.decode(Payload.self, from: legacyData) else { return }
            legacyRecords = payload.records
        } else {
            legacyRecords = []
        }
        let seeds = legacyRecords.compactMap { record -> LocalDataRecordSeed? in
            guard let data = try? encoder.encode(record) else { return nil }
            return LocalDataRecordSeed(
                domain: domain,
                recordID: record.id,
                kind: kind,
                occurredAt: record.importedAt,
                updatedAt: record.updatedAt,
                payload: data
            )
        }
        guard seeds.count == legacyRecords.count, records.migrate(migrationID, seeds: seeds) else { return }
        defaults.removeObject(forKey: storageKey)
    }
}
