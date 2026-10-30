import { CloudCursor, CloudRecord } from '../model/CloudSyncContract';

export interface CloudPushResult {
  status: 'success' | 'retryable_failure' | 'permanent_failure' | 'account_changed';
  retryAfterMs: number;
  errorCode: number;
}

export interface CloudPullResult {
  records: CloudRecord[];
  cursor: CloudCursor;
  maxRevision: number;
}

export interface CloudAccountSession {
  currentAccountId(): Promise<string>;
}

export interface CloudSyncTransport {
  push(record: CloudRecord, expectedAccountId: string): Promise<CloudPushResult>;
  pullChanges(accountId: string, cursor: CloudCursor): Promise<CloudPullResult>;
}
