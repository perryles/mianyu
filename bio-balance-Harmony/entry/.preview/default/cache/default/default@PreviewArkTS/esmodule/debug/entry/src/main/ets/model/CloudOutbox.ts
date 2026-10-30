import { CloudSyncPolicy } from "@normalized:N&&&entry/src/main/ets/model/CloudSyncContract&";
export interface CloudOutboxItem {
    operationId: string;
    recordId: string;
    attempts: number;
    nextAttemptAt: number;
    leasedUntil: number;
    state?: 'pending' | 'permanent_failure';
    errorCode?: number;
}
export class CloudOutbox {
    static claimDue(items: CloudOutboxItem[], now: number, leaseMs: number, limit: number): CloudOutboxItem[] {
        const claimed: CloudOutboxItem[] = [];
        for (let index: number = 0; index < items.length && claimed.length < limit; index++) {
            const item: CloudOutboxItem = items[index];
            if ((item.state === undefined || item.state === 'pending') && item.nextAttemptAt <= now && item.leasedUntil <= now) {
                item.leasedUntil = now + leaseMs;
                claimed.push(item);
            }
        }
        return claimed;
    }
    static acknowledge(items: CloudOutboxItem[], operationId: string): CloudOutboxItem[] {
        return items.filter((item: CloudOutboxItem): boolean => item.operationId !== operationId);
    }
    static markFailed(items: CloudOutboxItem[], operationId: string, now: number): CloudOutboxItem[] {
        for (let index: number = 0; index < items.length; index++) {
            const item: CloudOutboxItem = items[index];
            if (item.operationId === operationId) {
                item.nextAttemptAt = now + CloudSyncPolicy.nextRetryDelayMs(item.attempts);
                item.attempts += 1;
                item.leasedUntil = 0;
            }
        }
        return items;
    }
    static markRetryable(items: CloudOutboxItem[], operationId: string, now: number, retryAfterMs: number): CloudOutboxItem[] {
        for (let index: number = 0; index < items.length; index++) {
            const item: CloudOutboxItem = items[index];
            if (item.operationId === operationId) {
                const policyDelay: number = CloudSyncPolicy.nextRetryDelayMs(item.attempts);
                item.nextAttemptAt = now + Math.max(policyDelay, retryAfterMs);
                item.attempts += 1;
                item.leasedUntil = 0;
                item.state = 'pending';
            }
        }
        return items;
    }
    static markPermanent(items: CloudOutboxItem[], operationId: string, errorCode: number): CloudOutboxItem[] {
        for (let index: number = 0; index < items.length; index++) {
            const item: CloudOutboxItem = items[index];
            if (item.operationId === operationId) {
                item.leasedUntil = 0;
                item.state = 'permanent_failure';
                item.errorCode = errorCode;
            }
        }
        return items;
    }
}
