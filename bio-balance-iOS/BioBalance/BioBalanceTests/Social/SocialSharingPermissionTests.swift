import CloudKit
import XCTest
@testable import BioBalance

nonisolated final class SocialSharingPermissionTests: XCTestCase {
    @MainActor private let remoteFriendsCacheKey = "social.sharing.remote.friends.v2"
    @MainActor private let legacyRemoteFriendsCacheKey = "social.sharing.remote.friends.v1"
    @MainActor private let cloudAccountBindingKey = CloudKitDataPolicy.AccountBindingKey.socialSharing

    @MainActor func testFriendsDashboardPresentsAcceptedAndPendingConnectionsSeparately() {
        let presentation = SocialDashboardPresentation(
            friendCount: 3,
            pendingCount: 2,
            mutualCount: 1
        )

        XCTAssertEqual(presentation.totalConnectionCount, 5)
        XCTAssertEqual(presentation.primarySummary, "3 位好友保持连接")
        XCTAssertEqual(presentation.pendingSummary, "2 个邀请待回应")
    }

    @MainActor func testFriendsDashboardUsesInvitationPromptWhenThereAreNoConnections() {
        let presentation = SocialDashboardPresentation(
            friendCount: 0,
            pendingCount: 0,
            mutualCount: 0
        )

        XCTAssertEqual(presentation.primarySummary, "邀请一位好友，开始安全共享")
        XCTAssertNil(presentation.pendingSummary)
    }

    @MainActor func testFriendDetailCountsOnlySharedContentCategories() {
        let presentation = SocialFriendDetailPresentation(
            hasLocation: true,
            actionCount: 2,
            countdownCount: 0,
            todoCount: 3
        )

        XCTAssertEqual(presentation.sharedCategoryCount, 3)
        XCTAssertEqual(presentation.sharedSummary, "已分享 3 类内容")
        XCTAssertTrue(presentation.hasSharedContent)
    }

    @MainActor func testFriendDetailRecognizesAnEmptySharedContentGroup() {
        let presentation = SocialFriendDetailPresentation(
            hasLocation: false,
            actionCount: 0,
            countdownCount: 0,
            todoCount: 0
        )

        XCTAssertEqual(presentation.sharedCategoryCount, 0)
        XCTAssertEqual(presentation.sharedSummary, "暂未分享其他内容")
        XCTAssertFalse(presentation.hasSharedContent)
    }

    @MainActor func testHostAppDeclaresCloudKitSharingSupport() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CKSharingSupported") as? Bool,
            true
        )
    }

    @MainActor func testSharedSnapshotWriteFailsClosedWhenCloudIdentityIsUnavailable() async {
        let client = SocialSharingCloudKitClientStub(
            userRecordIDResult: .failure(CloudKitDomainError.notAuthenticated)
        )
        let repository = CloudKitSharingRepository(client: client)

        do {
            _ = try await repository.saveMySharedSnapshot(
                makeSnapshot(date: Date(timeIntervalSince1970: 1_000), todo: nil)
            )
            XCTFail("Expected identity lookup to fail")
        } catch {
            XCTAssertEqual(error as? CloudKitDomainError, .notAuthenticated)
        }

        XCTAssertEqual(client.writeCount, 0)
    }

    @MainActor func testSharedSnapshotWriteStopsBeforeRecordModifyWhenCloudAccountChanges() async {
        let client = SocialSharingCloudKitClientStub(
            userRecordIDResults: [
                .success(CKRecord.ID(recordName: "account-a")),
                .success(CKRecord.ID(recordName: "account-b"))
            ]
        )
        let repository = CloudKitSharingRepository(client: client)

        do {
            _ = try await repository.saveMySharedSnapshot(
                makeSnapshot(date: Date(timeIntervalSince1970: 1_000), todo: nil),
                expectedUserRecordName: "account-a"
            )
            XCTFail("Expected account validation to fail")
        } catch {
            XCTAssertEqual(error as? CloudKitDomainError, .iCloudUnavailable)
        }

        XCTAssertEqual(client.modifyCount, 0)
    }

    @MainActor func testSharedSnapshotUsesZoneOwnerWhenDeclaredOwnerMatches() async throws {
        let record = try makeSharedRecord(zoneOwner: "owner-a", declaredOwner: "owner-a")
        let repository = CloudKitSharingRepository(
            client: SocialSharingCloudKitClientStub(fetchedRecord: record)
        )

        let snapshot = try await repository.fetchSharedSnapshot(recordID: record.recordID)

        XCTAssertEqual(snapshot?.ownerRecordName, "owner-a")
    }

    @MainActor func testSharedSnapshotRejectsMismatchedDeclaredOwner() async throws {
        let record = try makeSharedRecord(zoneOwner: "owner-a", declaredOwner: "owner-b")
        let repository = CloudKitSharingRepository(
            client: SocialSharingCloudKitClientStub(fetchedRecord: record)
        )

        let snapshot = try await repository.fetchSharedSnapshot(recordID: record.recordID)

        XCTAssertNil(snapshot)
    }

    @MainActor func testSharedSnapshotRejectsMissingDeclaredOwner() async throws {
        let record = try makeSharedRecord(zoneOwner: "owner-a", declaredOwner: nil)
        let repository = CloudKitSharingRepository(
            client: SocialSharingCloudKitClientStub(fetchedRecord: record)
        )

        let snapshot = try await repository.fetchSharedSnapshot(recordID: record.recordID)

        XCTAssertNil(snapshot)
    }

    @MainActor func testFriendCacheDecodeDowngradesLegacyCollaboratorRoles() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let todo = SharedTodoListSummary(
            id: "todo",
            title: "共享待办",
            ownerUserRecordName: "owner-a",
            itemCount: 0,
            completedCount: 0,
            updatedAt: now,
            lastEditedByUserRecordName: nil,
            permissionRole: .collaborator,
            previewItems: []
        )
        let friend = FriendHealthProfile(
            id: "owner-a",
            ownerUserRecordName: "owner-a",
            name: "好友 A",
            relationshipState: .incomingShared,
            permissionRole: .collaborator,
            statusText: "已共享",
            sleepText: "暂无",
            walkingText: "暂无",
            lastUpdated: now,
            isStale: false,
            publicProfile: nil,
            availableContentSummary: "待办",
            snapshot: makeSnapshot(date: now, todo: todo)
        )

        let decoded = try JSONDecoder().decode(
            FriendHealthProfile.self,
            from: JSONEncoder().encode(friend)
        )

        XCTAssertEqual(decoded.permissionRole, .readOnly)
        XCTAssertEqual(decoded.snapshot.sharedTodoListSummary?.permissionRole, .readOnly)
    }

    @MainActor func testLegacyFullTodoPayloadDecodesAsCurrentSummary() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let item = SharedTodoItem(
            id: "item-1",
            title: "旧待办",
            isCompleted: true,
            note: nil,
            dueDate: nil,
            createdByUserRecordName: "owner-a",
            createdAt: now,
            updatedAt: now,
            fieldTimestamps: .uniform(now)
        )
        let legacyList = SharedTodoList(
            id: "todo-1",
            title: "旧共享待办",
            ownerUserRecordName: "owner-a",
            items: [item],
            updatedAt: now,
            lastEditedByUserRecordName: "owner-a",
            permissionRole: .collaborator
        )
        struct LegacySnapshot: Encodable {
            let ownerUserID: String? = nil
            let ownerDisplayName = "好友"
            let generatedAt: Date
            let days: [SharedHealthDay] = []
            let highlights: SharedHealthHighlights
            let payloadVersion = 2
            let sharedActionRecords: [SharedActionRecord] = []
            let sharedCountdownItems: [SharedCountdownItem] = []
            let sharedTodoListSummary: SharedTodoList
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(LegacySnapshot(
            generatedAt: now,
            highlights: SharedHealthHighlights(
                averageSleepMinutes: nil,
                averageWalkingSpeedMps: nil,
                validSleepDays: 0,
                validWalkingSpeedDays: 0
            ),
            sharedTodoListSummary: legacyList
        ))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SharedHealthSnapshot.self, from: data)

        XCTAssertEqual(decoded.sharedTodoListSummary?.id, legacyList.id)
        XCTAssertEqual(decoded.sharedTodoListSummary?.itemCount, 1)
        XCTAssertEqual(decoded.sharedTodoListSummary?.completedCount, 1)
        XCTAssertEqual(decoded.sharedTodoListSummary?.previewItems, [item])
    }

    @MainActor func testFriendIDsIncludeOwnerWhenRootRecordNamesMatch() {
        let zoneA = CKRecordZone.ID(zoneName: "FriendHealthShareZone", ownerName: "owner-a")
        let zoneB = CKRecordZone.ID(zoneName: "FriendHealthShareZone", ownerName: "owner-b")
        let snapshot = makeSnapshot(date: Date(timeIntervalSince1970: 1_000), todo: nil)
        let remoteSnapshots = [
            SharedRemoteHealthSnapshot(
                recordID: CKRecord.ID(recordName: "CurrentHealthShareRoot", zoneID: zoneA),
                recordName: "CurrentHealthShareRoot",
                ownerRecordName: "owner-a",
                permissionRole: .readOnly,
                snapshot: snapshot,
                generatedAt: snapshot.generatedAt
            ),
            SharedRemoteHealthSnapshot(
                recordID: CKRecord.ID(recordName: "CurrentHealthShareRoot", zoneID: zoneB),
                recordName: "CurrentHealthShareRoot",
                ownerRecordName: "owner-b",
                permissionRole: .readOnly,
                snapshot: snapshot,
                generatedAt: snapshot.generatedAt
            )
        ]

        let profiles = FollowService().makeFriendProfiles(from: remoteSnapshots)

        XCTAssertEqual(Set(profiles.map(\.id)), Set(["owner-a", "owner-b"]))
    }

    @MainActor func testBindingDifferentCloudKitAccountDropsPreviousFriendCache() throws {
        let suiteName = "SocialSharingPermissionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedHealthDataStore(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        store.bindFriendCache(to: "account-a")
        defaults.set(Data("current-cache".utf8), forKey: remoteFriendsCacheKey)
        defaults.set(Data("legacy-cache".utf8), forKey: legacyRemoteFriendsCacheKey)

        store.bindFriendCache(to: "account-b")

        XCTAssertEqual(defaults.string(forKey: cloudAccountBindingKey), "account-b")
        XCTAssertNil(defaults.data(forKey: remoteFriendsCacheKey))
        XCTAssertNil(defaults.data(forKey: legacyRemoteFriendsCacheKey))
        XCTAssertTrue(store.state.friends.isEmpty)
        XCTAssertTrue(store.state.outgoingShares.isEmpty)
        XCTAssertEqual(store.state.staleFriendCacheState, .none)
    }

    @MainActor func testCloudKitAccountChangeNotificationImmediatelyInvalidatesFriendCacheAndBinding() async throws {
        let suiteName = "SocialSharingPermissionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notificationCenter = NotificationCenter()
        let store = SharedHealthDataStore(
            defaults: defaults,
            notificationCenter: notificationCenter
        )

        store.bindFriendCache(to: "account-a")
        defaults.set(Data("current-cache".utf8), forKey: remoteFriendsCacheKey)
        defaults.set(Data("legacy-cache".utf8), forKey: legacyRemoteFriendsCacheKey)

        notificationCenter.post(name: .CKAccountChanged, object: nil)
        await Task.yield()

        XCTAssertNil(defaults.string(forKey: cloudAccountBindingKey))
        XCTAssertNil(defaults.data(forKey: remoteFriendsCacheKey))
        XCTAssertNil(defaults.data(forKey: legacyRemoteFriendsCacheKey))
        XCTAssertEqual(store.state.phase, .loaded)
        XCTAssertFalse(store.state.isICloudAvailable)
        XCTAssertEqual(store.state.emptyStateReason, .iCloudUnavailable)
        XCTAssertTrue(store.state.friends.isEmpty)
        XCTAssertEqual(store.state.myStatus.sharedFriendCount, 0)
    }

    @MainActor func testRemovingLocationStripsLocationFromSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = SharedHealthSnapshot(
            ownerUserID: nil,
            ownerDisplayName: "好友",
            generatedAt: now,
            days: [SharedHealthDay(date: now, sleepMinutes: 480, walkingSpeedMps: 1.2)],
            highlights: SharedHealthHighlights(
                averageSleepMinutes: 480,
                averageWalkingSpeedMps: 1.2,
                validSleepDays: 1,
                validWalkingSpeedDays: 1
            ),
            location: SharedLocationSummary(
                latitude: 31.23,
                longitude: 121.47,
                horizontalAccuracyMeters: 1_000,
                label: "约 31.23, 121.47",
                capturedAt: now
            ),
            payloadVersion: 3
        )

        let sanitized = snapshot.removingLocation()

        XCTAssertNil(sanitized.location)
        XCTAssertEqual(sanitized.days, snapshot.days)
        XCTAssertEqual(sanitized.highlights, snapshot.highlights)
        XCTAssertEqual(sanitized.payloadVersion, snapshot.payloadVersion)
        XCTAssertEqual(sanitized.ownerDisplayName, snapshot.ownerDisplayName)

        // 编码后的 payload 同样不得再包含 location 字段，避免旧位置重新进入共享载荷。
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sanitized)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["location"])
    }

    @MainActor func testPrivacyValidatorRejectsTooPreciseLocation() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = SharedHealthSnapshot(
            ownerUserID: nil,
            ownerDisplayName: "好友",
            generatedAt: now,
            days: [],
            highlights: SharedHealthHighlights(
                averageSleepMinutes: nil,
                averageWalkingSpeedMps: nil,
                validSleepDays: 0,
                validWalkingSpeedDays: 0
            ),
            location: SharedLocationSummary(
                latitude: 31.2301,
                longitude: 121.4736,
                horizontalAccuracyMeters: 10,
                label: "精确位置",
                capturedAt: now
            ),
            payloadVersion: 3
        )

        XCTAssertEqual(
            SharedHealthSnapshotPrivacyValidator.validate(snapshot),
            .locationTooPrecise(accuracyMeters: 10, minAccuracy: 500)
        )
    }

    @MainActor func testFriendSharePermissionFiltersSensitiveCategoriesBeforeEncoding() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let source = SharedHealthSnapshot(
            ownerUserID: nil,
            ownerDisplayName: "我",
            generatedAt: date,
            days: [SharedHealthDay(date: date, sleepMinutes: 465, walkingSpeedMps: 1.4)],
            highlights: SharedHealthHighlights(
                averageSleepMinutes: 465,
                averageWalkingSpeedMps: 1.4,
                validSleepDays: 1,
                validWalkingSpeedDays: 1
            ),
            payloadVersion: 3
        )

        let filtered = FriendSharePermission(
            sleep: false,
            activity: true,
            liveStatus: false,
            showsLastUpdated: true
        ).filtering(source)

        XCTAssertNil(filtered.days.first?.sleepMinutes)
        XCTAssertNil(filtered.highlights.averageSleepMinutes)
        XCTAssertEqual(filtered.highlights.validSleepDays, 0)
        XCTAssertEqual(filtered.days.first?.walkingSpeedMps, 1.4)
        XCTAssertEqual(filtered.highlights.validWalkingSpeedDays, 1)
        let encoded = try JSONEncoder().encode(filtered)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("465"))
    }

    @MainActor private func makeSnapshot(
        date: Date,
        todo: SharedTodoListSummary?
    ) -> SharedHealthSnapshot {
        SharedHealthSnapshot(
            ownerUserID: nil,
            ownerDisplayName: "好友",
            generatedAt: date,
            days: [],
            highlights: SharedHealthHighlights(
                averageSleepMinutes: nil,
                averageWalkingSpeedMps: nil,
                validSleepDays: 0,
                validWalkingSpeedDays: 0
            ),
            payloadVersion: 3,
            sharedTodoListSummary: todo
        )
    }

    @MainActor private func makeSharedRecord(
        zoneOwner: String,
        declaredOwner: String?
    ) throws -> CKRecord {
        let date = Date(timeIntervalSince1970: 1_000)
        let zoneID = CKRecordZone.ID(zoneName: "FriendHealthShareZone", ownerName: zoneOwner)
        let record = CKRecord(
            recordType: "HealthShareRoot",
            recordID: CKRecord.ID(recordName: "CurrentHealthShareRoot", zoneID: zoneID)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        record["payloadData"] = try encoder.encode(makeSnapshot(date: date, todo: nil)) as CKRecordValue
        record["generatedAt"] = date as CKRecordValue
        record["ownerUserRecordName"] = declaredOwner as CKRecordValue?
        return record
    }
}

