import { healthStore } from '@kit.HealthServiceKit';
import type common from '@ohos.app.ability.common';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 华为运动健康（Health Service Kit）封装。
 * 只读不写：仅申请日常活动、静息心率与睡眠的读取授权，
 * 不写入、不删除任何健康数据，也不向任何远端上传明细。
 */
export interface HealthServiceResult {
  success: boolean;
  message: string;
}

export interface HuaweiHealthSnapshot {
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
  updatedAt: number;
}

/**
 * 最近一晚的睡眠分期（分钟）。仅从本机已授权的睡眠明细聚合，不落盘、不上传。
 */
export interface SleepStages {
  deepMinutes: number;
  shallowMinutes: number;
  dreamMinutes: number;
  awakeMinutes: number;
  totalMinutes: number;
  hasDetails: boolean;
}

/**
 * 睡眠分期明细段（Health Service Kit 的 sleepSegment 子集）。
 */
interface SleepSegment {
  startTime: number;
  endTime: number;
  sleepStatus: number;
}

interface StepAggregateValue {
  sum?: number;
}

interface StepAggregateResult {
  step: StepAggregateValue;
}

interface StepAggregateItem extends healthStore.AggregateResult {
  result: StepAggregateResult;
}

interface AuthorizationGrantedResponse extends healthStore.AuthorizationResponse {
  grantedTypes: healthStore.DataType[];
}

interface HealthDataTypes {
  dailyActivities: healthStore.DataType;
  restingHeartRate: healthStore.DataType;
  sleepRecord: healthStore.DataType;
}

interface StepReadResult {
  steps: number;
  hasSteps: boolean;
  dailySteps: number[];
  dailyStepDates: string[];
}

interface HeartRateReadResult {
  restingHeartRate: number;
  hasRestingHeartRate: boolean;
  dailyRestingHeartRates: number[];
}

interface SleepReadResult {
  sleepMinutes: number;
  sleepScore: number;
  hasSleep: boolean;
  dailySleepMinutes: number[];
  dailySleepScores: number[];
  lastSleepStages: SleepStages;
}

export class HuaweiHealthService {
  private context: common.Context | undefined = undefined;
  private initialized: boolean = false;
  private readonly dataTypes: HealthDataTypes = {
    dailyActivities: healthStore.samplePointHelper.dailyActivities.DATA_TYPE,
    restingHeartRate: healthStore.samplePointHelper.restingHeartRate.DATA_TYPE,
    sleepRecord: healthStore.healthSequenceHelper.sleepRecord.DATA_TYPE
  };
  private readonly readDataTypes: healthStore.DataType[] = [];
  private readonly writeDataTypes: healthStore.DataType[] = [];

  private t(name: string, first?: number): string {
    if (this.context === undefined) return '';
    if (first === undefined) return this.context.resourceManager.getStringByNameSync(name);
    return this.context.resourceManager.getStringByNameSync(name, first);
  }

  constructor() {
    this.readDataTypes.push(this.dataTypes.dailyActivities);
    this.readDataTypes.push(this.dataTypes.restingHeartRate);
    this.readDataTypes.push(this.dataTypes.sleepRecord);
  }

  private get authorizationRequest(): healthStore.AuthorizationRequest {
    return {
      readDataTypes: this.readDataTypes,
      writeDataTypes: this.writeDataTypes
    };
  }

  /**
   * 初始化 Health Service Kit，并缓存授权所需的数据类型。
   */
  async initialize(context: common.Context): Promise<HealthServiceResult> {
    this.context = context;
    if (this.initialized) {
      return { success: true, message: this.t('health_ready') };
    }
    try {
      await healthStore.init(context);
      this.initialized = true;
      return { success: true, message: this.t('health_initialized') };
    } catch (error) {
      const code: number = (error as BusinessError).code;
      return { success: false, message: this.errorMessage(code) };
    }
  }

