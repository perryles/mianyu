import type common from '@ohos.app.ability.common';
import { HuaweiHealthService } from '../service/HuaweiHealthService';
import type { HuaweiHealthSnapshot, SleepStages } from '../service/HuaweiHealthService';

const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
const COLOR_LIGHT_GREEN: string = '#E2F4EA';
const COLOR_PURPLE: string = '#8B6FD6';
const COLOR_BLUE: string = '#4F7FEA';
const COLOR_ORANGE: string = '#F09A50';
const COLOR_RED: string = '#D85C67';

interface SleepDayPoint {
  label: string;
  minutes: number;
  score: number;
  heightPercent: number;
}

interface StageRow {
  key: string;
  name: string;
  minutes: number;
  percent: number;
  color: string;
}

@Entry
@Component
struct SleepDetailPage {
  @State loading: boolean = true;
  @State statusText: string = '';
  @State hasSleep: boolean = false;
  @State sleepMinutes: number = 0;
  @State sleepScore: number = 0;
  @State days: SleepDayPoint[] = [];
  @State stages: SleepStages = {
    deepMinutes: 0,
    shallowMinutes: 0,
    dreamMinutes: 0,
    awakeMinutes: 0,
    totalMinutes: 0,
    hasDetails: false
  };
  private healthService: HuaweiHealthService = new HuaweiHealthService();