private final class SocialSharingCloudKitClientStub: CloudKitClientProtocol, @unchecked Sendable {
    private let userRecordIDResults: [Result<CKRecord.ID, Error>]
    private let fetchedRecord: CKRecord?
    private let lock = NSLock()
    private var nextUserRecordIDResultIndex = 0
    private var storedWriteCount = 0
    private var storedModifyCount = 0

    init(
        userRecordIDResult: Result<CKRecord.ID, Error> = .success(CKRecord.ID(recordName: "current-user")),
        userRecordIDResults: [Result<CKRecord.ID, Error>]? = nil,
        fetchedRecord: CKRecord? = nil
    ) {
        self.userRecordIDResults = userRecordIDResults ?? [userRecordIDResult]
        self.fetchedRecord = fetchedRecord
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedWriteCount
    }

    var modifyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedModifyCount
    }

    func accountStatus(container: CKContainer) async throws -> CKAccountStatus {
        .available
    }

    func fetchUserRecordID(container: CKContainer) async throws -> CKRecord.ID {
        try nextUserRecordIDResult().get()
    }

    func accept(metadata: CKShare.Metadata, container: CKContainer) async throws {
        recordWrite()
    }

    func save(zone: CKRecordZone, in database: CKDatabase) async throws -> CKRecordZone {
        recordWrite()
        return zone
    }

    func delete(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        recordWrite()
    }

    func fetch(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        fetchedRecord
    }

    func save(record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        recordWrite()
        return record
    }

    func modify(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        in database: CKDatabase
    ) async throws -> [CKRecord] {
        recordModify()
        return recordsToSave
    }

    func runQuery(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        zoneID: CKRecordZone.ID?,
        in database: CKDatabase
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        ([], nil)
    }

    func fetchAllZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        []
    }

    private func recordWrite() {
        lock.lock()
        storedWriteCount += 1
        lock.unlock()
    }

    private func recordModify() {
        lock.lock()
        storedWriteCount += 1
        storedModifyCount += 1
        lock.unlock()
    }

    private func nextUserRecordIDResult() -> Result<CKRecord.ID, Error> {
        lock.lock()
        defer { lock.unlock() }
        let index = min(nextUserRecordIDResultIndex, userRecordIDResults.count - 1)
        nextUserRecordIDResultIndex += 1
        return userRecordIDResults[index]
    }
}