  /**
   * 检查是否已获得全部所需授权。
   */
  async hasRequiredAuthorizations(): Promise<boolean> {
    try {
      const response: AuthorizationGrantedResponse = await healthStore.getAuthorizations(this.authorizationRequest) as AuthorizationGrantedResponse;
      return this.containsRequiredTypes(response.grantedTypes);
    } catch (error) {
      return false;
    }
  }

  /**
   * 发起授权（会拉起华为运动健康授权页）。
   */
  async requestAuthorizations(context: common.UIAbilityContext): Promise<HealthServiceResult> {
    const initializedResult: HealthServiceResult = await this.initialize(context);
    if (!initializedResult.success) {
      return initializedResult;
    }
    try {
      const granted: AuthorizationGrantedResponse = await healthStore.requestAuthorizations(context, this.authorizationRequest) as AuthorizationGrantedResponse;
      if (this.containsRequiredTypes(granted.grantedTypes)) {
        return { success: true, message: this.t('health_auth_all') };
      }
      if (this.containsAnyRequiredType(this.readDataTypes, granted.grantedTypes)) {
        return { success: false, message: this.t('health_auth_partial') };
      }
      return { success: false, message: this.t('health_auth_none') };
    } catch (error) {
      const code: number = (error as BusinessError).code;
      return { success: false, message: this.errorMessage(code) };
    }
  }

  /**
   * 读取今日快照与近 7 天序列。
   */
  async readTodaySnapshot(): Promise<HuaweiHealthSnapshot> {
    const stepResult: StepReadResult = await this.readSteps();
    const heartRateResult: HeartRateReadResult = await this.readRestingHeartRate();
    const sleepResult: SleepReadResult = await this.readSleep();
    const snapshot: HuaweiHealthSnapshot = {
      steps: stepResult.steps,
      restingHeartRate: heartRateResult.restingHeartRate,
      sleepMinutes: sleepResult.sleepMinutes,
      sleepScore: sleepResult.sleepScore,
      hasSteps: stepResult.hasSteps,
      hasRestingHeartRate: heartRateResult.hasRestingHeartRate,
      hasSleep: sleepResult.hasSleep,
      dailySteps: stepResult.dailySteps,
      dailyStepDates: stepResult.dailyStepDates,
      dailyRestingHeartRates: heartRateResult.dailyRestingHeartRates,
      dailySleepMinutes: sleepResult.dailySleepMinutes,
      dailySleepScores: sleepResult.dailySleepScores,
      lastSleepStages: sleepResult.lastSleepStages,
      updatedAt: Date.now()
    };
    return snapshot;
  }

  /**
   * 撤销运动健康授权。
   */
  async cancelAuthorizations(): Promise<HealthServiceResult> {
    try {
      await healthStore.cancelAuthorizations();
      this.initialized = false;
      return { success: true, message: this.t('health_auth_revoked') };
    } catch (error) {
      const code: number = (error as BusinessError).code;
      return { success: false, message: this.errorMessage(code) };
    }
  }

