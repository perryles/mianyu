import { HealthSyncPolicy } from './HealthSyncPolicy';
import type {
  HealthAuthorizationStatus,
  HealthDisplayState,
  HealthDomainReadStatus,
  HuaweiHealthSnapshot
} from './HealthSyncPolicy';

/**
 * Per-domain read presentation state used by Index and local tests.
 * It tracks authorization, the latest read attempt and stale-old-value status
 * without exposing raw health details to logs or remote storage.
 */
export interface HealthDomainReadState {
  authorized: boolean;
  attempted: boolean;
  success: boolean;
  stale: boolean;
  errorCode: number;
  lastSuccessAt: number;
}

export interface HealthSnapshotProvider {
  readTodaySnapshot(authorizationStatus: HealthAuthorizationStatus): Promise<HuaweiHealthSnapshot>;
}

export interface HealthStepStore {
  saveSteps(steps: number, hasSteps: boolean): void;
}

export interface HealthCoordinatorRequest {
  authorizationStatus: HealthAuthorizationStatus;
  previousState: HealthDisplayState;
  previousStepsReadState: HealthDomainReadState;
  previousRestingHeartRateReadState: HealthDomainReadState;
  previousSleepReadState: HealthDomainReadState;
  previousSyncTimestamp: number;
}

export interface HealthRefreshResult {
  state: HealthDisplayState;
  stepsReadState: HealthDomainReadState;
  restingHeartRateReadState: HealthDomainReadState;
  sleepReadState: HealthDomainReadState;
  syncTimestamp?: number;
  shouldPersistSteps: boolean;
  successfulDomains: number;
  failedDomains: number;
  statusText: string;
}

/**
 * Coordinate a snapshot read, selective merge and page-level read-state update.
 * The provider and step store are injected so local tests can cover mixed
 * success/failure behavior without Health Service Kit or Preferences.
 */
export class HealthCoordinator {
  private provider: HealthSnapshotProvider;
  private stepStore: HealthStepStore;

  constructor(provider: HealthSnapshotProvider, stepStore: HealthStepStore) {
    this.provider = provider;
    this.stepStore = stepStore;
  }

  static initialDomainState(): HealthDomainReadState {
    return {
      authorized: false,
      attempted: false,
      success: false,
      stale: false,
      errorCode: 0,
      lastSuccessAt: 0
    };
  }

  static updateAuthorization(previous: HealthDomainReadState, authorized: boolean): HealthDomainReadState {
    if (!authorized) {
      return HealthCoordinator.initialDomainState();
    }
    return {
      authorized: true,
      attempted: previous.attempted,
      success: previous.success,
      stale: previous.stale,
      errorCode: previous.errorCode,
      lastSuccessAt: previous.lastSuccessAt
    };
  }

  async refresh(request: HealthCoordinatorRequest): Promise<HealthRefreshResult> {
    const snapshot: HuaweiHealthSnapshot = await this.provider.readTodaySnapshot(request.authorizationStatus);
    const mergeResult = HealthSyncPolicy.merge(request.previousState, snapshot);
    const stepsReadState: HealthDomainReadState = this.resolveDomainState(
      request.authorizationStatus.steps, snapshot.stepsStatus, request.previousStepsReadState, snapshot.updatedAt);
    const restingHeartRateReadState: HealthDomainReadState = this.resolveDomainState(
      request.authorizationStatus.restingHeartRate,
      snapshot.restingHeartRateStatus, request.previousRestingHeartRateReadState, snapshot.updatedAt);
    const sleepReadState: HealthDomainReadState = this.resolveDomainState(
      request.authorizationStatus.sleep, snapshot.sleepStatus, request.previousSleepReadState, snapshot.updatedAt);
    const syncTimestamp: number | undefined =
      mergeResult.successfulDomains > 0 && mergeResult.failedDomains === 0 ? snapshot.updatedAt : undefined;
    const statusText: string = HealthCoordinator.statusText(
      request.authorizationStatus, mergeResult.successfulDomains, mergeResult.failedDomains);

    if (mergeResult.shouldPersistSteps) {
      this.stepStore.saveSteps(mergeResult.state.steps, mergeResult.state.hasSteps);
    }

    return {
      state: mergeResult.state,
      stepsReadState: stepsReadState,
      restingHeartRateReadState: restingHeartRateReadState,
      sleepReadState: sleepReadState,
      syncTimestamp: syncTimestamp,
      shouldPersistSteps: mergeResult.shouldPersistSteps,
      successfulDomains: mergeResult.successfulDomains,
      failedDomains: mergeResult.failedDomains,
      statusText: statusText
    };
  }

  private resolveDomainState(authorized: boolean,
    readStatus: HealthDomainReadStatus,
    previous: HealthDomainReadState,
    timestamp: number): HealthDomainReadState {
    if (!authorized) {
      return HealthCoordinator.initialDomainState();
    }
    if (readStatus.success) {
      return {
        authorized: true,
        attempted: true,
        success: true,
        stale: false,
        errorCode: 0,
        lastSuccessAt: timestamp
      };
    }
    if (readStatus.attempted) {
      return {
        authorized: true,
        attempted: true,
        success: false,
        stale: true,
        errorCode: readStatus.errorCode ?? 0,
        lastSuccessAt: previous.lastSuccessAt
      };
    }
    return {
      authorized: true,
      attempted: false,
      success: false,
      stale: false,
      errorCode: 0,
      lastSuccessAt: previous.lastSuccessAt
    };
  }

  private static statusText(status: HealthAuthorizationStatus,
    successfulDomains: number, failedDomains: number): string {
    if (failedDomains > 0) {
      return successfulDomains > 0 ? '部分健康数据读取失败，已保留原有数据' : '读取健康数据失败，已保留原有数据';
    }
    if (successfulDomains > 0) {
      return HealthSyncPolicy.hasAllAuthorizations(status) ? '已同步华为运动健康数据' : '已同步已授权的运动健康数据';
    }
    return '尚未同步健康数据';
  }
}
