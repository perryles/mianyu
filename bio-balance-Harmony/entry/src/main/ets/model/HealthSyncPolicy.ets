/**
 * Health Service Kit-independent contracts used by the service, UI and local tests.
 * Raw health details remain in memory and are never logged or uploaded.
 */
export interface HealthAuthorizationStatus {
  querySuccess: boolean;
  steps: boolean;
  restingHeartRate: boolean;
  sleep: boolean;
  errorCode?: number;
}

export interface HealthDomainReadStatus {
  attempted: boolean;
  success: boolean;
  errorCode?: number;
}

export interface SleepStages {
  deepMinutes: number;
  shallowMinutes: number;
  dreamMinutes: number;
  awakeMinutes: number;
  totalMinutes: number;
  hasDetails: boolean;
}

export interface HealthDisplayState {
  steps: number;
  restingHeartRate: number;
  sleepMinutes: number;
  sleepScore: number;
  hasSteps: boolean;
  hasRestingHeartRate: boolean;
  hasSleep: boolean;
  dailySteps: number[];
  dailyStepDates: string[];
  dailyRestingHeartRates: number[];
  dailySleepMinutes: number[];
  dailySleepScores: number[];
  lastSleepStages: SleepStages;
}

export interface HuaweiHealthSnapshot extends HealthDisplayState {
  stepsStatus: HealthDomainReadStatus;
  restingHeartRateStatus: HealthDomainReadStatus;
  sleepStatus: HealthDomainReadStatus;
  updatedAt: number;
}

export interface HealthMergeResult {
  state: HealthDisplayState;
  successfulDomains: number;
  failedDomains: number;
  shouldPersistSteps: boolean;
}

export class HealthSyncPolicy {
  static hasAnyAuthorization(status: HealthAuthorizationStatus): boolean {
    return status.querySuccess && (status.steps || status.restingHeartRate || status.sleep);
  }

  static hasAllAuthorizations(status: HealthAuthorizationStatus): boolean {
    return status.querySuccess && status.steps && status.restingHeartRate && status.sleep;
  }

  static resolveAuthorization(previous: HealthAuthorizationStatus,
    latest: HealthAuthorizationStatus): HealthAuthorizationStatus {
    return latest.querySuccess ? latest : previous;
  }

  static merge(previous: HealthDisplayState, snapshot: HuaweiHealthSnapshot): HealthMergeResult {
    const state: HealthDisplayState = {
      steps: previous.steps,
      restingHeartRate: previous.restingHeartRate,
      sleepMinutes: previous.sleepMinutes,
      sleepScore: previous.sleepScore,
      hasSteps: previous.hasSteps,
      hasRestingHeartRate: previous.hasRestingHeartRate,
      hasSleep: previous.hasSleep,
      dailySteps: previous.dailySteps,
      dailyStepDates: previous.dailyStepDates,
      dailyRestingHeartRates: previous.dailyRestingHeartRates,
      dailySleepMinutes: previous.dailySleepMinutes,
      dailySleepScores: previous.dailySleepScores,
      lastSleepStages: previous.lastSleepStages
    };
    let successfulDomains: number = 0;
    let failedDomains: number = 0;

    if (snapshot.stepsStatus.success) {
      state.steps = snapshot.steps;
      state.hasSteps = snapshot.hasSteps;
      state.dailySteps = snapshot.dailySteps;
      state.dailyStepDates = snapshot.dailyStepDates;
      successfulDomains += 1;
    } else if (snapshot.stepsStatus.attempted) {
      failedDomains += 1;
    }

    if (snapshot.restingHeartRateStatus.success) {
      state.restingHeartRate = snapshot.restingHeartRate;
      state.hasRestingHeartRate = snapshot.hasRestingHeartRate;
      state.dailyRestingHeartRates = snapshot.dailyRestingHeartRates;
      successfulDomains += 1;
    } else if (snapshot.restingHeartRateStatus.attempted) {
      failedDomains += 1;
    }

    if (snapshot.sleepStatus.success) {
      state.sleepMinutes = snapshot.sleepMinutes;
      state.sleepScore = snapshot.sleepScore;
      state.hasSleep = snapshot.hasSleep;
      state.dailySleepMinutes = snapshot.dailySleepMinutes;
      state.dailySleepScores = snapshot.dailySleepScores;
      state.lastSleepStages = snapshot.lastSleepStages;
      successfulDomains += 1;
    } else if (snapshot.sleepStatus.attempted) {
      failedDomains += 1;
    }

    return {
      state: state,
      successfulDomains: successfulDomains,
      failedDomains: failedDomains,
      shouldPersistSteps: snapshot.stepsStatus.success
    };
  }
}
