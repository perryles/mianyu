/// MedicationHealthKitService — iOS 26+ HealthKit Medications API 桥接层
/// 负责只读查询系统健康 App 中的药物与剂量事件。
import Foundation
import HealthKit

// MARK: - 领域模型（与 HealthKit 类型解耦）

/// 从 HealthKit 获取的用户药物信息
struct HealthKitMedication: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let aliases: [String]
    let dosageForm: String?
    let scheduleStatus: ScheduleStatus
    let concept: MedicationConceptInfo?

    enum ScheduleStatus: String, Sendable {
        case active
        case paused
        case completed
        case unknown
    }
}

/// 药物概念元数据（标识符、剂型、RxNorm 编码）
struct MedicationConceptInfo: Hashable, Sendable {
    let identifier: String?
    let dosageForm: String?
    let rxNormCode: String?
}

/// 用药剂量事件状态
enum MedicationDoseStatus: String, CaseIterable, Sendable {
    case taken
    case skipped
    case deferred

    var localizedTitle: String {
        switch self {
        case .taken: return "已服用"
        case .skipped: return "已跳过"
        case .deferred: return "已延后"
        }
    }
}

/// 从 HealthKit 获取的用药剂量事件
struct HealthKitMedicationDoseEvent: Identifiable, Hashable, Sendable {
    let id: String
    let medicationName: String
    let status: MedicationDoseStatus
    let date: Date
    let dosageDescription: String?
}

/// 同步结果
struct MedicationHealthKitSyncResult: Sendable {
    let writtenCount: Int
    let skippedCount: Int
    let errors: [String]
}

// MARK: - Service

@available(iOS 26.0, *)
final class MedicationHealthKitService: Sendable {

