import { cloudDatabase } from '@kit.CloudFoundationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CloudCursor, CloudRecord, CloudRecordInput, CloudSyncPolicy } from '../model/CloudSyncContract';
import { CloudAccountSession, CloudPullResult, CloudPushResult, CloudSyncTransport } from './CloudSyncTransport';
import { CloudQueryAdapter, CloudQueryRow, CompoundCloudQueryAdapter,
  CompoundQueryExecutor, ReliableCloudPuller } from './ReliableCloudPuller';

const ZONE_NAME: string = 'mianyu_sync';

export class MianyuSyncRecord extends cloudDatabase.DatabaseObject {
  recordId: string = '';
  recordType: string = '';
  accountId: string = '';
  dateKey: string = '';
  updatedAt: number = 0;
  revision: number = 0;
  deviceId: string = '';
  schemaVersion: number = 1;
  steps: number = -1;
  restingHeartRate: number = -1;
  durationMinutes: number = -1;
  sleepScore: number = -1;
  deepMinutes: number = -1;
  shallowMinutes: number = -1;
  dreamMinutes: number = -1;
  awakeMinutes: number = -1;
  moodCode: number = -1;
  waterCups: number = -1;
  dailyStepGoal: number = -1;
  notificationEnabled: boolean = false;
  hasNotificationEnabled: boolean = false;

  naturalbase_ClassName(): string {
    return 'MianyuSyncRecord';
  }
}

const PAGE_SIZE: number = 100;

export class AgcCloudSyncTransport implements CloudSyncTransport, CompoundQueryExecutor {
  private zone: cloudDatabase.DatabaseZone = cloudDatabase.zone(ZONE_NAME);
  private session: CloudAccountSession;
  private puller: ReliableCloudPuller;
  private queryAdapter: CloudQueryAdapter;

  constructor(session: CloudAccountSession) {
    this.session = session; this.queryAdapter = new CompoundCloudQueryAdapter(this);
    this.puller = new ReliableCloudPuller(this.queryAdapter, PAGE_SIZE);
  }

  async push(record: CloudRecord, expectedAccountId: string): Promise<CloudPushResult> {
    try {
      if (record.accountId !== expectedAccountId || await this.session.currentAccountId() !== expectedAccountId)
        return { status: 'account_changed', retryAfterMs: 0, errorCode: 1008230010 };
      const count: number = await this.zone.upsert<MianyuSyncRecord>(this.toEntity(record));
      if (count === 1) return { status: 'success', retryAfterMs: 0, errorCode: 0 };
      return { status: 'retryable_failure', retryAfterMs: 0, errorCode: 1008230009 };
    } catch (error) {
      const code: number = (error as BusinessError).code;
      const retryable: boolean = code === 1008230001 || code === 1008230009 || code === 1008231001;
      return { status: retryable ? 'retryable_failure' : 'permanent_failure', retryAfterMs: 0, errorCode: code };
    }
  }

  async pullChanges(accountId: string, cursor: CloudCursor): Promise<CloudPullResult> {
    return this.puller.pullChanges(accountId, cursor);
  }

  async querySameRevision(accountId: string, cursor: CloudCursor, limit: number): Promise<CloudQueryRow[]> {
      const sameRevision: cloudDatabase.DatabaseQuery<MianyuSyncRecord> =
        new cloudDatabase.DatabaseQuery<MianyuSyncRecord>(MianyuSyncRecord)
          .equalTo('accountId', accountId).and().equalTo('revision', cursor.revision).and()
          .greaterThan('recordId', cursor.recordId).orderByAsc('recordId').limit(limit);
      const entities: MianyuSyncRecord[] = await this.zone.query<MianyuSyncRecord>(sameRevision);
      return this.toRows(accountId, entities);
  }

