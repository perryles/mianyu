export interface CloudAccountSnapshot {
  accountId: string;
  generation: number;
  enabled: boolean;
  cursorRevision: number;
  cursorRecordId: string;
  logicalClock: number;
  recordsJson: string;
  outboxJson: string;
}

export class CloudAccountStatePolicy {
  static bind(current: CloudAccountSnapshot, accountId: string): CloudAccountSnapshot {
    if (current.accountId === accountId) return current;
    return {
      accountId,
      generation: current.generation + 1,
      enabled: false,
      cursorRevision: 0,
      cursorRecordId: '',
      logicalClock: 0,
      recordsJson: '[]',
      outboxJson: '[]'
    };
  }
}