    static let shared = MedicationHealthKitService()

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HealthKitManager.shared.healthStore) {
        self.healthStore = healthStore
    }

    // MARK: - 查询用户药物列表

    /// 从 HealthKit 查询用户已添加的所有药物
    func fetchUserMedications() async throws -> [HealthKitMedication] {
        let descriptor = HKUserAnnotatedMedicationQueryDescriptor(
            predicate: nil
        )
        let results = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "medication.list",
            status: results.isEmpty ? .noData : .dataAvailable
        )
        return results.map { medication in
            let concept = medication.medication
            let displayName = medication.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
            return HealthKitMedication(
                id: String(describing: concept.identifier),
                name: displayName?.isEmpty == false ? displayName! : concept.displayText,
                aliases: displayName?.isEmpty == false && displayName != concept.displayText
                    ? [concept.displayText]
                    : [],
                dosageForm: concept.generalForm.rawValue,
                scheduleStatus: medication.isArchived ? .completed : .active,
                concept: MedicationConceptInfo(
                    identifier: String(describing: concept.identifier),
                    dosageForm: concept.generalForm.rawValue,
                    rxNormCode: concept.relatedCodings.first(where: {
                        $0.system.localizedCaseInsensitiveContains("rxnorm")
                    })?.code
                )
            )
        }
    }

    // MARK: - 查询用药剂量事件

    /// 查询指定日期范围内的用药事件
    func fetchDoseEvents(from startDate: Date, to endDate: Date) async throws -> [HealthKitMedicationDoseEvent] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        let sampleType: HKSampleType = HKObjectType.medicationDoseEventType()
        let sort = SortDescriptor(\HKSample.startDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: sampleType, predicate: predicate)],
            sortDescriptors: [sort],
            limit: 200
        )
        let samples = try await descriptor.result(for: healthStore)
        logHealthKitRead(
            metric: "medication.intakeSamples",
            status: samples.isEmpty ? .noData : .dataAvailable
        )
        let medications = (try? await fetchUserMedications()) ?? []

        return samples.compactMap { sample -> HealthKitMedicationDoseEvent? in
            guard let doseEvent = sample as? HKMedicationDoseEvent else { return nil }
            let conceptID = String(describing: doseEvent.medicationConceptIdentifier)
            let medicationName = medications.first(where: { $0.id == conceptID })?.name ?? "健康 App 药物"
            let dosageDescription = doseEvent.doseQuantity.map {
                "\($0.formatted()) \(doseEvent.unit.unitString)"
            }
            return HealthKitMedicationDoseEvent(
                id: doseEvent.uuid.uuidString,
                medicationName: medicationName,
                status: mapDoseStatus(doseEvent.logStatus),
                date: doseEvent.startDate,
                dosageDescription: dosageDescription
            )
        }
    }

    // MARK: - 写入用药事件

    /// 将 Mianyu 的 MedicationEntry 同步为 HealthKit 用药事件
    func syncEntriesToHealthKit(_ entries: [MedicationEntry]) async -> MedicationHealthKitSyncResult {
        // iOS 26/27 SDK 的 HKMedicationDoseEvent 只有只读属性且 init/new 均不可用。
        // 保留此接口让现有 UI 能明确展示能力边界，绝不伪造“写入成功”。
        return MedicationHealthKitSyncResult(
            writtenCount: 0,
            skippedCount: entries.count,
            errors: entries.isEmpty ? [] : ["系统健康 App 暂未向第三方应用开放用药事件写入"]
        )
    }

    // MARK: - 药物名称匹配

    /// 在 HealthKit 药物列表中查找与 Mianyu 药物名称最匹配的项
    func findMatchingMedication(name: String, in medications: [HealthKitMedication]) -> HealthKitMedication? {
        // 精确匹配
        if let exact = medications.first(where: { $0.name == name }) {
            return exact
        }
        // 包含匹配
        if let contains = medications.first(where: {
            $0.name.localizedCaseInsensitiveContains(name) ||
            name.localizedCaseInsensitiveContains($0.name)
        }) {
            return contains
        }
        // 别名匹配
        return medications.first { med in
            med.aliases.contains { alias in
                alias.localizedCaseInsensitiveContains(name) ||
                name.localizedCaseInsensitiveContains(alias)
            }
        }
    }

    // MARK: - 生成症状关联摘要

    /// 对比 HealthKit 用药事件和 Mianyu 症状记录，生成时间关联摘要
    func correlationSummary(
        doseEvents: [HealthKitMedicationDoseEvent],
        symptomDate: Date,
        windowHours: Int = 24
    ) -> MedicationSymptomCorrelation {
        let windowStart = symptomDate.addingTimeInterval(-Double(windowHours) * 3600)
        let relatedEvents = doseEvents.filter { event in
            event.date >= windowStart && event.date <= symptomDate && event.status == .taken
        }

        let uniqueMedications = Set(relatedEvents.map(\.medicationName))
        return MedicationSymptomCorrelation(
            symptomDate: symptomDate,
            windowHours: windowHours,
            relatedDoseEvents: relatedEvents,
            uniqueMedicationCount: uniqueMedications.count,
            medicationNames: Array(uniqueMedications.prefix(5))
        )
    }

    // MARK: - 私有辅助方法

    private func mapDoseStatus(_ status: HKMedicationDoseEvent.LogStatus) -> MedicationDoseStatus {
        switch status {
        case .taken: return .taken
        case .skipped: return .skipped
        case .snoozed, .notInteracted, .notificationNotSent, .notLogged:
            return .deferred
        @unknown default: return .deferred
        }
    }
}

// MARK: - 关联分析结果

struct MedicationSymptomCorrelation: Sendable {
    let symptomDate: Date
    let windowHours: Int
    let relatedDoseEvents: [HealthKitMedicationDoseEvent]
    let uniqueMedicationCount: Int
    let medicationNames: [String]

    var isEmpty: Bool { relatedDoseEvents.isEmpty }

    var summaryText: String {
        guard !isEmpty else {
            return String(localized: "症状发生前 \(windowHours) 小时内，健康 App 没有用药记录。")
        }
        let names = medicationNames.prefix(3).joined(separator: "、")
        return String(localized: "症状发生前 \(windowHours) 小时内，健康 App 记录了 \(relatedDoseEvents.count) 次用药（\(names)）。仅表示时间重叠，不代表因果关系。")
    }
}