  async queryLaterRevisions(accountId: string, revision: number, limit: number): Promise<CloudQueryRow[]> {
      const later: cloudDatabase.DatabaseQuery<MianyuSyncRecord> =
        new cloudDatabase.DatabaseQuery<MianyuSyncRecord>(MianyuSyncRecord)
          .equalTo('accountId', accountId).and().greaterThan('revision', revision)
          .orderByAsc('revision').orderByAsc('recordId').limit(limit);
      const entities: MianyuSyncRecord[] = await this.zone.query<MianyuSyncRecord>(later);
      return this.toRows(accountId, entities);
  }

  private toRows(accountId: string, entities: MianyuSyncRecord[]): CloudQueryRow[] {
      const rows: CloudQueryRow[] = [];
      for (let index: number = 0; index < entities.length; index++) {
        const entity: MianyuSyncRecord = entities[index];
        const logicalRecordId: string | undefined = CloudSyncPolicy.logicalRecordId(accountId, entity.recordId);
        if (logicalRecordId === undefined) {
          rows.push({ physicalRecordId: entity.recordId, revision: entity.revision }); continue;
        }
        const record: CloudRecord | undefined = CloudSyncPolicy.sanitize(this.toInput(entity, logicalRecordId));
        if (record !== undefined && record.accountId === accountId)
          rows.push({ physicalRecordId: entity.recordId, revision: entity.revision, record });
      }
      return rows;
  }

  private toEntity(record: CloudRecord): MianyuSyncRecord {
    const entity: MianyuSyncRecord = new MianyuSyncRecord();
    entity.recordId = CloudSyncPolicy.cloudStorageRecordId(record.accountId, record.recordId);
    entity.recordType = record.recordType; entity.accountId = record.accountId;
    entity.dateKey = record.dateKey; entity.updatedAt = record.updatedAt; entity.revision = record.revision;
    entity.deviceId = record.deviceId; entity.schemaVersion = record.schemaVersion;
    entity.steps = record.steps ?? -1; entity.restingHeartRate = record.restingHeartRate ?? -1;
    entity.durationMinutes = record.durationMinutes ?? -1; entity.sleepScore = record.sleepScore ?? -1;
    entity.deepMinutes = record.deepMinutes ?? -1; entity.shallowMinutes = record.shallowMinutes ?? -1;
    entity.dreamMinutes = record.dreamMinutes ?? -1; entity.awakeMinutes = record.awakeMinutes ?? -1;
    entity.moodCode = record.moodCode ?? -1; entity.waterCups = record.waterCups ?? -1;
    entity.dailyStepGoal = record.dailyStepGoal ?? -1;
    if (record.notificationEnabled !== undefined) {
      entity.notificationEnabled = record.notificationEnabled;
      entity.hasNotificationEnabled = true;
    }
    return entity;
  }

  private toInput(entity: MianyuSyncRecord, logicalRecordId: string): CloudRecordInput {
    const input: CloudRecordInput = {
      recordType: entity.recordType, recordId: logicalRecordId, accountId: entity.accountId,
      dateKey: entity.dateKey, updatedAt: entity.updatedAt, revision: entity.revision,
      deviceId: entity.deviceId, schemaVersion: entity.schemaVersion
    };
    if (entity.steps >= 0) input.steps = entity.steps;
    if (entity.restingHeartRate >= 0) input.restingHeartRate = entity.restingHeartRate;
    if (entity.durationMinutes >= 0) input.durationMinutes = entity.durationMinutes;
    if (entity.sleepScore >= 0) input.sleepScore = entity.sleepScore;
    if (entity.deepMinutes >= 0) input.deepMinutes = entity.deepMinutes;
    if (entity.shallowMinutes >= 0) input.shallowMinutes = entity.shallowMinutes;
    if (entity.dreamMinutes >= 0) input.dreamMinutes = entity.dreamMinutes;
    if (entity.awakeMinutes >= 0) input.awakeMinutes = entity.awakeMinutes;
    if (entity.moodCode >= 0) input.moodCode = entity.moodCode;
    if (entity.waterCups >= 0) input.waterCups = entity.waterCups;
    if (entity.dailyStepGoal >= 0) input.dailyStepGoal = entity.dailyStepGoal;
    if (entity.hasNotificationEnabled) input.notificationEnabled = entity.notificationEnabled;
    return input;
  }
}
