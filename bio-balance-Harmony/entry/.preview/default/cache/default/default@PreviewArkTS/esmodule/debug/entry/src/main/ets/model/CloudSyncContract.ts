export type CloudRecordType = 'DailyStepsSummary' | 'DailyRestingHeartRateSummary' | 'SleepSessionSummary' | 'CheckinSummary' | 'UserPreference';
// This input is deliberately broader than CloudRecord so the boundary can discard
// locally held sensitive values instead of ever serializing the local model wholesale.
export interface CloudRecordInput {
    recordType: string;
    recordId: string;
    accountId: string;
    dateKey: string;
    updatedAt: number;
    revision: number;
    deviceId: string;
    schemaVersion: number;
    steps?: number;
    restingHeartRate?: number;
    durationMinutes?: number;
    sleepScore?: number;
    deepMinutes?: number;
    shallowMinutes?: number;
    dreamMinutes?: number;
    awakeMinutes?: number;
    moodCode?: number;
    waterCups?: number;
    dailyStepGoal?: number;
    notificationEnabled?: boolean;
    medicationName?: string;
    medicationDose?: string;
    symptomText?: string;
    freeText?: string;
}
export interface CloudRecord {
    recordType: CloudRecordType;
    recordId: string;
    accountId: string;
    dateKey: string;
    updatedAt: number;
    revision: number;
    deviceId: string;
    schemaVersion: number;
    steps?: number;
    restingHeartRate?: number;
    durationMinutes?: number;
    sleepScore?: number;
    deepMinutes?: number;
    shallowMinutes?: number;
    dreamMinutes?: number;
    awakeMinutes?: number;
    moodCode?: number;
    waterCups?: number;
    dailyStepGoal?: number;
    notificationEnabled?: boolean;
}
export interface CloudCursor {
    revision: number;
    recordId: string;
}
export class CloudSyncPolicy {
    static sanitize(input: CloudRecordInput): CloudRecord | undefined {
        if (!CloudSyncPolicy.hasValidEnvelope(input)) {
            return undefined;
        }
        const base: CloudRecord = {
            recordType: input.recordType as CloudRecordType,
            recordId: input.recordId,
            accountId: input.accountId,
            dateKey: input.dateKey,
            updatedAt: input.updatedAt,
            revision: input.revision,
            deviceId: input.deviceId,
            schemaVersion: 1
        };
        if (input.recordType === 'DailyStepsSummary' && CloudSyncPolicy.isNonNegative(input.steps)) {
            base.steps = input.steps;
            return base;
        }
        if (input.recordType === 'DailyRestingHeartRateSummary' && CloudSyncPolicy.isNonNegative(input.restingHeartRate)) {
            base.restingHeartRate = input.restingHeartRate;
            return base;
        }
        if (input.recordType === 'SleepSessionSummary' && CloudSyncPolicy.isNonNegative(input.durationMinutes)) {
            base.durationMinutes = input.durationMinutes;
            if (CloudSyncPolicy.isNonNegative(input.sleepScore))
                base.sleepScore = input.sleepScore;
            if (CloudSyncPolicy.isNonNegative(input.deepMinutes))
                base.deepMinutes = input.deepMinutes;
            if (CloudSyncPolicy.isNonNegative(input.shallowMinutes))
                base.shallowMinutes = input.shallowMinutes;
            if (CloudSyncPolicy.isNonNegative(input.dreamMinutes))
                base.dreamMinutes = input.dreamMinutes;
            if (CloudSyncPolicy.isNonNegative(input.awakeMinutes))
                base.awakeMinutes = input.awakeMinutes;
            return base;
        }
        if (input.recordType === 'CheckinSummary') {
            if (input.moodCode !== undefined)
                base.moodCode = Math.max(0, Math.min(5, input.moodCode));
            if (CloudSyncPolicy.isNonNegative(input.waterCups))
                base.waterCups = input.waterCups;
            return base;
        }
        if (input.recordType === 'UserPreference') {
            if (CloudSyncPolicy.isNonNegative(input.dailyStepGoal))
                base.dailyStepGoal = input.dailyStepGoal;
            if (input.notificationEnabled !== undefined)
                base.notificationEnabled = input.notificationEnabled;
            return base;
        }
        return undefined;
    }
    static resolveConflict(local: CloudRecord, remote: CloudRecord): CloudRecord {
        if (remote.revision !== local.revision)
            return remote.revision > local.revision ? remote : local;
        return remote.deviceId > local.deviceId ? remote : local;
    }
    static isAfterCursor(revision: number, recordId: string, cursor: CloudCursor): boolean {
        return revision > cursor.revision || (revision === cursor.revision && recordId > cursor.recordId);
    }
    static advanceCursor(cursor: CloudCursor, revision: number, recordId: string): CloudCursor {
        if (!CloudSyncPolicy.isAfterCursor(revision, recordId, cursor))
            return cursor;
        return { revision, recordId };
    }
    static cloudStorageRecordId(accountId: string, logicalRecordId: string): string {
        return `a${accountId.length}:${accountId}:${logicalRecordId}`;
    }
    static logicalRecordId(accountId: string, storageRecordId: string): string | undefined {
        const prefix: string = `a${accountId.length}:${accountId}:`;
        return storageRecordId.startsWith(prefix) ? storageRecordId.substring(prefix.length) : undefined;
    }
    static nextLogicalRevision(observedClock: number, candidateRevision: number): number {
        return Math.max(observedClock, candidateRevision) + 1;
    }
    static needsRebase(remoteFloor: number, candidateRevision: number): boolean {
        return candidateRevision <= remoteFloor;
    }
    static nextRetryDelayMs(attempt: number): number {
        const safeAttempt: number = Math.max(0, Math.min(20, attempt));
        return Math.min(3600000, 5000 * Math.pow(2, safeAttempt));
    }
    private static hasValidEnvelope(input: CloudRecordInput): boolean {
        const knownType: boolean = input.recordType === 'DailyStepsSummary' ||
            input.recordType === 'DailyRestingHeartRateSummary' || input.recordType === 'SleepSessionSummary' ||
            input.recordType === 'CheckinSummary' || input.recordType === 'UserPreference';
        return knownType && input.recordId.length > 0 && input.accountId.length > 0 && input.dateKey.length > 0 &&
            input.deviceId.length > 0 && input.updatedAt >= 0 && input.revision >= 0 && input.schemaVersion === 1;
    }
    private static isNonNegative(value: number | undefined): boolean {
        return value !== undefined && Number.isFinite(value) && value >= 0;
    }
}
