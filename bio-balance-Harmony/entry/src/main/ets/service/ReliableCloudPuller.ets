import { CloudCursor, CloudRecord, CloudSyncPolicy } from '../model/CloudSyncContract';
import { CloudPullResult } from './CloudSyncTransport';

export interface CloudQueryRow {
  physicalRecordId: string;
  revision: number;
  record?: CloudRecord;
}

export interface CloudQueryAdapter {
  queryAfter(accountId: string, cursor: CloudCursor, limit: number): Promise<CloudQueryPage>;
}

export interface CloudQueryPage {
  rows: CloudQueryRow[];
  hasMore: boolean;
}

export interface CompoundQueryExecutor {
  querySameRevision(accountId: string, cursor: CloudCursor, limit: number): Promise<CloudQueryRow[]>;
  queryLaterRevisions(accountId: string, revision: number, limit: number): Promise<CloudQueryRow[]>;
}

export class CompoundCloudQueryAdapter implements CloudQueryAdapter {
  private executor: CompoundQueryExecutor;

  constructor(executor: CompoundQueryExecutor) { this.executor = executor; }

  async queryAfter(accountId: string, cursor: CloudCursor, limit: number): Promise<CloudQueryPage> {
    const same: CloudQueryRow[] = await this.executor.querySameRevision(accountId, cursor, limit);
    let rows: CloudQueryRow[] = same;
    if (same.length < limit) {
      const later: CloudQueryRow[] = await this.executor.queryLaterRevisions(accountId, cursor.revision,
        limit - same.length);
      rows = same.concat(later);
    }
    return { rows, hasMore: rows.length === limit };
  }
}

export class ReliableCloudPuller {
  private adapter: CloudQueryAdapter;
  private pageSize: number;

  constructor(adapter: CloudQueryAdapter, pageSize: number = 100) {
    this.adapter = adapter; this.pageSize = pageSize;
  }

  async pullChanges(accountId: string, savedCursor: CloudCursor): Promise<CloudPullResult> {
    // Cloud DB has no server change token. Full overlap replay is the only finite-data protocol that cannot
    // miss a record arriving later below a previously observed client revision/recordId high-water mark.
    let cursor: CloudCursor = { revision: 0, recordId: '' };
    const records: CloudRecord[] = [];
    const seen: string[] = [];
    let more: boolean = true;
    while (more) {
      const page: CloudQueryPage = await this.adapter.queryAfter(accountId, cursor, this.pageSize);
      for (let index: number = 0; index < page.rows.length; index++) {
        const row: CloudQueryRow = page.rows[index];
        cursor = CloudSyncPolicy.advanceCursor(cursor, row.revision, row.physicalRecordId);
        const key: string = `${row.revision}:${row.physicalRecordId}`;
        if (row.record !== undefined && !seen.includes(key)) { seen.push(key); records.push(row.record); }
      }
      more = page.hasMore;
    }
    const maxRevision: number = Math.max(savedCursor.revision, cursor.revision);
    return { records, cursor, maxRevision };
  }
}
