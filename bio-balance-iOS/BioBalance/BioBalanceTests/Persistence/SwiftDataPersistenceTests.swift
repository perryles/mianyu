import Foundation
import SwiftData
import XCTest
@testable import BioBalance

nonisolated final class SwiftDataPersistenceTests: XCTestCase {
    @MainActor func testCaffeineLegacyPayloadMigratesOnceAndPersistsAcrossStoreInstances() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let consumedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let event = CaffeineDoseEvent(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            amountMg: 80,
            consumedAt: consumedAt,
            source: .manualLog,
            note: "migration"
        )
        struct LegacyPayload: Encodable { let events: [CaffeineDoseEvent] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(
            try encoder.encode(LegacyPayload(events: [event])),
            forKey: "caffeineDoseEventStore.v1"
        )

        let migrated = CaffeineDoseEventStore(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(migrated.allEvents(), [event])
        XCTAssertNil(fixture.defaults.data(forKey: "caffeineDoseEventStore.v1"))

        migrated.append(amountMg: 40, consumedAt: consumedAt.addingTimeInterval(60), source: .quickAdd)
        let reopened = CaffeineDoseEventStore(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(reopened.allEvents().map(\.amountMg), [40, 80])
    }

    @MainActor func testQueryableHabitMoodAssessmentAndDrinkRecordsPersist() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let date = Date(timeIntervalSince1970: 1_725_000_000)

        let fitness = FitnessCalendarStore(defaults: fixture.defaults, container: fixture.container)
        fitness.updateRecord(for: date) { record in
            record.completedActions = [.water, .sunlight]
            record.waterMl = 600
        }
        XCTAssertEqual(
            FitnessCalendarStore(defaults: fixture.defaults, container: fixture.container)
                .record(for: date).completedActions,
            [.sunlight, .water]
        )

        let mood = MoodEntry(
            id: "mood-1",
            moodID: "calm",
            title: "平静",
            backendEmotionCode: "neutral",
            intensity: 45,
            note: nil,
            loggedAt: date,
            backendRecordedAt: nil
        )
        MoodStore(defaults: fixture.defaults, container: fixture.container).save(mood)
        XCTAssertEqual(
            MoodStore(defaults: fixture.defaults, container: fixture.container).allEntries(),
            [mood]
        )

        let assessment = MentalAssessmentResult(
            kind: .gad7,
            recordedAt: date,
            answers: [0, 1, 1, 0, 0, 1, 0],
            score: 3,
            source: .local,
            syncedToHealthKitAt: nil
        )
        MentalAssessmentStore(defaults: fixture.defaults, container: fixture.container).save(assessment)
        XCTAssertEqual(
            MentalAssessmentStore(defaults: fixture.defaults, container: fixture.container)
                .latestResult(for: .gad7),
            assessment
        )

        let drink = DrinkStampRecord(
            id: "drink-1",
            storeName: "本地咖啡店",
            cityName: "上海",
            drinkName: "美式",
            capturedAt: date,
            photoFileID: nil,
            photoURL: nil,
            cutoutFileID: nil,
            cutoutURL: nil,
            latitude: nil,
            longitude: nil,
            locationLabel: nil,
            status: .confirmed,
            isGeneratedFromRecognition: false
        )
        DrinkExperienceStore(defaults: fixture.defaults, container: fixture.container).saveStamp(drink)
        XCTAssertEqual(
            DrinkExperienceStore(defaults: fixture.defaults, container: fixture.container)
                .allStamps().first?.id,
            drink.id
        )
    }

    @MainActor func testPeriodStatePersistsInSwiftData() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_720_500_000))

        let first = PeriodStore(defaults: fixture.defaults, container: fixture.container)
        let cycleID = first.startCycle(startDate: start)
        _ = first.upsertDayLog(date: start, flowLevel: 2, painLevel: 1, moodLevel: nil, note: "day one")

        let reopened = PeriodStore(defaults: fixture.defaults, container: fixture.container)
        let summary = reopened.summary(days: 10, referenceDate: start)
        XCTAssertEqual(summary.current?.cycleId, cycleID)
        XCTAssertEqual(summary.dayLogs?.first?.flowLevel, 2)
        XCTAssertEqual(summary.dayLogs?.first?.note, "day one")
    }

    @MainActor func testMedicationLegacyPayloadMigratesToSwiftDataAndRemovesOldKeys() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let takenAt = Date(timeIntervalSince1970: 1_726_000_000)
        let entry = MedicationEntry(
            id: "medication-entry-1",
            name: "测试记录",
            amount: 1,
            unit: "片",
            takenAt: takenAt
        )
        struct LegacyPayload: Encodable {
            let entries: [MedicationEntry]
            let plans: [MedicationPlan]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(
            try encoder.encode(LegacyPayload(entries: [entry], plans: [])),
            forKey: "medicationStore.v1"
        )

        let migrated = MedicationStore(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(migrated.allEntries(), [entry])
        XCTAssertNil(fixture.defaults.data(forKey: "medicationStore.v1"))
        XCTAssertNil(fixture.defaults.data(forKey: "medicationStore.v2"))

        let reopened = MedicationStore(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(reopened.allEntries(), [entry])
    }

    @MainActor func testCountdownAndSharedTodoLegacyPayloadsMigrateToSwiftData() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let date = Date(timeIntervalSince1970: 1_727_000_000)
        let countdown = LocalCountdownItem(
            id: "countdown-1",
            title: "复诊",
            targetDate: date,
            note: nil,
            isPinned: true,
            isShared: false,
            createdAt: date.addingTimeInterval(-60),
            updatedAt: date
        )
        struct CountdownPayload: Encodable { let items: [LocalCountdownItem] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(try encoder.encode(CountdownPayload(items: [countdown])), forKey: "countdownStore.v1")

        let todoList = LocalSharedTodoList(
            id: "shared-todo-list",
            title: "家人健康事项",
            isShared: true,
            items: [],
            updatedAt: date
        )
        fixture.defaults.set(try encoder.encode(todoList), forKey: "social.sharedTodoStore.v1")

        XCTAssertEqual(
            CountdownStore(defaults: fixture.defaults, container: fixture.container).items(),
            [countdown]
        )
        XCTAssertEqual(
            SharedTodoStore(defaults: fixture.defaults, container: fixture.container).loadList(),
            todoList
        )
        XCTAssertNil(fixture.defaults.data(forKey: "countdownStore.v1"))
        XCTAssertNil(fixture.defaults.data(forKey: "social.sharedTodoStore.v1"))

        XCTAssertEqual(
            CountdownStore(defaults: fixture.defaults, container: fixture.container).items(),
            [countdown]
        )
        XCTAssertEqual(
            SharedTodoStore(defaults: fixture.defaults, container: fixture.container).loadList(),
            todoList
        )
    }

    @MainActor func testGoalsLegacyPayloadMigratesIntoQueryableKinds() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let date = Date(timeIntervalSince1970: 1_728_000_000)
        let goal = GoalItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "每日散步",
            category: .movement,
            symbol: "figure.walk",
            targetValue: 20,
            unit: "分钟",
            linkedActionKind: nil,
            isActive: true,
            createdAt: date
        )
        let pet = GoalPetState(
            name: "TATA",
            level: 2,
            xp: 10,
            rewardCount: 3,
            createdAt: date,
            lastXPDate: date,
            nameUpdatedAt: nil
        )
        struct LegacyGoalsPayload: Encodable {
            let goals: [GoalItem]
            let records: [GoalProgressRecord]
            let petState: GoalPetState
            let xpGrants: [GoalXPGrant]?
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(
            try encoder.encode(LegacyGoalsPayload(goals: [goal], records: [], petState: pet, xpGrants: [])),
            forKey: "goals.store.payload.v1"
        )

        let migrated = GoalsStore(
            defaults: fixture.defaults,
            cloudRepository: nil,
            container: fixture.container
        )
        XCTAssertEqual(migrated.goals, [goal])
        XCTAssertEqual(migrated.petState, pet)
        XCTAssertNil(fixture.defaults.data(forKey: "goals.store.payload.v1"))

        let reopened = GoalsStore(
            defaults: fixture.defaults,
            cloudRepository: nil,
            container: fixture.container
        )
        XCTAssertEqual(reopened.goals, [goal])
        XCTAssertEqual(reopened.petState, pet)
    }

    @MainActor func testPeriodLegacyEventTextMovesToStructuredFieldsAndLeavesResidualNote() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_729_000_000))
        let store = PeriodStore(defaults: fixture.defaults, container: fixture.container)
        _ = store.upsertDayLog(
            date: date,
            flowLevel: nil,
            painLevel: nil,
            moodLevel: nil,
            note: "性行为 · 妊娠测试阴性 · 普通备注"
        )

        let log = try XCTUnwrap(store.summary(days: 2, referenceDate: date).dayLogs?.first)
        XCTAssertEqual(log.hasSexualActivity, true)
        XCTAssertEqual(log.pregnancyTestResult, "negative")
        XCTAssertEqual(log.note, "普通备注")
    }

    @MainActor func testOutboxKeepsRevisionAwarePersistenceSemantics() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let outbox = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)

        let result = outbox.enqueue(
            recordType: .userEvent,
            recordID: "event-1",
            schemaVersion: 1,
            payload: Data("payload".utf8),
            now: now
        )
        guard case let .enqueued(item) = result else {
            return XCTFail("Expected an enqueued item")
        }

        let reopened = LocalSyncOutbox(defaults: fixture.defaults, container: fixture.container)
        XCTAssertEqual(reopened.pending(at: now, limit: 10), [item])
        XCTAssertFalse(reopened.markSucceeded(id: item.id, revision: "stale-revision"))
        XCTAssertTrue(reopened.markSucceeded(id: item.id, revision: item.revision))
        XCTAssertEqual(reopened.count(), 0)
    }

    @MainActor func testSleepRhythmTargetOffsetPersistsAndStaysWithinSafetyRange() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date(timeIntervalSince1970: 1_730_500_000)
        let store = SleepRhythmProtectionStore(
            defaults: fixture.defaults,
            calendar: Calendar(identifier: .gregorian),
            container: fixture.container
        )

        _ = store.start(mode: .rhythmTraining, on: now)
        XCTAssertEqual(store.adjustTargetOffset(by: -15, on: now)?.targetOffsetMinutes, -15)
        XCTAssertEqual(store.adjustTargetOffset(by: -200, on: now)?.targetOffsetMinutes, -90)

        let reopened = SleepRhythmProtectionStore(
            defaults: fixture.defaults,
            calendar: Calendar(identifier: .gregorian),
            container: fixture.container
        )
        XCTAssertEqual(reopened.activePlan()?.targetOffsetMinutes, -90)

        XCTAssertEqual(reopened.adjustTargetOffset(by: 300, on: now)?.targetOffsetMinutes, 90)
        XCTAssertEqual(reopened.adjustTargetOffset(by: nil, on: now)?.targetOffsetMinutes, 0)
        XCTAssertEqual(
            SleepRhythmProtectionStore(
                defaults: fixture.defaults,
                calendar: Calendar(identifier: .gregorian),
                container: fixture.container
            ).activePlan()?.targetOffsetMinutes,
            0
        )
    }

    @MainActor private func makeFixture() throws -> (container: ModelContainer, defaults: UserDefaults, suiteName: String) {
        let suiteName = "SwiftDataPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (
            try MianyuModelContainer.make(isStoredInMemoryOnly: true),
            defaults,
            suiteName
        )
    }
}
