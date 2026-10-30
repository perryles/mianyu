import CloudKit
import Foundation

nonisolated struct PrescriptionCloudRecordPayload: Codable, Hashable, Sendable {
    let id: String
    let medications: [PrescriptionMedicationCandidate]
    let conditions: [PrescriptionConditionCandidate]
    let documentDate: Date?
    let institution: String?
    let chiefComplaint: String?
    let medicalHistory: String?
    let importedAt: Date
    let updatedAt: Date

    init(record: MedicationPrescriptionRecord) {
        id = String(record.id.prefix(128))
        medications = Array(record.medications.compactMap(Self.sanitizedMedication).prefix(20))
        conditions = Array(record.conditions.compactMap(Self.sanitizedCondition).prefix(20))
        documentDate = record.documentDate
        institution = Self.bounded(record.institution, limit: 100)
        chiefComplaint = Self.bounded(record.chiefComplaint, limit: 500)
        medicalHistory = Self.bounded(record.medicalHistory, limit: 1000)
        importedAt = record.importedAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> MedicationPrescriptionRecord? {
        let sanitizedMedications = Array(medications.compactMap(Self.sanitizedMedication).prefix(20))
        let sanitizedConditions = Array(conditions.compactMap(Self.sanitizedCondition).prefix(20))
        guard !id.isEmpty, !sanitizedMedications.isEmpty || !sanitizedConditions.isEmpty else { return nil }
        return MedicationPrescriptionRecord(
            id: id,
            medications: sanitizedMedications,
            conditions: sanitizedConditions,
            chiefComplaint: Self.bounded(chiefComplaint, limit: 500),
            medicalHistory: Self.bounded(medicalHistory, limit: 1000),
            documentDate: documentDate,
            institution: Self.bounded(institution, limit: 100),
            importedAt: importedAt,
            updatedAt: updatedAt,
            recognitionProviderID: nil,
            recognitionModel: nil,
            recognitionConfidence: nil
        )
    }

    private static func sanitizedMedication(_ value: PrescriptionMedicationCandidate) -> PrescriptionMedicationCandidate? {
        guard let name = bounded(value.name, limit: 80) else { return nil }
        let amount = value.amount.flatMap { (0...100_000).contains($0) ? $0 : nil }
        return PrescriptionMedicationCandidate(
            id: String(value.id.prefix(128)),
            name: name,
            amount: amount,
            unit: bounded(value.unit, limit: 20),
            instructions: bounded(value.instructions, limit: 160),
            purpose: bounded(value.purpose, limit: 120)
        )
    }

    private static func sanitizedCondition(_ value: PrescriptionConditionCandidate) -> PrescriptionConditionCandidate? {
        guard let name = bounded(value.name, limit: 80) else { return nil }
        return PrescriptionConditionCandidate(
            id: String(value.id.prefix(128)),
            name: name,
            kind: value.kind
        )
    }

    private static func bounded(_ value: String?, limit: Int) -> String? {
        let redacted = PrescriptionTextRedactor.redact(value ?? "")
        let normalized = redacted
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(limit))
    }
}

nonisolated struct MedicationHealthCloudSnapshot: Sendable {
    let prescriptions: [MedicationPrescriptionRecord]
}

/// 同步人工确认后的最小处方快照。原图、OCR 全文、患者身份和 AI 来源元数据永不进入 payload。
final class MedicationHealthCloudRepository {
    static let shared = MedicationHealthCloudRepository()

