import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { HealthScoreEngine } from '../main/ets/model/HealthScoreEngine';
import { CloudCursor, CloudRecord, CloudRecordInput, CloudSyncPolicy } from '../main/ets/model/CloudSyncContract';
import { CloudOutbox, CloudOutboxItem } from '../main/ets/model/CloudOutbox';
import { CloudAccountSnapshot, CloudAccountStatePolicy } from '../main/ets/model/CloudAccountState';
import { CloudAccountSession, CloudPullResult, CloudPushResult,
  CloudSyncTransport } from '../main/ets/service/CloudSyncTransport';
import { CloudSyncCoordinator, CloudSyncResult } from '../main/ets/service/CloudSyncCoordinator';
import { CloudQueryAdapter, CloudQueryPage, CloudQueryRow, CompoundCloudQueryAdapter,
  CompoundQueryExecutor, ReliableCloudPuller } from '../main/ets/service/ReliableCloudPuller';
import { CloudStateMutex, CloudSyncRepository, CloudSyncSettings,
  CloudSyncPendingCounts } from '../main/ets/service/CloudSyncStateStore';

class FakeSyncRepository implements CloudSyncRepository {
  accountId: string = 'account-a';
  generation: number = 1;
  enabled: boolean = true;
  itemList: CloudOutboxItem[] = [];
  recordList: CloudRecordInput[] = [];
  acknowledged: number = 0;
  retryable: number = 0;
  permanent: number = 0;
  committed: number = 0;

  async settings(): Promise<CloudSyncSettings> {
    const settings: CloudSyncSettings = { enabled: this.enabled, accountId: this.accountId, generation: this.generation,
      cursor: { revision: 0, recordId: '' }, logicalClock: 0 };
    return settings;
  }
  async isSessionActive(accountId: string, generation: number): Promise<boolean> {
    return this.enabled && this.accountId === accountId && this.generation === generation;
  }
  async invalidateSession(accountId: string, generation: number, actualAccountId: string): Promise<boolean> {
    if (this.accountId !== accountId || this.generation !== generation) return false;
    this.accountId = actualAccountId; this.generation += 1; this.enabled = false;
    this.itemList = []; this.recordList = []; return true;
  }
  async claimDue(accountId: string, generation: number, now: number): Promise<CloudOutboxItem[]> {
    return await this.isSessionActive(accountId, generation) ? this.itemList : [];
  }
  async record(accountId: string, generation: number, recordId: string): Promise<CloudRecord | undefined> {
    if (!await this.isSessionActive(accountId, generation)) return undefined;
    const input: CloudRecordInput | undefined = this.recordList.find((item: CloudRecordInput): boolean => item.recordId === recordId);
    return input === undefined ? undefined : CloudSyncPolicy.sanitize(input);
  }
  async acknowledge(accountId: string, generation: number, operationId: string): Promise<boolean> {
    if (!await this.isSessionActive(accountId, generation)) return false;
    this.acknowledged += 1; return true;
  }
  async markRetryable(accountId: string, generation: number, operationId: string, now: number,
    retryAfterMs: number): Promise<boolean> {
    if (!await this.isSessionActive(accountId, generation)) return false;
    this.retryable += 1; return true;
  }
  async markPermanent(accountId: string, generation: number, operationId: string, errorCode: number): Promise<boolean> {
    if (!await this.isSessionActive(accountId, generation)) return false;
    this.permanent += 1; return true;
  }
  async commitPull(accountId: string, generation: number, result: CloudPullResult): Promise<boolean> {
    if (!await this.isSessionActive(accountId, generation)) return false;
    this.committed += 1; return true;
  }
  async pendingCounts(accountId: string, generation: number): Promise<CloudSyncPendingCounts> {
    const counts: CloudSyncPendingCounts = { retryable: this.retryable, permanent: this.permanent };
    return counts;
  }
}

class FakeSyncTransport implements CloudSyncTransport {
  pushResults: CloudPushResult[] = [];
  pushIndex: number = 0;
  onPush?: () => void;
  onPull?: () => void;
  pullCalled: boolean = false;
  events: string[] = [];
  authSession?: FakeAccountSession;
  onBeforeAuthenticatedWrite?: () => void;
  actualWrites: number = 0;

