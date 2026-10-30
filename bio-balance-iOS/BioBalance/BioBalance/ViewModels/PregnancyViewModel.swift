import Foundation

enum PregnancySyncStatus: Equatable {
    case idle
    case loading
    case saving
    case synced(Date)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .loading, .saving:
            return true
        default:
            return false
        }
    }
}

@MainActor
@Observable
final class PregnancyViewModel {
    private(set) var snapshot: PregnancySnapshot = .empty
    private(set) var syncStatus: PregnancySyncStatus = .idle
    private(set) var hasLoadedSnapshot = false

    private let repository: PregnancyRepositoryProtocol
    private var accountGeneration = 0
    private var activeLoadID: UUID?
    private var activeMutationID: UUID?

    init(repository: PregnancyRepositoryProtocol) {
        self.repository = repository
    }

    convenience init() {
        self.init(repository: PregnancyCloudKitRepository())
    }

    var profile: PregnancyProfile? { snapshot.profile }
    var activeProfile: PregnancyProfile? { snapshot.profile?.isActive == true ? snapshot.profile : nil }
    var hasActivePregnancy: Bool { activeProfile != nil }
    var weights: [PregnancyWeightEntry] { snapshot.weightEntries }
    var fetalMovements: [FetalMovementEntry] { snapshot.fetalMovementEntries }
    var canMutate: Bool { hasLoadedSnapshot && !syncStatus.isBusy }
    var errorMessage: String? {
        guard case .failed(let message) = syncStatus else { return nil }
        return message
    }

    func load() async {
        guard activeLoadID == nil, activeMutationID == nil else { return }
        let loadID = UUID()
        let generation = accountGeneration
        activeLoadID = loadID
        syncStatus = .loading
        defer {
            if activeLoadID == loadID {
                activeLoadID = nil
            }
        }

        do {
            let fetchedSnapshot = try await repository.fetchSnapshot()
            guard isCurrent(loadID: loadID, generation: generation) else { return }
            snapshot = fetchedSnapshot
            hasLoadedSnapshot = true
            syncStatus = .synced(Date())
        } catch {
            guard isCurrent(loadID: loadID, generation: generation) else { return }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
        }
    }

    func handleICloudAccountChange() async {
        accountGeneration += 1
        activeLoadID = nil
        activeMutationID = nil
        snapshot = .empty
        hasLoadedSnapshot = false
        syncStatus = .idle
        await load()
    }