    private enum Schema {
        static let zoneName = CloudKitDataPolicy.Zone.medicationHealth
        static let recordType = CloudKitDataPolicy.RecordType.medicationPrescription
        static let payload = "payload"
        static let importedAt = "importedAt"
        static let createdAt = CloudKitDataPolicy.MetadataField.createdAt
        static let updatedAt = CloudKitDataPolicy.MetadataField.updatedAt
        static let schemaVersion = CloudKitDataPolicy.MetadataField.schemaVersion
        static let currentSchemaVersion: Int64 = 1
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let client: CloudKitClientProtocol
    private let executor: CloudKitOperationExecutor
    private let preferences: UserDefaults
    private let zoneID: CKRecordZone.ID
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        container: CKContainer = CloudKitDataPolicy.makeContainer(),
        client: CloudKitClientProtocol = CloudKitClient(),
        executor: CloudKitOperationExecutor = CloudKitOperationExecutor(),
        preferences: UserDefaults = .standard
    ) {
        CloudKitDataPolicy.registerDefaultPreferences(in: preferences)
        self.container = container
        self.database = container.privateCloudDatabase
        self.client = client
        self.executor = executor
        self.preferences = preferences
        self.zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    func synchronize(localRecords: [MedicationPrescriptionRecord]) async throws -> MedicationHealthCloudSnapshot {
        guard preferences.bool(forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled) else {
            return MedicationHealthCloudSnapshot(prescriptions: localRecords)
        }

        let accountIdentifier = try await preparePrivateDatabase()
        let remoteRecords = try await fetchAllRecords()
        try await verifyCurrentAccount(accountIdentifier)
        var existingByName = Dictionary(
            remoteRecords.map { ($0.recordID.recordName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let merged = merge(local: localRecords, remote: remoteRecords.compactMap(decode))
        let recordsToSave = try merged.compactMap { value in
            try cloudRecord(for: value, existing: existingByName.removeValue(forKey: recordName(for: value)))
        }

        for start in stride(from: 0, to: recordsToSave.count, by: 200) {
            let end = min(start + 200, recordsToSave.count)
            let batch = Array(recordsToSave[start..<end])
            _ = try await executor.run(
                context: CloudKitLoggerContext(
                    operation: "sync-medication-health",
                    database: .private,
                    zoneID: zoneID.zoneName
                )
            ) { [container, client, database] in
                let current = try await client.fetchUserRecordID(container: container)
                guard current.recordName == accountIdentifier else {
                    throw CloudKitDomainError.iCloudUnavailable
                }
                return try await client.modify(
                    recordsToSave: batch,
                    recordIDsToDelete: [],
                    savePolicy: .changedKeys,
                    in: database
                )
            }
        }

        try await verifyCurrentAccount(accountIdentifier)
        return MedicationHealthCloudSnapshot(
            prescriptions: Array(merged.sorted { $0.importedAt > $1.importedAt }.prefix(80))
        )
    }

    func currentAccountIdentifier() async throws -> String {
        let status = try await executor.run(
            context: CloudKitLoggerContext(operation: "medication-health-account-status", database: .private)
        ) { [container, client] in
            try await client.accountStatus(container: container)
        }
        guard status == .available else { throw CloudKitDomainError.iCloudUnavailable }
        return try await executor.run(
            context: CloudKitLoggerContext(operation: "medication-health-account-identity", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
    }

    private func preparePrivateDatabase() async throws -> String {
        let accountIdentifier = try await currentAccountIdentifier()
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await executor.run(
            context: CloudKitLoggerContext(
                operation: "prepare-medication-health-zone",
                database: .private,
                zoneID: zoneID.zoneName
            )
        ) { [container, client, database] in
            let current = try await client.fetchUserRecordID(container: container)
            guard current.recordName == accountIdentifier else {
                throw CloudKitDomainError.iCloudUnavailable
            }
            return try await client.save(zone: zone, in: database)
        }
        return accountIdentifier
    }

    private func verifyCurrentAccount(_ accountIdentifier: String) async throws {
        let current = try await executor.run(
            context: CloudKitLoggerContext(operation: "verify-medication-health-account", database: .private)
        ) { [container, client] in
            try await client.fetchUserRecordID(container: container).recordName
        }
        guard current == accountIdentifier else { throw CloudKitDomainError.iCloudUnavailable }
    }

    private func fetchAllRecords() async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        do {
            repeat {
                let currentCursor = cursor
                let page = try await executor.run(
                    context: CloudKitLoggerContext(
                        operation: "fetch-medication-health",
                        database: .private,
                        zoneID: zoneID.zoneName
                    )
                ) { [client, database, zoneID] in
                    try await client.runQuery(
                        query: currentCursor == nil
                            ? CKQuery(recordType: Schema.recordType, predicate: NSPredicate(value: true))
                            : nil,
                        cursor: currentCursor,
                        zoneID: zoneID,
                        in: database
                    )
                }
                records.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil
            return records
        } catch CloudKitDomainError.unknownItem {
            return []
        }
    }

    private func cloudRecord(
        for value: MedicationPrescriptionRecord,
        existing: CKRecord?
    ) throws -> CKRecord? {
        let payload = try encoder.encode(PrescriptionCloudRecordPayload(record: value))
        if let existing, existing[Schema.payload] as? Data == payload { return nil }
        let record = existing ?? CKRecord(
            recordType: Schema.recordType,
            recordID: CKRecord.ID(recordName: recordName(for: value), zoneID: zoneID)
        )
        record[Schema.payload] = payload as CKRecordValue
        record[Schema.importedAt] = value.importedAt as CKRecordValue
        if record[Schema.createdAt] == nil {
            record[Schema.createdAt] = value.importedAt as CKRecordValue
        }
        record[Schema.updatedAt] = value.updatedAt as CKRecordValue
        record[Schema.schemaVersion] = Schema.currentSchemaVersion as CKRecordValue
        return record
    }

    private func decode(_ record: CKRecord) -> MedicationPrescriptionRecord? {
        guard let payload = record[Schema.payload] as? Data,
              let decoded = try? decoder.decode(PrescriptionCloudRecordPayload.self, from: payload) else {
            return nil
        }
        return decoded.makeRecord()
    }

    private func recordName(for value: MedicationPrescriptionRecord) -> String {
        "prescription.\(value.id)"
    }

    private func merge(
        local: [MedicationPrescriptionRecord],
        remote: [MedicationPrescriptionRecord]
    ) -> [MedicationPrescriptionRecord] {
        var merged = Dictionary(
            remote.map { ($0.id, $0) },
            uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second }
        )
        for value in local {
            guard let existing = merged[value.id] else {
                merged[value.id] = value
                continue
            }
            if value.updatedAt >= existing.updatedAt {
                merged[value.id] = value
            }
        }
        return Array(merged.values)
    }
}

/// 页面与 Store 共用的轻量同步协调器；CloudKit 失败不会影响本地保存。
final class MedicationHealthCloudSyncCoordinator {
    static let shared = MedicationHealthCloudSyncCoordinator()

    private let defaults: UserDefaults
    private let repository: MedicationHealthCloudRepository
    private let store: MedicationPrescriptionStore
    private let accountBindingKey = CloudKitDataPolicy.AccountBindingKey.medicationHealth
    private var isSynchronizing = false
    private var needsAnotherPass = false

    init(
        defaults: UserDefaults = .standard,
        repository: MedicationHealthCloudRepository = .shared,
        store: MedicationPrescriptionStore = .shared
    ) {
        CloudKitDataPolicy.registerDefaultPreferences(in: defaults)
        self.defaults = defaults
        self.repository = repository
        self.store = store
    }

    @discardableResult
    func synchronize() async -> Bool {
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled) else {
            return false
        }
        guard !isSynchronizing else {
            needsAnotherPass = true
            return false
        }

        isSynchronizing = true
        defer {
            isSynchronizing = false
            if needsAnotherPass {
                needsAnotherPass = false
                schedule()
            }
        }

        do {
            let currentAccount = try await repository.currentAccountIdentifier()
            if let previousAccount = defaults.string(forKey: accountBindingKey),
               previousAccount != currentAccount {
                defaults.set(false, forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled)
                defaults.removeObject(forKey: accountBindingKey)
                return false
            }

            let snapshot = try await repository.synchronize(localRecords: store.allRecords())
            store.mergeCloudRecords(snapshot.prescriptions)
            defaults.set(currentAccount, forKey: accountBindingKey)
            return true
        } catch {
            return false
        }
    }

    func schedule() {
        guard defaults.bool(forKey: CloudKitDataPolicy.PreferenceKey.medicationHealthSyncEnabled) else { return }
        Task { @MainActor in
            _ = await synchronize()
        }
    }
}