  async push(record: CloudRecord, expectedAccountId: string): Promise<CloudPushResult> {
    this.events.push('push');
    if (this.onPush !== undefined) this.onPush();
    if (this.onBeforeAuthenticatedWrite !== undefined) this.onBeforeAuthenticatedWrite();
    if (this.authSession !== undefined && await this.authSession.currentAccountId() !== expectedAccountId)
      return { status: 'account_changed', retryAfterMs: 0, errorCode: 1008230010 };
    this.actualWrites += 1;
    const result: CloudPushResult = this.pushResults[this.pushIndex];
    this.pushIndex += 1;
    return result;
  }
  async pullChanges(accountId: string, cursor: CloudCursor): Promise<CloudPullResult> {
    if (this.onPull !== undefined) this.onPull();
    this.pullCalled = true;
    this.events.push('pull');
    return { records: [], cursor, maxRevision: cursor.revision };
  }
}

class FakeAccountSession implements CloudAccountSession {
  accountId: string = 'account-a';
  checks: number = 0;

  async currentAccountId(): Promise<string> { this.checks += 1; return this.accountId; }
}

class FakeCloudQueryAdapter implements CloudQueryAdapter {
  rows: CloudQueryRow[] = [];
  requestedCursors: CloudCursor[] = [];

  async queryAfter(accountId: string, cursor: CloudCursor, limit: number): Promise<CloudQueryPage> {
    this.requestedCursors.push({ revision: cursor.revision, recordId: cursor.recordId });
    const matches: CloudQueryRow[] = this.rows.filter((row: CloudQueryRow): boolean =>
      row.record !== undefined && row.record.accountId === accountId && CloudSyncPolicy.isAfterCursor(row.revision,
        row.physicalRecordId, cursor));
    matches.sort((left: CloudQueryRow, right: CloudQueryRow): number =>
      left.revision === right.revision ? left.physicalRecordId.localeCompare(right.physicalRecordId) :
        left.revision - right.revision);
    const rows: CloudQueryRow[] = matches.slice(0, limit);
    return { rows, hasMore: rows.length === limit };
  }
}