  private t(name: string, first?: string | number, second?: string | number): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return '';
    if (first === undefined) return context.resourceManager.getStringByNameSync(name);
    if (second === undefined) return context.resourceManager.getStringByNameSync(name, first);
    return context.resourceManager.getStringByNameSync(name, first, second);
  }

  aboutToAppear(): void {
    this.statusText = this.t('sleep_reading');
    this.loadSleepData();
  }

  private async loadSleepData(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      this.statusText = this.t('context_unavailable');
      this.loading = false;
      return;
    }
    const result = await this.healthService.initialize(context);
    if (!result.success) {
      this.statusText = result.message;
      this.loading = false;
      return;
    }
    const authorized: boolean = await this.healthService.hasRequiredAuthorizations();
    if (!authorized) {
      this.statusText = this.t('sleep_auth_required');
      this.loading = false;
      return;
    }
    const snapshot: HuaweiHealthSnapshot = await this.healthService.readTodaySnapshot();
    this.hasSleep = snapshot.hasSleep;
    this.sleepMinutes = snapshot.sleepMinutes;
    this.sleepScore = snapshot.sleepScore;
    this.stages = snapshot.lastSleepStages;
    this.days = this.buildDays(snapshot.dailySleepMinutes, snapshot.dailySleepScores);
    this.statusText = this.hasSleep ? this.t('sleep_source') : this.t('sleep_empty');
    this.loading = false;
  }

  private buildDays(minutes: number[], scores: number[]): SleepDayPoint[] {
    const weekdays: string[] = ['weekday_sun', 'weekday_mon', 'weekday_tue', 'weekday_wed', 'weekday_thu',
      'weekday_fri', 'weekday_sat'];
    const now: Date = new Date();
    let maxMinutes: number = 0;
    for (let index = 0; index < 7; index++) {
      if (minutes[index] > maxMinutes) {
        maxMinutes = minutes[index];
      }
    }
    const points: SleepDayPoint[] = [];
    for (let index = 0; index < 7; index++) {
      const date: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6 + index);
      const dayMinutes: number = index < minutes.length ? minutes[index] : 0;
      const dayScore: number = index < scores.length ? scores[index] : 0;
      const heightPercent: number = maxMinutes > 0 ? Math.max(6, Math.round(dayMinutes / maxMinutes * 100)) : 6;
      points.push({
        label: this.t(index === 6 ? 'today_short' : weekdays[date.getDay()]),
        minutes: dayMinutes,
        score: dayScore,
        heightPercent: heightPercent
      });
    }
    return points;
  }

  private durationText(minutes: number): string {
    if (minutes <= 0) {
      return '--';
    }
    const hours: number = Math.floor(minutes / 60);
    const remaining: number = minutes % 60;
    return this.t('duration_format', hours, remaining);
  }

  private stagePercent(minutes: number): number {
    if (this.stages.totalMinutes <= 0) {
      return 0;
    }
    return Math.min(Math.round(minutes / this.stages.totalMinutes * 100), 100);
  }

  /**
   * 清醒占比使用「睡眠时长 + 清醒时长」作为分母（清醒不含在 totalMinutes 内），
   * 避免四期百分比合计越界，条形宽度统一限制在 100% 以内。
   */
  private awakePercent(): number {
    const total: number = this.stages.totalMinutes + this.stages.awakeMinutes;
    if (total <= 0) {
      return 0;
    }
    return Math.min(Math.round(this.stages.awakeMinutes / total * 100), 100);
  }

  private stageRows(): StageRow[] {
    return [
      {
        key: 'deep',
        name: this.t('sleep_stage_deep'),
        minutes: this.stages.deepMinutes,
        percent: this.stagePercent(this.stages.deepMinutes),
        color: COLOR_PURPLE
      },
      {
        key: 'shallow',
        name: this.t('sleep_stage_shallow'),
        minutes: this.stages.shallowMinutes,
        percent: this.stagePercent(this.stages.shallowMinutes),
        color: COLOR_BLUE
      },
      {
        key: 'dream',
        name: this.t('sleep_stage_rem'),
        minutes: this.stages.dreamMinutes,
        percent: this.stagePercent(this.stages.dreamMinutes),
        color: COLOR_ORANGE
      },
      {
        key: 'awake',
        name: this.t('sleep_stage_awake'),
        minutes: this.stages.awakeMinutes,
        percent: this.awakePercent(),
        color: COLOR_RED
      }
    ];
  }

  private stageHint(): string {
    if (!this.stages.hasDetails) {
      return this.t('sleep_stage_empty');
    }
    const deepPercent: number = this.stagePercent(this.stages.deepMinutes);
    if (deepPercent >= 20) {
      return this.t('sleep_hint_good');
    }
    if (deepPercent > 0) {
      return this.t('sleep_hint_low');
    }
    return this.t('sleep_hint_unknown');
  }

  @Builder
  StageBar(label: string, minutes: number, percent: number, color: string) {
    Column({ space: 6 }) {
      Text(this.durationText(minutes))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      Row() {
        Text(label)
          .fontSize(13)
          .fontColor(COLOR_SECONDARY)
        Blank()
        Text(`${percent}%`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(color)
      }
      .width('100%')
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .height(8)
          .width('100%')
          .backgroundColor('#EAEFEB')
          .borderRadius(4)
        Row()
          .height(8)
          .width(`${percent}%`)
          .backgroundColor(color)
          .borderRadius(4)
      }
      .width('100%')
      .height(8)
    }
    .width('100%')
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text('‹')
          .fontSize(28)
          .fontColor(COLOR_TEXT)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .onClick(() => this.getUIContext().getRouter().back())
        Column({ space: 3 }) {
          Text($r('app.string.sleep_detail_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
          Text(this.statusText)
            .fontSize(13)
            .fontColor(COLOR_SECONDARY)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Scroll() {
        Column({ space: 16 }) {
          if (this.loading) {
            Column() {
              Text($r('app.string.loading'))
                .fontSize(14)
                .fontColor(COLOR_SECONDARY)
            }
            .padding(30)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Column({ space: 14 }) {
              Row() {
                Column({ space: 4 }) {
                  Text($r('app.string.sleep_last_night'))
                    .fontSize(14)
                    .fontColor(COLOR_SECONDARY)
                    .width('100%')
                  Text(this.hasSleep ? this.durationText(this.sleepMinutes) : '--')
                    .fontSize(26)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(COLOR_TEXT)
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Column({ space: 4 }) {
                  Text($r('app.string.sleep_score'))
                    .fontSize(14)
                    .fontColor(COLOR_SECONDARY)
                    .width('100%')
                  Text(this.hasSleep && this.sleepScore > 0 ? this.t('score_format', this.sleepScore) : '--')
                    .fontSize(26)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(COLOR_PURPLE)
                    .width('100%')
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
            }
            .padding(18)
            .width('100%')
            .backgroundColor(COLOR_CARD)
            .borderRadius(24)

            Column({ space: 14 }) {
              Text($r('app.string.sleep_week_duration'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Row({ space: 10 }) {
                ForEach(this.days, (point: SleepDayPoint) => {
                  Column({ space: 6 }) {
                    Text(this.durationText(point.minutes))
                      .fontSize(9)
                      .fontColor(COLOR_SECONDARY)
                    Column()
                      .width(20)
                      .height(`${point.heightPercent}%`)
                      .linearGradient({
                        angle: 0,
                        colors: point.label === this.t('today_short') ? [[COLOR_GREEN, 0.0], ['#6BC49E', 1.0]] : [['#C9DAD1', 0.0], ['#E2EBE6', 1.0]]
                      })
                      .borderRadius(10)
                    Text(point.label)
                      .fontSize(12)
                      .fontColor(point.label === this.t('today_short') ? COLOR_GREEN : COLOR_SECONDARY)
                      .fontWeight(point.label === this.t('today_short') ? FontWeight.Bold : FontWeight.Regular)
                  }
                  .layoutWeight(1)
                  .height(150)
                  .justifyContent(FlexAlign.End)
                }, (point: SleepDayPoint) => point.label)
              }
              .width('100%')
              .height(150)
              .alignItems(VerticalAlign.Bottom)
              Text($r('app.string.sleep_week_score'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Row({ space: 10 }) {
                ForEach(this.days, (point: SleepDayPoint) => {
                  Column({ space: 5 }) {
                    Text(point.score > 0 ? `${point.score}` : '--')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(point.score > 0 ? COLOR_GREEN : '#A8B1AC')
                    Text(point.label)
                      .fontSize(11)
                      .fontColor(COLOR_SECONDARY)
                  }
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                }, (point: SleepDayPoint) => `score_${point.label}`)
              }
              .width('100%')
            }
            .padding(18)
            .width('100%')
            .backgroundColor(COLOR_CARD)
            .borderRadius(24)

            Column({ space: 12 }) {
              Row() {
                Text($r('app.string.sleep_stages'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT)
                Blank()
                Text(this.stages.hasDetails ? this.t('sleep_stage_total_format', this.durationText(this.stages.totalMinutes)) :
                  this.t('sleep_no_details'))
                  .fontSize(12)
                  .fontColor(COLOR_SECONDARY)
              }
              .width('100%')
              ForEach(this.stageRows(), (row: StageRow) => {
                this.StageBar(row.name, row.minutes, row.percent, row.color)
              }, (row: StageRow) => row.key)
              Text(this.stageHint())
                .fontSize(12)
                .fontColor(COLOR_SECONDARY)
                .lineHeight(18)
                .width('100%')
            }
            .padding(18)
            .width('100%')
            .backgroundColor(COLOR_CARD)
            .borderRadius(24)

            Text($r('app.string.sleep_privacy_disclaimer'))
              .fontSize(12)
              .fontColor(COLOR_SECONDARY)
              .lineHeight(18)
              .width('100%')
          }
        }
        .padding({ left: 18, right: 18, top: 10, bottom: 30 })
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')
    }
    .padding({ left: 18, right: 18, top: 14, bottom: 18 })
    .width('100%')
    .height('100%')
    .linearGradient({ angle: 180, colors: [['#F6FAF7', 0.0], [COLOR_BACKGROUND, 1.0]] })
  }
}
