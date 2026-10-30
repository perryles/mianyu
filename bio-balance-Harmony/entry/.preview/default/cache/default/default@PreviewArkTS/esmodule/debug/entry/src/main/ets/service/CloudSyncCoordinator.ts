import hilog from "@ohos:hilog";
import type { CloudRecord } from '../model/CloudSyncContract';
import type { CloudOutboxItem } from '../model/CloudOutbox';
import type { CloudSyncPendingCounts, CloudSyncRepository, CloudSyncSettings } from './CloudSyncStateStore';
import type { CloudAccountSession, CloudPullResult, CloudPushResult, CloudSyncTransport } from './CloudSyncTransport';
const DOMAIN: number = 0x0000;
const TAG: string = 'CloudSync';
export interface CloudSyncResult {
    status: 'disabled' | 'success' | 'partial_failure' | 'failed' | 'account_changed';
    pushed: number;
    pulled: number;
    retryableFailures: number;
    permanentFailures: number;
}
export class CloudSyncCoordinator {
    private state: CloudSyncRepository;
    private transport: CloudSyncTransport;
    private session: CloudAccountSession;
    constructor(state: CloudSyncRepository, transport: CloudSyncTransport, session: CloudAccountSession) {
        this.state = state;
        this.transport = transport;
        this.session = session;
    }
    async synchronize(now: number = Date.now()): Promise<CloudSyncResult> {
        const settings: CloudSyncSettings = await this.state.settings();
        if (!settings.enabled || settings.accountId.length === 0)
            return this.result('disabled', 0, 0, 0, 0);
        const accountId: string = settings.accountId;
        const generation: number = settings.generation;
        let pushed: number = 0;
        let pulled: number = 0;
        let retryableFailures: number = 0;
        let permanentFailures: number = 0;
        try {
            if (!await this.state.isSessionActive(accountId, generation))
                return this.accountChanged(pushed);
            let actualAccountId: string = await this.session.currentAccountId();
            if (actualAccountId !== accountId)
                return await this.invalidateAccount(accountId, generation, actualAccountId, pushed);
            const pull: CloudPullResult = await this.transport.pullChanges(accountId, settings.cursor);
            actualAccountId = await this.session.currentAccountId();
            if (actualAccountId !== accountId)
                return await this.invalidateAccount(accountId, generation, actualAccountId, pushed);
            if (!await this.state.commitPull(accountId, generation, pull))
                return this.accountChanged(pushed);
            pulled = pull.records.length;
            const claimed: CloudOutboxItem[] = await this.state.claimDue(accountId, generation, now);
            if (!await this.state.isSessionActive(accountId, generation))
                return this.accountChanged(pushed);
            for (let index: number = 0; index < claimed.length; index++) {
                if (!await this.state.isSessionActive(accountId, generation))
                    return this.accountChanged(pushed);
                const item: CloudOutboxItem = claimed[index];
                const record: CloudRecord | undefined = await this.state.record(accountId, generation, item.recordId);
                if (record === undefined || record.accountId !== accountId)
                    return this.accountChanged(pushed);
                actualAccountId = await this.session.currentAccountId();
                if (actualAccountId !== accountId)
                    return await this.invalidateAccount(accountId, generation, actualAccountId, pushed);
                const push: CloudPushResult = await this.transport.push(record, accountId);
                if (!await this.state.isSessionActive(accountId, generation))
                    return this.accountChanged(pushed);
                if (push.status === 'account_changed') {
                    actualAccountId = await this.session.currentAccountId();
                    return await this.invalidateAccount(accountId, generation, actualAccountId, pushed);
                }
                else if (push.status === 'success') {
                    if (!await this.state.acknowledge(accountId, generation, item.operationId))
                        return this.accountChanged(pushed);
                    pushed += 1;
                }
                else if (push.status === 'retryable_failure') {
                    if (!await this.state.markRetryable(accountId, generation, item.operationId, now, push.retryAfterMs))
                        return this.accountChanged(pushed);
                    retryableFailures += 1;
                }
                else {
                    if (!await this.state.markPermanent(accountId, generation, item.operationId, push.errorCode))
                        return this.accountChanged(pushed);
                    permanentFailures += 1;
                }
            }
            const pending: CloudSyncPendingCounts = await this.state.pendingCounts(accountId, generation);
            retryableFailures = Math.max(retryableFailures, pending.retryable);
            permanentFailures = Math.max(permanentFailures, pending.permanent);
            const status: 'success' | 'partial_failure' | 'failed' = permanentFailures > 0 && pushed === 0 && pulled === 0 ?
                'failed' : (retryableFailures > 0 || permanentFailures > 0 ? 'partial_failure' : 'success');
            hilog.info(DOMAIN, TAG, 'operation=sync_incremental');
            return this.result(status, pushed, pulled, retryableFailures, permanentFailures);
        }
        catch (error) {
            hilog.warn(DOMAIN, TAG, 'operation=sync_incremental');
            return this.result('failed', pushed, 0, retryableFailures, permanentFailures);
        }
    }
    private accountChanged(pushed: number): CloudSyncResult {
        return this.result('account_changed', pushed, 0, 0, 0);
    }
    private async invalidateAccount(accountId: string, generation: number, actualAccountId: string, pushed: number): Promise<CloudSyncResult> {
        await this.state.invalidateSession(accountId, generation, actualAccountId);
        return this.accountChanged(pushed);
    }
    private result(status: 'disabled' | 'success' | 'partial_failure' | 'failed' | 'account_changed', pushed: number, pulled: number, retryableFailures: number, permanentFailures: number): CloudSyncResult {
        return { status, pushed, pulled, retryableFailures, permanentFailures };
    }
}