class FakeCompoundQueryExecutor implements CompoundQueryExecutor {
  same: CloudQueryRow[] = [];
  later: CloudQueryRow[] = [];
  laterLimits: number[] = [];
  async querySameRevision(accountId: string, cursor: CloudCursor, limit: number): Promise<CloudQueryRow[]> {
    return this.same.slice(0, limit);
  }
  async queryLaterRevisions(accountId: string, revision: number, limit: number): Promise<CloudQueryRow[]> {
    this.laterLimits.push(limit); return this.later.slice(0, limit);
  }
import { HealthSyncPolicy } from '../main/ets/model/HealthSyncPolicy';
import type {
  HealthAuthorizationStatus,
  HealthDisplayState,
  HealthMergeResult,
  HuaweiHealthSnapshot,
  SleepStages
} from '../main/ets/model/HealthSyncPolicy';

const EMPTY_STAGES: SleepStages = {
  deepMinutes: 0,
  shallowMinutes: 0,
  dreamMinutes: 0,
  awakeMinutes: 0,
  totalMinutes: 0,
  hasDetails: false
};

function existingHealthState(): HealthDisplayState {
  return {
    steps: 4321,
    restingHeartRate: 61,
    sleepMinutes: 450,
    sleepScore: 82,
    hasSteps: true,
    hasRestingHeartRate: true,
    hasSleep: true,
    dailySteps: [1000, 2000, 3000, 4000, 5000, 6000, 4321],
    dailyStepDates: ['1', '2', '3', '4', '5', '6', '7'],
    dailyRestingHeartRates: [60, 61, 62, 63, 64, 65, 61],
    dailySleepMinutes: [420, 430, 440, 450, 460, 470, 450],
    dailySleepScores: [78, 79, 80, 81, 82, 83, 82],
    lastSleepStages: EMPTY_STAGES
  };
}

function failedSnapshot(errorCode: number): HuaweiHealthSnapshot {
  return {
    steps: 0,
    restingHeartRate: 0,
    sleepMinutes: 0,
    sleepScore: 0,
    hasSteps: false,
    hasRestingHeartRate: false,
    hasSleep: false,
    dailySteps: [0, 0, 0, 0, 0, 0, 0],
    dailyStepDates: [],
    dailyRestingHeartRates: [0, 0, 0, 0, 0, 0, 0],
    dailySleepMinutes: [0, 0, 0, 0, 0, 0, 0],
    dailySleepScores: [0, 0, 0, 0, 0, 0, 0],
    lastSleepStages: EMPTY_STAGES,
    stepsStatus: { attempted: true, success: false, errorCode: errorCode },
    restingHeartRateStatus: { attempted: true, success: false, errorCode: errorCode },
    sleepStatus: { attempted: true, success: false, errorCode: errorCode },
    updatedAt: 1000
  };
}

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('calculatesDailyHealthScore', 0, () => {
      expect(HealthScoreEngine.calculate(4, 4000, 3, 8000)).assertEqual(62);
      expect(HealthScoreEngine.calculate(8, 8000, 5, 8000)).assertEqual(81);
    });
    it('clampsInvalidInputs', 0, () => {
      expect(HealthScoreEngine.calculate(-2, -100, 10, 0)).assertEqual(51);
      expect(HealthScoreEngine.percentage(4000, 8000)).assertEqual(50);
      expect(HealthScoreEngine.percentage(100, 0)).assertEqual(0);
    });
    it('keepsOnlyWhitelistedCloudFields', 0, () => {
      const input: CloudRecordInput = {
        recordType: 'CheckinSummary', recordId: 'checkin-2026-08-08', accountId: 'opaque-account',
        dateKey: '2026-08-08', moodCode: 3, waterCups: 6, updatedAt: 1000,
        revision: 2, deviceId: 'device-b', schemaVersion: 1,
        medicationName: 'forbidden', symptomText: 'forbidden'
      };
      const sanitized = CloudSyncPolicy.sanitize(input);
      expect(sanitized === undefined).assertFalse();
      const encoded = JSON.stringify(sanitized);
      expect(encoded.includes('medicationName')).assertFalse();
      expect(encoded.includes('symptomText')).assertFalse();
      expect(encoded.includes('"moodCode":3')).assertTrue();
    });
    it('rejectsUnknownCloudRecordTypes', 0, () => {
      const input: CloudRecordInput = {
        recordType: 'RawHeartRateSample', recordId: 'raw-1', accountId: 'opaque-account',
        dateKey: '2026-08-08', updatedAt: 1000, revision: 1, deviceId: 'device-a', schemaVersion: 1
      };
      expect(CloudSyncPolicy.sanitize(input) === undefined).assertTrue();
    });
    it('resolvesConflictsDeterministically', 0, () => {
      const older = CloudSyncPolicy.sanitize({
        recordType: 'CheckinSummary', recordId: 'same', accountId: 'account', dateKey: '2026-08-08',
        waterCups: 3, updatedAt: 1000, revision: 1, deviceId: 'device-z', schemaVersion: 1
      });
      const newer = CloudSyncPolicy.sanitize({
        recordType: 'CheckinSummary', recordId: 'same', accountId: 'account', dateKey: '2026-08-08',
        waterCups: 4, updatedAt: 900, revision: 2, deviceId: 'device-a', schemaVersion: 1
      });
      expect(CloudSyncPolicy.resolveConflict(older!, newer!).waterCups).assertEqual(4);
      const tied = CloudSyncPolicy.sanitize({
        recordType: 'CheckinSummary', recordId: 'same', accountId: 'account', dateKey: '2026-08-08',
        waterCups: 5, updatedAt: 1000, revision: 2, deviceId: 'device-z', schemaVersion: 1
      });
      expect(CloudSyncPolicy.resolveConflict(newer!, tied!).waterCups).assertEqual(5);
    });
    it('ignoresWallClockDriftWhenResolvingConflicts', 0, () => {
      const fastClock = CloudSyncPolicy.sanitize({
        recordType: 'CheckinSummary', recordId: 'same', accountId: 'account', dateKey: '2026-08-08',
        waterCups: 2, updatedAt: 999999999, revision: 7, deviceId: 'device-a', schemaVersion: 1
      });
      const normalClock = CloudSyncPolicy.sanitize({
        recordType: 'CheckinSummary', recordId: 'same', accountId: 'account', dateKey: '2026-08-08',
        waterCups: 8, updatedAt: 100, revision: 7, deviceId: 'device-z', schemaVersion: 1
      });
      expect(CloudSyncPolicy.resolveConflict(fastClock!, normalClock!).waterCups).assertEqual(8);
    });
    it('usesStableCompoundCursorAcrossEqualTimestampPages', 0, () => {
      const cursor: CloudCursor = { revision: 7, recordId: 'record-b' };
      expect(CloudSyncPolicy.isAfterCursor(7, 'record-a', cursor)).assertFalse();
      expect(CloudSyncPolicy.isAfterCursor(7, 'record-c', cursor)).assertTrue();
      expect(CloudSyncPolicy.isAfterCursor(8, 'record-a', cursor)).assertTrue();
      const next: CloudCursor = CloudSyncPolicy.advanceCursor(cursor, 7, 'record-z');
      expect(next.revision).assertEqual(7);
      expect(next.recordId).assertEqual('record-z');
    });
    it('partitionsCloudPrimaryKeysByOpaqueAccount', 0, () => {
      const keyA: string = CloudSyncPolicy.cloudStorageRecordId('opaque-a', 'checkin-1');
      const keyB: string = CloudSyncPolicy.cloudStorageRecordId('opaque-b', 'checkin-1');
      expect(keyA === keyB).assertFalse();
      expect(CloudSyncPolicy.logicalRecordId('opaque-a', keyA)).assertEqual('checkin-1');
      expect(CloudSyncPolicy.logicalRecordId('opaque-b', keyA) === undefined).assertTrue();
    });
    it('rebasesQueuedRevisionAfterRemoteClockAdvances', 0, () => {
      expect(CloudSyncPolicy.nextLogicalRevision(40, 3)).assertEqual(41);
      expect(CloudSyncPolicy.nextLogicalRevision(4, 9)).assertEqual(10);
      expect(CloudSyncPolicy.nextLogicalRevision(9, 9)).assertEqual(10);
      expect(CloudSyncPolicy.needsRebase(9, 9)).assertTrue();
      expect(CloudSyncPolicy.needsRebase(9, 10)).assertFalse();
    });
    it('advancesPhysicalCursorAcrossFullMalformedAndEqualRevisionPages', 0, () => {
      let cursor: CloudCursor = { revision: 12, recordId: '' };
      const physicalIds: string[] = [];
      for (let index: number = 0; index < 205; index++) {
        const physicalId: string = index < 100 ? `legacy-${index.toString().padStart(3, '0')}` :
          CloudSyncPolicy.cloudStorageRecordId('opaque-a', `record-${index.toString().padStart(3, '0')}`);
        physicalIds.push(physicalId);
      }
      physicalIds.sort();
      physicalIds.forEach((physicalId: string): void => {
        cursor = CloudSyncPolicy.advanceCursor(cursor, 12, physicalId);
      });
      expect(cursor.revision).assertEqual(12);
      expect(cursor.recordId).assertEqual('legacy-099');
    });
    it('replaysFromOriginToFindLateSameRevisionSmallerRecordId', 0, async () => {
      const adapter: FakeCloudQueryAdapter = new FakeCloudQueryAdapter();
      const recordZ: CloudRecord = CloudSyncPolicy.sanitize({ recordType: 'CheckinSummary', recordId: 'z',
        accountId: 'account-a', dateKey: '2026-08-08', updatedAt: 1, revision: 7, deviceId: 'd1',
        schemaVersion: 1, waterCups: 1 })!;
      adapter.rows = [{ physicalRecordId: 'z', revision: 7, record: recordZ }];
      const puller: ReliableCloudPuller = new ReliableCloudPuller(adapter, 1);
      const first: CloudPullResult = await puller.pullChanges('account-a', { revision: 0, recordId: '' });
      const lateA: CloudRecord = CloudSyncPolicy.sanitize({ recordType: 'CheckinSummary', recordId: 'a',
        accountId: 'account-a', dateKey: '2026-08-07', updatedAt: 2, revision: 7, deviceId: 'd2',
        schemaVersion: 1, waterCups: 2 })!;
      adapter.rows.push({ physicalRecordId: 'a', revision: 7, record: lateA });
      const secondStart: number = adapter.requestedCursors.length;
      const second: CloudPullResult = await puller.pullChanges('account-a', first.cursor);
      expect(adapter.requestedCursors[secondStart].revision).assertEqual(0);
      expect(second.records.some((record: CloudRecord): boolean => record.recordId === 'a')).assertTrue();
    });
    it('fillsUnderfullSameRevisionPageWithLaterRevisions', 0, async () => {
      const executor: FakeCompoundQueryExecutor = new FakeCompoundQueryExecutor();
      executor.same = [{ physicalRecordId: 'z', revision: 7 }];
      executor.later = [{ physicalRecordId: 'a', revision: 8 }];
      const page: CloudQueryPage = await new CompoundCloudQueryAdapter(executor)
        .queryAfter('account-a', { revision: 7, recordId: 'y' }, 3);
      expect(page.rows.length).assertEqual(2);
      expect(page.rows[1].revision).assertEqual(8);
      expect(executor.laterLimits[0]).assertEqual(2);
      expect(page.hasMore).assertFalse();
    });
    it('capsCloudRetryBackoff', 0, () => {
      expect(CloudSyncPolicy.nextRetryDelayMs(0)).assertEqual(5000);
      expect(CloudSyncPolicy.nextRetryDelayMs(3)).assertEqual(40000);
      expect(CloudSyncPolicy.nextRetryDelayMs(20)).assertEqual(3600000);
    });
    it('claimsOnlyDueCloudOutboxItems', 0, () => {
      const items: CloudOutboxItem[] = [
        { operationId: 'due', recordId: 'r1', attempts: 0, nextAttemptAt: 10, leasedUntil: 0 },
        { operationId: 'future', recordId: 'r2', attempts: 0, nextAttemptAt: 200, leasedUntil: 0 },
        { operationId: 'leased', recordId: 'r3', attempts: 0, nextAttemptAt: 10, leasedUntil: 300 }
      ];
      const claimed = CloudOutbox.claimDue(items, 100, 50, 10);
      expect(claimed.length).assertEqual(1);
      expect(claimed[0].operationId).assertEqual('due');
      expect(claimed[0].leasedUntil).assertEqual(150);
    });
    it('acknowledgesAndRetriesCloudOutboxItems', 0, () => {
      const items: CloudOutboxItem[] = [
        { operationId: 'one', recordId: 'r1', attempts: 0, nextAttemptAt: 0, leasedUntil: 10 },
        { operationId: 'two', recordId: 'r2', attempts: 0, nextAttemptAt: 0, leasedUntil: 10 }
      ];
      expect(CloudOutbox.acknowledge(items, 'one').length).assertEqual(1);
      const failed = CloudOutbox.markFailed(items, 'one', 100);
      expect(failed[0].attempts).assertEqual(1);
      expect(failed[0].leasedUntil).assertEqual(0);
      expect(failed[0].nextAttemptAt).assertEqual(5100);
    });
    it('resetsAllSyncStateWhenAccountChanges', 0, () => {
      const oldState: CloudAccountSnapshot = {
        accountId: 'account-a', generation: 4, enabled: true,
        cursorRevision: 12, cursorRecordId: 'record-z', logicalClock: 12,
        recordsJson: '[{"accountId":"account-a"}]', outboxJson: '[{"operationId":"old"}]'
      };
      const switched: CloudAccountSnapshot = CloudAccountStatePolicy.bind(oldState, 'account-b');
      expect(switched.accountId).assertEqual('account-b');
      expect(switched.generation).assertEqual(5);
      expect(switched.enabled).assertFalse();
      expect(switched.cursorRevision).assertEqual(0);
      expect(switched.cursorRecordId).assertEqual('');
      expect(switched.logicalClock).assertEqual(0);
      expect(switched.recordsJson).assertEqual('[]');
      expect(switched.outboxJson).assertEqual('[]');
    });
    it('keepsStateWhenBindingSameAccount', 0, () => {
      const state: CloudAccountSnapshot = {
        accountId: 'account-a', generation: 4, enabled: true,
        cursorRevision: 12, cursorRecordId: 'record-z', logicalClock: 12,
        recordsJson: '[1]', outboxJson: '[2]'
      };
      expect(CloudAccountStatePolicy.bind(state, 'account-a')).assertEqual(state);
    });
    it('clearsAccountAOnLogoutBeforeBindingAccountB', 0, () => {
      const stateA: CloudAccountSnapshot = {
        accountId: 'account-a', generation: 7, enabled: true,
        cursorRevision: 18, cursorRecordId: 'record-z', logicalClock: 18,
        recordsJson: '[1]', outboxJson: '[2]'
      };
      const loggedOut: CloudAccountSnapshot = CloudAccountStatePolicy.bind(stateA, '');
      const stateB: CloudAccountSnapshot = CloudAccountStatePolicy.bind(loggedOut, 'account-b');
      expect(loggedOut.accountId).assertEqual('');
      expect(loggedOut.enabled).assertFalse();
      expect(loggedOut.recordsJson).assertEqual('[]');
      expect(stateB.accountId).assertEqual('account-b');
      expect(stateB.generation).assertEqual(9);
      expect(stateB.enabled).assertFalse();
      expect(stateB.cursorRevision).assertEqual(0);
      expect(stateB.outboxJson).assertEqual('[]');
    });
    it('clearsAccountAWhenSessionSilentlyRestoresAsAccountB', 0, () => {
      const stateA: CloudAccountSnapshot = {
        accountId: 'account-a', generation: 2, enabled: true,
        cursorRevision: 6, cursorRecordId: 'record-c', logicalClock: 6,
        recordsJson: '[1]', outboxJson: '[2]'
      };
      const restoredB: CloudAccountSnapshot = CloudAccountStatePolicy.bind(stateA, 'account-b');
      expect(restoredB.accountId).assertEqual('account-b');
      expect(restoredB.generation).assertEqual(3);
      expect(restoredB.enabled).assertFalse();
      expect(restoredB.recordsJson).assertEqual('[]');
      expect(restoredB.outboxJson).assertEqual('[]');
    });
    it('serializesStateCommitAndAccountSwitchMutations', 0, async () => {
      const mutex: CloudStateMutex = new CloudStateMutex();
      const events: string[] = [];
      let releaseFirst: () => void = (): void => {};
      const first: Promise<void> = mutex.run<void>(async (): Promise<void> => {
        events.push('commit-start');
        await new Promise<void>((resolve: () => void): void => { releaseFirst = resolve; });
        events.push('commit-end');
      });
      const second: Promise<void> = mutex.run<void>(async (): Promise<void> => { events.push('switch'); });
      await Promise.resolve();
      expect(events.join(',')).assertEqual('commit-start');
      releaseFirst(); await first; await second;
      expect(events.join(',')).assertEqual('commit-start,commit-end,switch');
    });
    it('abortsWithoutAckWhenAccountChangesDuringPush', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      state.itemList = [{ operationId: 'op', recordId: 'record', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 }];
      state.recordList = [{ recordType: 'CheckinSummary', recordId: 'record', accountId: 'account-a',
        dateKey: '2026-08-08', updatedAt: 1, revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 1 }];
      const transport: FakeSyncTransport = new FakeSyncTransport();
      transport.pushResults = [{ status: 'success', retryAfterMs: 0, errorCode: 0 }];
      transport.onPush = (): void => { state.accountId = 'account-b'; state.generation = 2; state.enabled = false; };
      const result: CloudSyncResult = await new CloudSyncCoordinator(state, transport, new FakeAccountSession()).synchronize(10);
      expect(result.status).assertEqual('account_changed');
      expect(state.acknowledged).assertEqual(0);
      expect(transport.events.join(',')).assertEqual('pull,push');
    });
    it('doesNotInvokeCloudWriteWhenRealAccountChangesBeforePush', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      state.itemList = [{ operationId: 'op', recordId: 'record', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 }];
      state.recordList = [{ recordType: 'CheckinSummary', recordId: 'record', accountId: 'account-a',
        dateKey: '2026-08-08', updatedAt: 1, revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 1 }];
      const transport: FakeSyncTransport = new FakeSyncTransport();
      transport.pushResults = [{ status: 'success', retryAfterMs: 0, errorCode: 0 }];
      const session: FakeAccountSession = new FakeAccountSession();
      transport.onPull = (): void => { session.accountId = 'account-b'; };
      const result: CloudSyncResult = await new CloudSyncCoordinator(state, transport, session).synchronize(10);
      expect(result.status).assertEqual('account_changed');
      expect(transport.pushIndex).assertEqual(0);
      expect(state.acknowledged).assertEqual(0);
      expect(state.accountId).assertEqual('account-b');
      expect(state.enabled).assertFalse();
    });
    it('invalidatesRealAccountChangeAfterPullWithEmptyOutbox', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      const transport: FakeSyncTransport = new FakeSyncTransport();
      const session: FakeAccountSession = new FakeAccountSession();
      transport.onPull = (): void => { session.accountId = 'account-b'; };
      const result: CloudSyncResult = await new CloudSyncCoordinator(state, transport, session).synchronize(10);
      expect(result.status).assertEqual('account_changed');
      expect(state.committed).assertEqual(0);
      expect(state.accountId).assertEqual('account-b');
      expect(state.enabled).assertFalse();
      expect(transport.actualWrites).assertEqual(0);
    });
    it('accountBoundAdapterRejectsRaceBeforeActualWrite', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      state.itemList = [{ operationId: 'op', recordId: 'record', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 }];
      state.recordList = [{ recordType: 'CheckinSummary', recordId: 'record', accountId: 'account-a',
        dateKey: '2026-08-08', updatedAt: 1, revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 1 }];
      const session: FakeAccountSession = new FakeAccountSession();
      const transport: FakeSyncTransport = new FakeSyncTransport();
      transport.authSession = session;
      transport.onBeforeAuthenticatedWrite = (): void => { session.accountId = 'account-b'; };
      const result: CloudSyncResult = await new CloudSyncCoordinator(state, transport, session).synchronize(10);
      expect(result.status).assertEqual('account_changed');
      expect(transport.actualWrites).assertEqual(0);
      expect(state.accountId).assertEqual('account-b');
      expect(state.enabled).assertFalse();
    });
    it('pullsRemoteClockBeforePushingQueuedRecords', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      state.itemList = [{ operationId: 'one', recordId: 'r1', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 }];
      state.recordList = [{ recordType: 'CheckinSummary', recordId: 'r1', accountId: 'account-a', dateKey: 'd',
        updatedAt: 999999, revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 1 }];
      const transport: FakeSyncTransport = new FakeSyncTransport();
      transport.pushResults = [{ status: 'success', retryAfterMs: 0, errorCode: 0 }];
      await new CloudSyncCoordinator(state, transport, new FakeAccountSession()).synchronize(10);
      expect(transport.events.join(',')).assertEqual('pull,push');
    });
    it('reportsPartialWhenRetryablePushFails', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      state.itemList = [
        { operationId: 'one', recordId: 'r1', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 },
        { operationId: 'two', recordId: 'r2', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 }
      ];
      state.recordList = [
        { recordType: 'CheckinSummary', recordId: 'r1', accountId: 'account-a', dateKey: 'd', updatedAt: 1,
          revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 1 },
        { recordType: 'CheckinSummary', recordId: 'r2', accountId: 'account-a', dateKey: 'd', updatedAt: 1,
          revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 2 }
      ];
      const transport: FakeSyncTransport = new FakeSyncTransport();
      transport.pushResults = [
        { status: 'success', retryAfterMs: 0, errorCode: 0 },
        { status: 'retryable_failure', retryAfterMs: 9000, errorCode: 1008230001 }
      ];
      const result: CloudSyncResult = await new CloudSyncCoordinator(state, transport, new FakeAccountSession()).synchronize(10);
      expect(result.status).assertEqual('partial_failure');
      expect(result.pushed).assertEqual(1);
      expect(result.retryableFailures).assertEqual(1);
      expect(state.retryable).assertEqual(1);
    });
    it('surfacesPermanentPushFailure', 0, async () => {
      const state: FakeSyncRepository = new FakeSyncRepository();
      state.itemList = [{ operationId: 'one', recordId: 'r1', attempts: 0, nextAttemptAt: 0, leasedUntil: 0 }];
      state.recordList = [{ recordType: 'CheckinSummary', recordId: 'r1', accountId: 'account-a', dateKey: 'd',
        updatedAt: 1, revision: 1, deviceId: 'd', schemaVersion: 1, waterCups: 1 }];
      const transport: FakeSyncTransport = new FakeSyncTransport();
      transport.pushResults = [{ status: 'permanent_failure', retryAfterMs: 0, errorCode: 1008230002 }];
      const result: CloudSyncResult = await new CloudSyncCoordinator(state, transport, new FakeAccountSession()).synchronize(10);
      expect(result.status).assertEqual('failed');
      expect(result.permanentFailures).assertEqual(1);
      expect(state.permanent).assertEqual(1);
    it('reportsNoAuthorizationWhenEveryDomainIsDenied', 0, () => {
      const status: HealthAuthorizationStatus = {
        querySuccess: true,
        steps: false,
        restingHeartRate: false,
        sleep: false
      };
      expect(HealthSyncPolicy.hasAnyAuthorization(status)).assertFalse();
      expect(HealthSyncPolicy.hasAllAuthorizations(status)).assertFalse();
    });
    it('allowsAuthorizedDomainsWhenAuthorizationIsPartial', 0, () => {
      const status: HealthAuthorizationStatus = {
        querySuccess: true,
        steps: true,
        restingHeartRate: false,
        sleep: true
      };
      expect(HealthSyncPolicy.hasAnyAuthorization(status)).assertTrue();
      expect(HealthSyncPolicy.hasAllAuthorizations(status)).assertFalse();
    });
    it('preservesKnownAuthorizationWhenStatusQueryFails', 0, () => {
      const previous: HealthAuthorizationStatus = {
        querySuccess: true,
        steps: true,
        restingHeartRate: false,
        sleep: true
      };
      const failedQuery: HealthAuthorizationStatus = {
        querySuccess: false,
        steps: false,
        restingHeartRate: false,
        sleep: false,
        errorCode: 1002701001
      };
      const resolved: HealthAuthorizationStatus = HealthSyncPolicy.resolveAuthorization(previous, failedQuery);
      expect(resolved.steps).assertTrue();
      expect(resolved.sleep).assertTrue();
    });
    it('preservesEveryOldValueWhenAllReadsFail', 0, () => {
      const previous: HealthDisplayState = existingHealthState();
      const result: HealthMergeResult = HealthSyncPolicy.merge(previous, failedSnapshot(1002701001));
      expect(result.state.steps).assertEqual(4321);
      expect(result.state.restingHeartRate).assertEqual(61);
      expect(result.state.sleepMinutes).assertEqual(450);
      expect(result.successfulDomains).assertEqual(0);
      expect(result.failedDomains).assertEqual(3);
      expect(result.shouldPersistSteps).assertFalse();
    });
    it('acceptsRealZeroFromSuccessfulStepRead', 0, () => {
      const snapshot: HuaweiHealthSnapshot = failedSnapshot(1002701001);
      snapshot.hasSteps = true;
      snapshot.stepsStatus = { attempted: true, success: true };
      const result: HealthMergeResult = HealthSyncPolicy.merge(existingHealthState(), snapshot);
      expect(result.state.steps).assertEqual(0);
      expect(result.state.hasSteps).assertTrue();
      expect(result.successfulDomains).assertEqual(1);
      expect(result.shouldPersistSteps).assertTrue();
    });
    it('updatesSuccessfulDomainAndProtectsFailedDomains', 0, () => {
      const snapshot: HuaweiHealthSnapshot = failedSnapshot(1002701001);
      snapshot.restingHeartRate = 58;
      snapshot.hasRestingHeartRate = true;
      snapshot.dailyRestingHeartRates = [0, 0, 59, 0, 57, 0, 58];
      snapshot.restingHeartRateStatus = { attempted: true, success: true };
      snapshot.sleepStatus = { attempted: false, success: false };
      const result: HealthMergeResult = HealthSyncPolicy.merge(existingHealthState(), snapshot);
      expect(result.state.steps).assertEqual(4321);
      expect(result.state.restingHeartRate).assertEqual(58);
      expect(result.state.sleepMinutes).assertEqual(450);
      expect(result.successfulDomains).assertEqual(1);
      expect(result.failedDomains).assertEqual(1);
      expect(result.shouldPersistSteps).assertFalse();
    });
  });
}