  private async readSteps(): Promise<StepReadResult> {
    const endDate: Date = new Date();
    const startDate: Date = new Date(endDate.getTime() - 6 * 24 * 60 * 60 * 1000);
    const request: healthStore.AggregateRequest = {
      dataType: this.dataTypes.dailyActivities,
      metrics: { step: ['sum'] },
      groupBy: { unitType: healthStore.GroupUnitType.DAY },
      startLocalDate: HuaweiHealthService.localDate(startDate),
      endLocalDate: HuaweiHealthService.localDate(endDate)
    };
    try {
      const results: StepAggregateItem[] = await healthStore.aggregateData<StepAggregateItem>(request);
      const dailySteps: number[] = [];
      const dailyStepDates: string[] = [];
      for (let index = 0; index < 7; index++) {
        const date: Date = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate() - 6 + index);
        const key: string = HuaweiHealthService.localDate(date);
        let dayTotal: number = 0;
        results.forEach((item) => {
          if (HuaweiHealthService.localDate(new Date(item.startTime)) === key) {
            dayTotal += item.result.step.sum ?? 0;
          }
        });
        dailySteps.push(dayTotal);
        dailyStepDates.push(key);
      }
      const steps: number = dailySteps.length > 0 ? dailySteps[dailySteps.length - 1] : 0;
      const hasSteps: boolean = dailySteps.some((value: number) => value > 0);
      return { steps, hasSteps, dailySteps, dailyStepDates };
    } catch (error) {
      return { steps: 0, hasSteps: false, dailySteps: [0, 0, 0, 0, 0, 0, 0], dailyStepDates: [] };
    }
  }

  private async readRestingHeartRate(): Promise<HeartRateReadResult> {
    const endDate: Date = new Date();
    const startDate: Date = new Date(endDate.getTime() - 6 * 24 * 60 * 60 * 1000);
    const request: healthStore.SamplePointReadRequest = {
      samplePointDataType: this.dataTypes.restingHeartRate,
      startTime: startDate.getTime(),
      endTime: endDate.getTime(),
      sortOrder: healthStore.SortOrder.ASC
    };
    try {
      const points: healthStore.samplePointHelper.restingHeartRate.Model[] =
        await healthStore.readData<healthStore.samplePointHelper.restingHeartRate.Model>(request);
      const dailyRestingHeartRates: number[] = [];
      for (let index = 0; index < 7; index++) {
        const date: Date = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate() - 6 + index);
        const key: string = HuaweiHealthService.localDate(date);
        let latestBpm: number = 0;
        let latestTime: number = 0;
        points.forEach((point) => {
          if (HuaweiHealthService.localDate(new Date(point.startTime)) === key && point.modifiedTime >= latestTime) {
            latestTime = point.modifiedTime;
            latestBpm = point.fields.restBpm;
          }
        });
        dailyRestingHeartRates.push(latestBpm);
      }
      const restingHeartRate: number = dailyRestingHeartRates.length > 0 ? dailyRestingHeartRates[dailyRestingHeartRates.length - 1] : 0;
      const hasRestingHeartRate: boolean = dailyRestingHeartRates.some((value: number) => value > 0);
      return { restingHeartRate, hasRestingHeartRate, dailyRestingHeartRates };
    } catch (error) {
      return { restingHeartRate: 0, hasRestingHeartRate: false, dailyRestingHeartRates: [0, 0, 0, 0, 0, 0, 0] };
    }
  }

  private async readSleep(): Promise<SleepReadResult> {
    const endDate: Date = new Date();
    const startDate: Date = new Date(endDate.getTime() - 6 * 24 * 60 * 60 * 1000);
    const request: healthStore.HealthSequenceReadRequest = {
      healthSequenceDataType: this.dataTypes.sleepRecord,
      startTime: startDate.getTime(),
      endTime: endDate.getTime(),
      readOptions: { withDetails: true }
    };
    try {
      const records: healthStore.healthSequenceHelper.sleepRecord.Model[] =
        await healthStore.readData<healthStore.healthSequenceHelper.sleepRecord.Model>(request);
      const dailySleepMinutes: number[] = [];
      const dailySleepScores: number[] = [];
      let todayScore: number = 0;
      for (let index = 0; index < 7; index++) {
        const date: Date = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate() - 6 + index);
        const key: string = HuaweiHealthService.localDate(date);
        let dayMinutes: number = 0;
        let dayScore: number = 0;
        records.forEach((record) => {
          if (HuaweiHealthService.localDate(new Date(record.startTime)) === key) {
            dayMinutes += Math.round((record.summaries.duration ?? 0) / 60);
            const score: number = record.summaries.sleepScore ?? 0;
            if (score > dayScore) {
              dayScore = score;
            }
            if (index === 6 && score > 0) {
              todayScore = score;
            }
          }
        });
        dailySleepMinutes.push(dayMinutes);
        dailySleepScores.push(dayScore);
      }
      const sleepMinutes: number = dailySleepMinutes.length > 0 ? dailySleepMinutes[dailySleepMinutes.length - 1] : 0;
      const sleepScore: number = todayScore;
      const hasSleep: boolean = dailySleepMinutes.some((value: number) => value > 0);
      const lastSleepStages: SleepStages = this.aggregateLatestSleepStages(records);
      return { sleepMinutes, sleepScore, hasSleep, dailySleepMinutes, dailySleepScores, lastSleepStages };
    } catch (error) {
      return {
        sleepMinutes: 0,
        sleepScore: 0,
        hasSleep: false,
        dailySleepMinutes: [0, 0, 0, 0, 0, 0, 0],
        dailySleepScores: [0, 0, 0, 0, 0, 0, 0],
        lastSleepStages: this.emptySleepStages()
      };
    }
  }

  /**
   * 聚合最近一条包含分期明细的睡眠记录，输出深睡/浅睡/REM/清醒分钟数。
   * 1=深睡 2=浅睡 3=REM 4=清醒；其余状态（0 未知、5 小睡、6 卧床等）不纳入分期占比。
   */
  private aggregateLatestSleepStages(records: healthStore.healthSequenceHelper.sleepRecord.Model[]): SleepStages {
    const empty: SleepStages = this.emptySleepStages();
    if (records.length === 0) {
      return empty;
    }
    const sorted: healthStore.healthSequenceHelper.sleepRecord.Model[] = records.slice().sort((a, b) => b.startTime - a.startTime);
    for (let index = 0; index < sorted.length; index++) {
      const record = sorted[index];
      const segments: SleepSegment[] | undefined = (record.details as healthStore.healthFields.SleepDetail | undefined)?.sleepSegment;
      if (segments === undefined || segments.length === 0) {
        continue;
      }
      let deepMinutes: number = 0;
      let shallowMinutes: number = 0;
      let dreamMinutes: number = 0;
      let awakeMinutes: number = 0;
      let totalMinutes: number = 0;
      segments.forEach((segment: SleepSegment) => {
        const minutes: number = Math.round((segment.endTime - segment.startTime) / 60000);
        if (minutes <= 0) {
          return;
        }
        if (segment.sleepStatus === 1) {
          deepMinutes += minutes;
          totalMinutes += minutes;
        } else if (segment.sleepStatus === 2) {
          shallowMinutes += minutes;
          totalMinutes += minutes;
        } else if (segment.sleepStatus === 3) {
          dreamMinutes += minutes;
          totalMinutes += minutes;
        } else if (segment.sleepStatus === 4) {
          awakeMinutes += minutes;
        }
      });
      return { deepMinutes, shallowMinutes, dreamMinutes, awakeMinutes, totalMinutes, hasDetails: totalMinutes > 0 };
    }
    return empty;
  }

  private emptySleepStages(): SleepStages {
    return { deepMinutes: 0, shallowMinutes: 0, dreamMinutes: 0, awakeMinutes: 0, totalMinutes: 0, hasDetails: false };
  }

  private containsRequiredTypes(grantedTypes: healthStore.DataType[]): boolean {
    const requiredIds: number[] = this.readDataTypes.map((type: healthStore.DataType) => type.id);
    for (let index = 0; index < requiredIds.length; index++) {
      const found: boolean = grantedTypes.some((grantedType: healthStore.DataType) => grantedType.id === requiredIds[index]);
      if (!found) {
        return false;
      }
    }
    return true;
  }

  private containsAnyRequiredType(requiredTypes: healthStore.DataType[], grantedTypes: healthStore.DataType[]): boolean {
    return requiredTypes.some((requiredType: healthStore.DataType) =>
      grantedTypes.some((grantedType: healthStore.DataType) => grantedType.id === requiredType.id));
  }

  /**
   * 将健康服务错误码映射为用户可读文案（不输出任何健康明细）。
   */
  private errorMessage(code: number): string {
    switch (code) {
      case 201:
        return this.t('health_error_config');
      case 1002701001:
        return this.t('health_error_network');
      case 1002702001:
        return this.t('health_error_account');
      case 1002702002:
        return this.t('health_error_unavailable_format', code);
      case 1002703001:
        return this.t('health_error_privacy');
      case 1002700001:
      case 1002700002:
        return this.t('health_error_unavailable_format', code);
      default:
        return this.t('health_error_unavailable_format', code);
    }
  }

  static localDate(date: Date): string {
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }
}