    @discardableResult
    func saveProfile(lastMenstrualPeriod: Date, dueDate: Date) async -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let normalizedLMP = calendar.startOfDay(for: lastMenstrualPeriod)
        let normalizedDueDate = calendar.startOfDay(for: dueDate)
        let earliestLMP = calendar.date(byAdding: .weekOfYear, value: -44, to: today) ?? today
        let earliestDueDate = calendar.date(byAdding: .weekOfYear, value: -4, to: today) ?? today
        let latestDueDate = calendar.date(byAdding: .weekOfYear, value: 44, to: today) ?? today
        guard normalizedLMP >= earliestLMP,
              normalizedLMP <= today,
              normalizedDueDate >= earliestDueDate,
              normalizedDueDate <= latestDueDate,
              normalizedDueDate > normalizedLMP else {
            syncStatus = .failed("请检查日期：末次月经需在最近 44 周内，预产期需晚于末次月经日期。")
            return false
        }
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }

        let now = Date()
        let currentProfile = activeProfile
        let profile = PregnancyProfile(
            id: currentProfile?.id ?? UUID().uuidString,
            dueDate: normalizedDueDate,
            lastMenstrualPeriod: normalizedLMP,
            endedAt: nil,
            createdAt: currentProfile?.createdAt ?? now,
            updatedAt: now
        )

        do {
            let saved = try await repository.saveProfile(profile)
            guard isCurrent(mutation) else { return false }
            let previousPregnancyID = snapshot.profile?.id
            snapshot.profile = saved
            if previousPregnancyID != saved.id {
                snapshot.weightEntries = []
                snapshot.fetalMovementEntries = []
            }
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    @discardableResult
    func addWeight(weightKg: Double, measuredAt: Date) async -> Bool {
        guard let pregnancyID = activeProfile?.id else {
            syncStatus = .failed("请先开始孕期记录。")
            return false
        }
        guard (25...300).contains(weightKg) else {
            syncStatus = .failed("请输入 25 至 300 kg 之间的体重。")
            return false
        }
        guard measuredAt <= Date().addingTimeInterval(60) else {
            syncStatus = .failed("体重测量时间不能晚于现在。")
            return false
        }
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }

        do {
            let saved = try await repository.saveWeightEntry(
                PregnancyWeightEntry(
                    pregnancyID: pregnancyID,
                    measuredAt: measuredAt,
                    weightKg: weightKg
                )
            )
            guard isCurrent(mutation) else { return false }
            snapshot.weightEntries.removeAll { $0.id == saved.id }
            snapshot.weightEntries.append(saved)
            snapshot.weightEntries.sort { $0.measuredAt < $1.measuredAt }
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    @discardableResult
    func deleteWeight(id: String) async -> Bool {
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }
        do {
            try await repository.deleteWeightEntry(id: id)
            guard isCurrent(mutation) else { return false }
            snapshot.weightEntries.removeAll { $0.id == id }
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    @discardableResult
    func addFetalMovement(occurredAt: Date) async -> Bool {
        guard let pregnancyID = activeProfile?.id else {
            syncStatus = .failed("请先开始孕期记录。")
            return false
        }
        guard occurredAt <= Date().addingTimeInterval(60) else {
            syncStatus = .failed("胎动时间不能晚于现在。")
            return false
        }
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }

        do {
            let saved = try await repository.saveFetalMovementEntry(
                FetalMovementEntry(pregnancyID: pregnancyID, occurredAt: occurredAt)
            )
            guard isCurrent(mutation) else { return false }
            snapshot.fetalMovementEntries.removeAll { $0.id == saved.id }
            snapshot.fetalMovementEntries.append(saved)
            snapshot.fetalMovementEntries.sort { $0.occurredAt > $1.occurredAt }
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    @discardableResult
    func deleteFetalMovement(id: String) async -> Bool {
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }
        do {
            try await repository.deleteFetalMovementEntry(id: id)
            guard isCurrent(mutation) else { return false }
            snapshot.fetalMovementEntries.removeAll { $0.id == id }
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    @discardableResult
    func endPregnancy(at date: Date = Date()) async -> Bool {
        guard let currentProfile = activeProfile else {
            syncStatus = .failed("当前没有进行中的孕期记录。")
            return false
        }
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }

        let endedProfile = PregnancyProfile(
            id: currentProfile.id,
            dueDate: currentProfile.dueDate,
            lastMenstrualPeriod: currentProfile.lastMenstrualPeriod,
            endedAt: date,
            createdAt: currentProfile.createdAt,
            updatedAt: Date()
        )

        do {
            let saved = try await repository.saveProfile(endedProfile)
            guard isCurrent(mutation) else { return false }
            snapshot.profile = saved
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    @discardableResult
    func deleteAllPregnancyData() async -> Bool {
        guard let mutation = beginMutation() else { return false }
        defer { finishMutation(mutation.id) }
        do {
            try await repository.deleteAllPregnancyData()
            guard isCurrent(mutation) else { return false }
            snapshot = .empty
            syncStatus = .synced(Date())
            return true
        } catch {
            guard isCurrent(mutation) else { return false }
            syncStatus = .failed(PregnancyCloudErrorText.message(for: error))
            return false
        }
    }

    private typealias MutationContext = (id: UUID, generation: Int)

    private func beginMutation() -> MutationContext? {
        guard hasLoadedSnapshot else {
            syncStatus = .failed("请先完成 iCloud 孕期记录读取，再进行修改。")
            return nil
        }
        guard activeLoadID == nil, activeMutationID == nil else { return nil }
        let id = UUID()
        activeMutationID = id
        syncStatus = .saving
        return (id, accountGeneration)
    }

    private func finishMutation(_ id: UUID) {
        if activeMutationID == id {
            activeMutationID = nil
        }
    }

    private func isCurrent(loadID: UUID, generation: Int) -> Bool {
        activeLoadID == loadID && accountGeneration == generation
    }

    private func isCurrent(_ mutation: MutationContext) -> Bool {
        activeMutationID == mutation.id && accountGeneration == mutation.generation
    }
}
