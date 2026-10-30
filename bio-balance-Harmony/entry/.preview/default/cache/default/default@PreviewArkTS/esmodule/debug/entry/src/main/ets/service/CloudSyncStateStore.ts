import preferences from "@ohos:data.preferences";
import type common from "@ohos:app.ability.common";
import { CloudAccountStatePolicy } from "@normalized:N&&&entry/src/main/ets/model/CloudAccountState&";
import type { CloudAccountSnapshot } from "@normalized:N&&&entry/src/main/ets/model/CloudAccountState&";
import { CloudOutbox } from "@normalized:N&&&entry/src/main/ets/model/CloudOutbox&";
import type { CloudOutboxItem } from "@normalized:N&&&entry/src/main/ets/model/CloudOutbox&";
import { CloudSyncPolicy } from "@normalized:N&&&entry/src/main/ets/model/CloudSyncContract&";
import type { CloudCursor, CloudRecord } from "@normalized:N&&&entry/src/main/ets/model/CloudSyncContract&";
import type { CloudPullResult } from './CloudSyncTransport';
const STORAGE_NAME: string = 'bio_balance_cloud_sync';
export class CloudStateMutex {
    private tail: Promise<void> = Promise.resolve();
    async run<T>(operation: () => Promise<T>): Promise<T> {
        const previous: Promise<void> = this.tail;
        let release: () => void = (): void => { };
        this.tail = new Promise<void>((resolve: () => void): void => { release = resolve; });
        await previous;
        try {
            return await operation();
        }
        finally {
            release();
        }
    }
}
const CLOUD_STATE_MUTEX: CloudStateMutex = new CloudStateMutex();
export interface CloudSyncSettings {
    enabled: boolean;
    accountId: string;
    generation: number;
    cursor: CloudCursor;
    logicalClock: number;
}
export interface CloudSyncPendingCounts {
    retryable: number;
    permanent: number;
}
export interface CloudSyncRepository {
    settings(): Promise<CloudSyncSettings>;
    isSessionActive(accountId: string, generation: number): Promise<boolean>;
    invalidateSession(accountId: string, generation: number, actualAccountId: string): Promise<boolean>;
    claimDue(accountId: string, generation: number, now: number): Promise<CloudOutboxItem[]>;
    record(accountId: string, generation: number, recordId: string): Promise<CloudRecord | undefined>;
    acknowledge(accountId: string, generation: number, operationId: string): Promise<boolean>;
    markRetryable(accountId: string, generation: number, operationId: string, now: number, retryAfterMs: number): Promise<boolean>;
    markPermanent(accountId: string, generation: number, operationId: string, errorCode: number): Promise<boolean>;
    commitPull(accountId: string, generation: number, result: CloudPullResult): Promise<boolean>;
    pendingCounts(accountId: string, generation: number): Promise<CloudSyncPendingCounts>;
}
export class CloudSyncStateStore implements CloudSyncRepository {
    private context: common.Context;
    private mutex: CloudStateMutex = CLOUD_STATE_MUTEX;
    constructor(context: common.Context) { this.context = context; }
    private async store(): Promise<preferences.Preferences> {
        return preferences.getPreferences(this.context, STORAGE_NAME);
    }
    private parse<T>(raw: string, fallback: T): T {
        try {
            return raw.length > 0 ? JSON.parse(raw) as T : fallback;
        }
        catch (error) {
            return fallback;
        }
    }
    private snapshot(store: preferences.Preferences): CloudAccountSnapshot {
        return {
            accountId: store.getSync('accountId', '') as string,
            generation: store.getSync('generation', 0) as number,
            enabled: store.getSync('enabled', false) as boolean,
            cursorRevision: store.getSync('cursorRevision', 0) as number,
            cursorRecordId: store.getSync('cursorRecordId', '') as string,
            logicalClock: store.getSync('logicalClock', 0) as number,
            recordsJson: store.getSync('records', '[]') as string,
            outboxJson: store.getSync('outbox', '[]') as string
        };
    }
    private writeSnapshot(store: preferences.Preferences, value: CloudAccountSnapshot): void {
        store.putSync('accountId', value.accountId);
        store.putSync('generation', value.generation);
        store.putSync('enabled', value.enabled);
        store.putSync('cursorRevision', value.cursorRevision);
        store.putSync('cursorRecordId', value.cursorRecordId);
        store.putSync('logicalClock', value.logicalClock);
        store.putSync('records', value.recordsJson);
        store.putSync('outbox', value.outboxJson);
    }
    async settings(): Promise<CloudSyncSettings> {
        const store: preferences.Preferences = await this.store();
        const value: CloudAccountSnapshot = this.snapshot(store);
        return { enabled: value.enabled, accountId: value.accountId, generation: value.generation,
            cursor: { revision: value.cursorRevision, recordId: value.cursorRecordId }, logicalClock: value.logicalClock };
    }
    async bindAccount(accountId: string): Promise<CloudSyncSettings> {
        return this.mutex.run<CloudSyncSettings>(async (): Promise<CloudSyncSettings> => {
            const store: preferences.Preferences = await this.store();
            const bound: CloudAccountSnapshot = CloudAccountStatePolicy.bind(this.snapshot(store), accountId);
            this.writeSnapshot(store, bound);
            await store.flush();
            return { enabled: bound.enabled, accountId: bound.accountId, generation: bound.generation,
                cursor: { revision: bound.cursorRevision, recordId: bound.cursorRecordId }, logicalClock: bound.logicalClock };
        });
    }
    async deviceId(): Promise<string> {
        const store: preferences.Preferences = await this.store();
        let value: string = store.getSync('deviceId', '') as string;
        if (value.length === 0) {
            value = `harmony_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
            store.putSync('deviceId', value);
            await store.flush();
        }
        return value;
    }
    async isSessionActive(accountId: string, generation: number): Promise<boolean> {
        const current: CloudSyncSettings = await this.settings();
        return current.enabled && current.accountId === accountId && current.generation === generation;
    }
    async setEnabled(accountId: string, generation: number, enabled: boolean): Promise<boolean> {
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (value.accountId !== accountId || value.generation !== generation || accountId.length === 0)
                return false;
            store.putSync('enabled', enabled);
            await store.flush();
            return true;
        });
    }
    async invalidateSession(accountId: string, generation: number, actualAccountId: string): Promise<boolean> {
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const current: CloudAccountSnapshot = this.snapshot(store);
            if (current.accountId !== accountId || current.generation !== generation)
                return false;
            const bound: CloudAccountSnapshot = CloudAccountStatePolicy.bind(current, actualAccountId);
            this.writeSnapshot(store, bound);
            await store.flush();
            return true;
        });
    }
    async nextRevision(accountId: string, generation: number): Promise<number> {
        return this.mutex.run<number>(async (): Promise<number> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return 0;
            const next: number = value.logicalClock + 1;
            store.putSync('logicalClock', next);
            await store.flush();
            return next;
        });
    }
    async cachedRecords(accountId: string, generation: number): Promise<CloudRecord[]> {
        const store: preferences.Preferences = await this.store();
        const value: CloudAccountSnapshot = this.snapshot(store);
        if (value.accountId !== accountId || value.generation !== generation)
            return [];
        return this.parse<CloudRecord[]>(value.recordsJson, []);
    }
    async enqueue(accountId: string, generation: number, record: CloudRecord, now: number = Date.now()): Promise<boolean> {
        if (record.accountId !== accountId)
            return false;
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return false;
            const records: CloudRecord[] = this.parse<CloudRecord[]>(value.recordsJson, []);
            this.mergeRecord(records, record);
            const items: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(value.outboxJson, []);
            const existing: number = items.findIndex((item: CloudOutboxItem): boolean => item.recordId === record.recordId);
            const operation: CloudOutboxItem = { operationId: `${record.recordId}_${record.revision}_${record.deviceId}`,
                recordId: record.recordId, attempts: 0, nextAttemptAt: now, leasedUntil: 0, state: 'pending' };
            if (existing >= 0)
                items[existing] = operation;
            else
                items.push(operation);
            store.putSync('records', JSON.stringify(records));
            store.putSync('outbox', JSON.stringify(items));
            await store.flush();
            return true;
        });
    }
    async claimDue(accountId: string, generation: number, now: number): Promise<CloudOutboxItem[]> {
        return this.mutex.run<CloudOutboxItem[]>(async (): Promise<CloudOutboxItem[]> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return [];
            const items: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(store.getSync('outbox', '[]') as string, []);
            const claimed: CloudOutboxItem[] = CloudOutbox.claimDue(items, now, 30000, 20);
            store.putSync('outbox', JSON.stringify(items));
            await store.flush();
            return claimed;
        });
    }
    async record(accountId: string, generation: number, recordId: string): Promise<CloudRecord | undefined> {
        return this.mutex.run<CloudRecord | undefined>(async (): Promise<CloudRecord | undefined> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return undefined;
            const records: CloudRecord[] = this.parse<CloudRecord[]>(store.getSync('records', '[]') as string, []);
            const index: number = records.findIndex((record: CloudRecord): boolean => record.recordId === recordId && record.accountId === accountId);
            if (index < 0)
                return undefined;
            return records[index];
        });
    }
    async acknowledge(accountId: string, generation: number, operationId: string): Promise<boolean> {
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return false;
            const items: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(store.getSync('outbox', '[]') as string, []);
            store.putSync('outbox', JSON.stringify(CloudOutbox.acknowledge(items, operationId)));
            await store.flush();
            return true;
        });
    }
    async markRetryable(accountId: string, generation: number, operationId: string, now: number, retryAfterMs: number): Promise<boolean> {
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return false;
            const items: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(store.getSync('outbox', '[]') as string, []);
            store.putSync('outbox', JSON.stringify(CloudOutbox.markRetryable(items, operationId, now, retryAfterMs)));
            await store.flush();
            return true;
        });
    }
    async markPermanent(accountId: string, generation: number, operationId: string, errorCode: number): Promise<boolean> {
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return false;
            const items: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(store.getSync('outbox', '[]') as string, []);
            store.putSync('outbox', JSON.stringify(CloudOutbox.markPermanent(items, operationId, errorCode)));
            await store.flush();
            return true;
        });
    }
    async commitPull(accountId: string, generation: number, result: CloudPullResult): Promise<boolean> {
        return this.mutex.run<boolean>(async (): Promise<boolean> => {
            const store: preferences.Preferences = await this.store();
            const value: CloudAccountSnapshot = this.snapshot(store);
            if (!value.enabled || value.accountId !== accountId || value.generation !== generation)
                return false;
            const records: CloudRecord[] = this.parse<CloudRecord[]>(store.getSync('records', '[]') as string, []);
            const outbox: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(store.getSync('outbox', '[]') as string, []);
            for (let index: number = 0; index < result.records.length; index++) {
                const record: CloudRecord = result.records[index];
                if (record.accountId !== accountId)
                    return false;
                const hasLocalOperation: boolean = outbox.some((item: CloudOutboxItem): boolean => item.recordId === record.recordId);
                if (!hasLocalOperation)
                    this.mergeRecord(records, record);
            }
            let currentClock: number = Math.max(store.getSync('logicalClock', 0) as number, result.maxRevision);
            for (let index: number = 0; index < outbox.length; index++) {
                const recordIndex: number = records.findIndex((record: CloudRecord): boolean => record.recordId === outbox[index].recordId && record.accountId === accountId);
                if (recordIndex >= 0 && CloudSyncPolicy.needsRebase(result.maxRevision, records[recordIndex].revision)) {
                    const rebased: number = CloudSyncPolicy.nextLogicalRevision(currentClock, records[recordIndex].revision);
                    records[recordIndex].revision = rebased;
                    currentClock = rebased;
                }
            }
            store.putSync('records', JSON.stringify(records));
            store.putSync('cursorRevision', result.cursor.revision);
            store.putSync('cursorRecordId', result.cursor.recordId);
            store.putSync('logicalClock', currentClock);
            await store.flush();
            return true;
        });
    }
    async pendingCounts(accountId: string, generation: number): Promise<CloudSyncPendingCounts> {
        if (!await this.isSessionActive(accountId, generation))
            return { retryable: 0, permanent: 0 };
        const store: preferences.Preferences = await this.store();
        const items: CloudOutboxItem[] = this.parse<CloudOutboxItem[]>(store.getSync('outbox', '[]') as string, []);
        let retryable: number = 0;
        let permanent: number = 0;
        items.forEach((item: CloudOutboxItem): void => {
            if (item.state === 'permanent_failure')
                permanent += 1;
            else
                retryable += 1;
        });
        return { retryable, permanent };
    }
    private mergeRecord(records: CloudRecord[], incoming: CloudRecord): void {
        const index: number = records.findIndex((record: CloudRecord): boolean => record.recordId === incoming.recordId);
        if (index < 0)
            records.push(incoming);
        else
            records[index] = CloudSyncPolicy.resolveConflict(records[index], incoming);
    }
}
