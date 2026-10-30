import bundleManager from '@ohos.bundle.bundleManager';
import type common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { HealthScoreEngine } from '../model/HealthScoreEngine';
import { HuaweiHealthService } from '../service/HuaweiHealthService';
import type { HealthServiceResult, HuaweiHealthSnapshot } from '../service/HuaweiHealthService';

const STORAGE_NAME: string = 'bio_balance_local_state';
const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
const COLOR_LIGHT_GREEN: string = '#E2F4EA';
const COLOR_ORANGE: string = '#F09A50';
const COLOR_BLUE: string = '#4F7FEA';
const COLOR_PURPLE: string = '#8B6FD6';

interface TrendPoint {
  day: string;
  value: number;
  steps: number;
}

@Entry
@Component
struct Index {
  @State selectedTab: number = 0;
  @State waterCups: number = 4;
  @State steps: number = 0;
  @State mood: number = 3;
  @State actionCompleted: boolean = false;
  @State notificationEnabled: boolean = true;
  @State dailyStepGoal: number = 8000;
  @State breathingSeconds: number = 60;
  @State breathingActive: boolean = false;
  @State loaded: boolean = false;
  @State lastSavedText: string = '';
  @State resetConfirmationVisible: boolean = false;
  @State restingHeartRate: number = 0;
  @State sleepMinutes: number = 0;
  @State sleepScore: number = 0;
  @State hasSteps: boolean = false;
  @State hasRestingHeartRate: boolean = false;
  @State hasSleep: boolean = false;
  @State healthAuthorized: boolean = false;
  @State healthLoading: boolean = false;
  @State healthStatus: string = '';
  @State healthUpdatedAt: string = '';
  @State hasTrendData: boolean = false;
  @State weeklyStepTotal: number = 0;
  @State weeklyGoalDays: number = 0;
  @State averageRestingHeartRate: number = 0;
  @State restingHeartRateDays: number = 0;
  @State averageSleepMinutes: number = 0;
  @State sleepRecordDays: number = 0;
  @State trendData: TrendPoint[] = [
    { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 },
    { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 },
    { day: '', value: 0, steps: 0 }
  ];
  private dataStore: preferences.Preferences | undefined = undefined;
  private breathingTimer: number = -1;
  private healthService: HuaweiHealthService = new HuaweiHealthService();

  aboutToAppear(): void {
    this.lastSavedText = this.t('index_data_local');
    this.healthStatus = this.t('index_health_waiting');
    this.healthUpdatedAt = this.t('index_not_synced');
    this.loadLocalState();
  }

  private t(name: string, first?: string | number, second?: string | number, third?: string | number): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return '';
    if (first === undefined) return context.resourceManager.getStringByNameSync(name);
    if (second === undefined) return context.resourceManager.getStringByNameSync(name, first);
    if (third === undefined) return context.resourceManager.getStringByNameSync(name, first, second);
    return context.resourceManager.getStringByNameSync(name, first, second, third);
  }

  onPageShow(): void {
    if (this.loaded && !this.healthLoading) {
      this.initializeHuaweiHealth();
    }
  }

  aboutToDisappear(): void {
    if (this.breathingTimer >= 0) {
      clearInterval(this.breathingTimer);
      this.breathingTimer = -1;
    }
  }

  private async loadLocalState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.loaded = true;
        this.lastSavedText = this.t('local_storage_unavailable');
        return;
      }
      this.dataStore = await preferences.getPreferences(context, STORAGE_NAME);
      const storedDate = this.dataStore.getSync('date', '') as string;
      const today = this.todayKey();
      this.notificationEnabled = this.dataStore.getSync('notificationEnabled', true) as boolean;
      this.dailyStepGoal = this.dataStore.getSync('dailyStepGoal', 8000) as number;
      if (storedDate === today) {
        this.waterCups = this.dataStore.getSync('waterCups', 4) as number;
        this.steps = this.dataStore.getSync('steps', 0) as number;
        this.mood = this.dataStore.getSync('mood', 3) as number;
        this.actionCompleted = this.dataStore.getSync('actionCompleted', false) as boolean;
      } else {
        this.persistState();
      }
      this.loaded = true;
      this.initializeHuaweiHealth();
    } catch (error) {
      this.loaded = true;
      this.lastSavedText = this.t('local_storage_unavailable');
      this.initializeHuaweiHealth();
    }
  }

  private persistState(): void {
    if (this.dataStore === undefined) {
      return;
    }
    try {
      this.dataStore.putSync('date', this.todayKey());
      this.dataStore.putSync('waterCups', this.waterCups);
      this.dataStore.putSync('steps', this.steps);
      this.dataStore.putSync('mood', this.mood);
      this.dataStore.putSync('actionCompleted', this.actionCompleted);
      this.dataStore.putSync('notificationEnabled', this.notificationEnabled);
      this.dataStore.putSync('dailyStepGoal', this.dailyStepGoal);
      this.dataStore.flush().then(() => {
        this.lastSavedText = this.t('saved_on_device');
      }).catch(() => {
        this.lastSavedText = this.t('save_failed');
      });
    } catch (error) {
      this.lastSavedText = this.t('save_failed');
    }
  }

  private todayKey(): string {
    const date = new Date();
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
  }

  private dateTitle(): string {
    const date = new Date();
    const weekdays: string[] = ['weekday_sun', 'weekday_mon', 'weekday_tue', 'weekday_wed', 'weekday_thu',
      'weekday_fri', 'weekday_sat'];
    return this.t('index_date_format', date.getMonth() + 1, date.getDate(), this.t(weekdays[date.getDay()]));
  }

  private greeting(): string {
    const hour = new Date().getHours();
    if (hour < 11) {
      return this.t('index_greeting_morning');
    }
    if (hour < 14) {
      return this.t('index_greeting_noon');
    }
    if (hour < 18) {
      return this.t('index_greeting_afternoon');
    }
    return this.t('index_greeting_evening');
  }

  private healthScore(): number {
    return HealthScoreEngine.calculate(this.waterCups, this.steps, this.mood, this.dailyStepGoal);
  }

  private moodLabel(): string {
    const labels: string[] = ['index_mood_exhausted', 'index_mood_low', 'index_mood_calm', 'index_mood_good',
      'index_mood_great'];
    return this.t(labels[this.mood - 1]);
  }

  private addWater(): void {
    if (this.waterCups < 12) {
      this.waterCups += 1;
      this.persistState();
    }
  }

  private setMood(value: number): void {
    this.mood = value;
    this.persistState();
  }

  private toggleAction(): void {
    this.actionCompleted = !this.actionCompleted;
    this.persistState();
  }

  private startBreathing(): void {
    if (this.breathingActive) {
      return;
    }
    this.breathingSeconds = 60;
    this.breathingActive = true;
    this.breathingTimer = setInterval(() => {
      this.breathingSeconds -= 1;
      if (this.breathingSeconds <= 0) {
        clearInterval(this.breathingTimer);
        this.breathingTimer = -1;
        this.breathingActive = false;
        this.breathingSeconds = 60;
      }
    }, 1000);
  }

  private resetToday(): void {
    this.waterCups = 0;
    this.steps = 0;
    this.mood = 3;
    this.actionCompleted = false;
    this.persistState();
  }

  private async initializeHuaweiHealth(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      this.healthStatus = this.t('context_unavailable');
      return;
    }
    const result: HealthServiceResult = await this.healthService.initialize(context);
    if (!result.success) {
      this.healthStatus = result.message;
      return;
    }
    this.healthAuthorized = await this.healthService.hasRequiredAuthorizations();
    this.healthStatus = this.t(this.healthAuthorized ? 'index_health_connected' : 'index_health_auth_required');
    if (this.healthAuthorized) {
      await this.refreshHuaweiHealth();
    }
  }

  private async connectHuaweiHealth(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || this.healthLoading) {
      return;
    }
    this.healthLoading = true;
    const result: HealthServiceResult = await this.healthService.requestAuthorizations(context);
    this.healthAuthorized = result.success;
    this.healthStatus = result.message;
    this.healthLoading = false;
    if (result.success) {
      await this.refreshHuaweiHealth();
    }
  }

  private async refreshHuaweiHealth(): Promise<void> {
    if (!this.healthAuthorized || this.healthLoading) {
      return;
    }
    this.healthLoading = true;
    try {
      const snapshot: HuaweiHealthSnapshot = await this.healthService.readTodaySnapshot();
      this.steps = snapshot.steps;
      this.restingHeartRate = snapshot.restingHeartRate;
      this.sleepMinutes = snapshot.sleepMinutes;
      this.sleepScore = snapshot.sleepScore;
      this.hasSteps = snapshot.hasSteps;
      this.hasRestingHeartRate = snapshot.hasRestingHeartRate;
      this.hasSleep = snapshot.hasSleep;
      this.updateStepTrend(snapshot.dailySteps);
      this.updateHealthHistory(snapshot.dailyRestingHeartRates, snapshot.dailySleepMinutes);
      this.healthUpdatedAt = this.timeText(snapshot.updatedAt);
      this.healthStatus = this.t('index_health_synced');
      this.persistState();
    } catch (error) {
      this.healthStatus = this.t('index_health_read_failed');
    }
    this.healthLoading = false;
  }

  private async openHuaweiHealthPrivacy(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) {
      return;
    }
    try {
      const link = 'huaweischeme://healthapp/home/main';
      if (bundleManager.canOpenLink(link)) {
        await context.openLink(link);
      } else {
        this.healthStatus = this.t('index_health_install');
      }
    } catch (error) {
      this.healthStatus = this.t('index_health_open_failed');
    }
  }

  private async disconnectHuaweiHealth(): Promise<void> {
    if (this.healthLoading) {
      return;
    }
    this.healthLoading = true;
    const result: HealthServiceResult = await this.healthService.cancelAuthorizations();
    this.healthStatus = result.message;
    if (result.success) {
      this.healthAuthorized = false;
      this.hasSteps = false;
      this.hasRestingHeartRate = false;
      this.hasSleep = false;
      this.steps = 0;
      this.restingHeartRate = 0;
      this.sleepMinutes = 0;
      this.sleepScore = 0;
      this.healthUpdatedAt = this.t('index_not_synced');
      this.clearStepTrend();
      this.clearHealthHistory();
      this.persistState();
    }
    this.healthLoading = false;
  }

  private timeText(timestamp: number): string {
    const date = new Date(timestamp);
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return this.t('index_today_time_format', date.getHours(), minute);
  }

  private sleepValue(): string {
    if (!this.hasSleep) {
      return '--';
    }
    const hours = Math.floor(this.sleepMinutes / 60);
    const minutes = this.sleepMinutes % 60;
    return this.t('duration_format', hours, minutes);
  }

  private updateStepTrend(dailySteps: number[]): void {
    const weekdays: string[] = ['weekday_sun', 'weekday_mon', 'weekday_tue', 'weekday_wed', 'weekday_thu',
      'weekday_fri', 'weekday_sat'];
    const now = new Date();
    const points: TrendPoint[] = [];
    let total = 0;
    let goalDays = 0;
    let hasData = false;
    for (let index = 0; index < 7; index++) {
      const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6 + index);
      const steps = index < dailySteps.length ? dailySteps[index] : 0;
      total += steps;
      if (steps >= this.dailyStepGoal) {
        goalDays += 1;
      }
      if (steps > 0) {
        hasData = true;
      }
      points.push({
        day: this.t(index === 6 ? 'today_short' : weekdays[date.getDay()]),
        value: Math.min(HealthScoreEngine.percentage(steps, this.dailyStepGoal), 100),
        steps: steps
      });
    }
    this.trendData = points;
    this.weeklyStepTotal = total;
    this.weeklyGoalDays = goalDays;
    this.hasTrendData = hasData;
  }

  private clearStepTrend(): void {
    this.updateStepTrend([0, 0, 0, 0, 0, 0, 0]);
  }

  private updateHealthHistory(dailyHeartRates: number[], dailySleepMinutes: number[]): void {
    let heartRateTotal = 0;
    let heartRateDays = 0;
    dailyHeartRates.forEach((heartRate) => {
      if (heartRate > 0) {
        heartRateTotal += heartRate;
        heartRateDays += 1;
      }
    });
    let sleepTotal = 0;
    let sleepDays = 0;
    dailySleepMinutes.forEach((minutes) => {
      if (minutes > 0) {
        sleepTotal += minutes;
        sleepDays += 1;
      }
    });
    this.restingHeartRateDays = heartRateDays;
    this.averageRestingHeartRate = heartRateDays > 0 ? Math.round(heartRateTotal / heartRateDays) : 0;
    this.sleepRecordDays = sleepDays;
    this.averageSleepMinutes = sleepDays > 0 ? Math.round(sleepTotal / sleepDays) : 0;
  }

  private clearHealthHistory(): void {
    this.averageRestingHeartRate = 0;
    this.restingHeartRateDays = 0;
    this.averageSleepMinutes = 0;
    this.sleepRecordDays = 0;
  }

  private durationText(minutes: number): string {
    if (minutes <= 0) {
      return '--';
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return this.t('duration_format', hours, remainingMinutes);
  }

  private shortSteps(steps: number): string {
    if (steps <= 0) {
      return '-';
    }
    if (steps >= 1000) {
      return `${(steps / 1000).toFixed(1)}k`;
    }
    return `${steps}`;
  }

  private trendSubtitle(): string {
    if (!this.healthAuthorized) {
      return this.t('index_trend_connect');
    }
    if (!this.hasTrendData) {
      return this.t('index_trend_empty');
    }
    return this.t('index_trend_source');
  }

  private healthSummaryTitle(): string {
    if (!this.healthAuthorized) {
      return this.t('index_health_waiting_short');
    }
    if (!this.hasSleep && !this.hasRestingHeartRate && !this.hasSteps) {
      return this.t('index_data_empty');
    }
    return this.t('index_status_updated');
  }

  private healthSummaryDetail(): string {
    if (!this.healthAuthorized) {
      return this.t('index_health_connect_help');
    }
    if (this.hasSleep) {
      return this.t('index_sleep_hint_format', this.sleepValue());
    }
    return this.t('index_health_partial');
  }

  @Builder
  PageHeader(title: string, subtitle: string) {
    Column({ space: 5 }) {
      Text(title)
        .fontSize(29)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      Text(subtitle)
        .fontSize(14)
        .fontColor(COLOR_SECONDARY)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SectionTitle(title: string, detail: string) {
    Row() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
      Blank()
      if (detail.length > 0) {
        Text(detail)
          .fontSize(13)
          .fontColor(COLOR_GREEN)
      }
    }
    .width('100%')
  }

  @Builder
  MetricCard(icon: string, label: string, value: string, detail: string, tint: string, surface: string) {
    Column({ space: 10 }) {
      Row() {
        Text(icon)
          .fontSize(21)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .backgroundColor(surface)
          .borderRadius(12)
        Blank()
        Text(detail)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(tint)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(value)
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      Text(label)
        .fontSize(13)
        .fontColor(COLOR_SECONDARY)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(15)
    .height(138)
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
    .shadow({ radius: 16, color: '#100C2017', offsetY: 5 })
  }

  @Builder
  ProgressBar(value: number, total: number, tint: string) {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .height(8)
        .width('100%')
        .backgroundColor('#EAEFEB')
        .borderRadius(4)
      Row()
        .height(8)
        .width(`${Math.min(value / total, 1) * 100}%`)
        .backgroundColor(tint)
        .borderRadius(4)
    }
    .width('100%')
    .height(8)
  }

  @Builder
  HomePage() {
    Scroll() {
      Column({ space: 22 }) {
        Column({ space: 5 }) {
          Text(this.dateTitle())
            .fontSize(14)
            .fontColor(COLOR_GREEN)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Text(this.t('index_greeting_format', this.greeting()))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)

        Row({ space: 18 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 112, height: 112 })
              .fill('#FFFFFF55')
              .stroke('#FFFFFF88')
              .strokeWidth(1)
            Column({ space: 0 }) {
              Text(`${this.healthScore()}`)
                .fontSize(39)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(this.t('index_today_status'))
                .fontSize(12)
                .fontColor('#E8FFF4')
            }
          }

          Column({ space: 9 }) {
            Text(this.healthSummaryTitle())
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width('100%')
            Text(this.healthSummaryDetail())
              .fontSize(14)
              .fontColor('#E9FFF5')
              .lineHeight(21)
              .width('100%')
            Text(this.t('index_local_assessment'))
              .fontSize(11)
              .fontColor('#CFF4E3')
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .padding(20)
        .width('100%')
        .linearGradient({ angle: 135, colors: [[COLOR_GREEN, 0.0], ['#45AF82', 1.0]] })
        .borderRadius(28)
        .shadow({ radius: 22, color: '#331E8E63', offsetY: 9 })

        this.SectionTitle(this.t('index_health_overview'), this.t('index_today'))

        Grid() {
          GridItem() {
            this.MetricCard('♥', this.t('index_resting_heart_rate'), this.hasRestingHeartRate ?
              this.t('heart_rate_format', this.restingHeartRate) : '--',
              this.t(this.healthAuthorized ? 'index_health_source' : 'index_pending_auth'), '#D85C67', '#FCE8EA')
          }
          GridItem() {
            this.MetricCard('☾', this.t('index_sleep'), this.sleepValue(),
              this.hasSleep && this.sleepScore > 0 ? this.t('score_format', this.sleepScore) :
                this.t('index_health_source'), COLOR_PURPLE, '#EEE9FA')
          }
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/SleepDetailPage' });
          })
          GridItem() {
            this.MetricCard('👟', this.t('index_today_steps'), this.hasSteps ? `${this.steps}` : '--',
              this.healthAuthorized ? `${HealthScoreEngine.percentage(this.steps, this.dailyStepGoal)}%` :
                this.t('index_pending_auth'), COLOR_BLUE, '#E8EEFD')
          }
          GridItem() {
            this.MetricCard('💧', this.t('index_water'), this.t('index_cups_format', this.waterCups),
              this.t(this.waterCups >= 8 ? 'index_goal_met' : 'index_continue'), COLOR_GREEN, COLOR_LIGHT_GREEN)
          }
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
        .height(288)

        this.SectionTitle(this.t('index_today_priority'), this.t(this.actionCompleted ? 'index_completed' : 'index_one_item'))

        Row({ space: 14 }) {
          Text(this.actionCompleted ? '✓' : '↗')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.actionCompleted ? Color.White : COLOR_GREEN)
            .width(50)
            .height(50)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.actionCompleted ? COLOR_GREEN : COLOR_LIGHT_GREEN)
            .borderRadius(17)
          Column({ space: 6 }) {
            Text(this.t(this.actionCompleted ? 'index_action_done' : 'index_action_stretch'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
              .width('100%')
            Text(this.t(this.actionCompleted ? 'index_action_done_help' : 'index_action_stretch_help'))
              .fontSize(13)
              .fontColor(COLOR_SECONDARY)
              .lineHeight(19)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button(this.t(this.actionCompleted ? 'index_undo' : 'index_complete'))
            .fontSize(13)
            .fontColor(this.actionCompleted ? COLOR_SECONDARY : Color.White)
            .backgroundColor(this.actionCompleted ? '#EDF1EE' : COLOR_GREEN)
            .height(38)
            .borderRadius(19)
            .onClick(() => this.toggleAction())
        }
        .padding(17)
        .width('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(22)
        .shadow({ radius: 14, color: '#0D0C2017', offsetY: 4 })

        Row({ space: 12 }) {
          Text('＋')
            .fontSize(24)
            .fontColor(COLOR_GREEN)
          Column({ space: 3 }) {
            Text(this.t('index_quick_water'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT)
              .width('100%')
            Text(this.t('index_water_goal_format', this.waterCups))
              .fontSize(12)
              .fontColor(COLOR_SECONDARY)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button(this.t('index_record'))
            .fontSize(13)
            .fontColor(COLOR_GREEN)
            .backgroundColor(COLOR_LIGHT_GREEN)
            .height(38)
            .borderRadius(19)
            .onClick(() => this.addWater())
        }
        .padding(16)
        .width('100%')
        .backgroundColor('#F8FCFA')
        .border({ width: 1, color: '#DDEBE3' })
        .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 110 })
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  CheckInCard(icon: string, title: string, subtitle: string, tint: string, surface: string, routeType: string) {
    Row({ space: 14 }) {
      Text(icon)
        .fontSize(22)
        .fontColor(tint)
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .backgroundColor(surface)
        .borderRadius(16)
      Column({ space: 4 }) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .width('100%')
        Text(subtitle)
          .fontSize(13)
          .fontColor(COLOR_SECONDARY)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(26)
        .fontColor('#A8B1AC')
    }
    .padding(16)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(20)
    .shadow({ radius: 12, color: '#0B0C2017', offsetY: 3 })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/CheckinDetailPage', params: { type: routeType } });
    })
  }

  @Builder
  RecordPage() {
    Scroll() {
      Column({ space: 20 }) {
        this.PageHeader(this.t('index_daily_checkin'), this.t('index_daily_checkin_subtitle'))

        Column({ space: 13 }) {
          Row() {
            Text(this.t('index_mood_question'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
            Blank()
            Text(this.moodLabel())
              .fontSize(13)
              .fontColor(COLOR_GREEN)
          }
          .width('100%')

          Row({ space: 8 }) {
            ForEach(['index_mood_tired', 'index_mood_low_short', 'index_mood_calm', 'index_mood_good', 'index_mood_great_short'],
              (label: string, index: number) => {
              Column({ space: 6 }) {
                Text(['😫', '😕', '😌', '🙂', '😄'][index])
                  .fontSize(22)
                  Text(this.t(label))
                  .fontSize(11)
                  .fontColor(this.mood === index + 1 ? Color.White : COLOR_SECONDARY)
              }
              .layoutWeight(1)
              .height(72)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.mood === index + 1 ? COLOR_GREEN : '#F1F5F2')
              .borderRadius(16)
              .onClick(() => this.setMood(index + 1))
            }, (label: string) => label)
          }
          .width('100%')
        }
        .padding(17)
        .backgroundColor(COLOR_CARD)
        .borderRadius(22)

        this.SectionTitle(this.t('index_quick_actions'), '')

        Row({ space: 14 }) {
          Column({ space: 9 }) {
            Text('💧')
              .fontSize(29)
            Text(this.t('index_drink_water'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
            Text(this.t('index_cups_format', this.waterCups))
              .fontSize(13)
              .fontColor(COLOR_SECONDARY)
            Button(this.t('index_add_cup'))
              .fontSize(13)
              .fontColor(COLOR_GREEN)
              .backgroundColor(COLOR_LIGHT_GREEN)
              .height(36)
              .borderRadius(18)
              .onClick(() => this.addWater())
          }
          .layoutWeight(1)
          .padding(17)
          .backgroundColor(COLOR_CARD)
          .borderRadius(22)

          Column({ space: 9 }) {
            Text(this.breathingActive ? '◌' : '🌿')
              .fontSize(29)
              .rotate({ angle: this.breathingActive ? 180 : 0 })
            Text(this.t('index_breathe'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
            Text(this.breathingActive ? this.t('index_seconds_format', this.breathingSeconds) : this.t('index_one_minute'))
              .fontSize(13)
              .fontColor(COLOR_SECONDARY)
            Button(this.t(this.breathingActive ? 'index_in_progress' : 'index_start'))
              .fontSize(13)
              .fontColor(COLOR_PURPLE)
              .backgroundColor('#EEE9FA')
              .height(36)
              .borderRadius(18)
              .enabled(!this.breathingActive)
              .onClick(() => this.startBreathing())
          }
          .layoutWeight(1)
          .padding(17)
          .backgroundColor(COLOR_CARD)
          .borderRadius(22)
        }
        .width('100%')

        this.SectionTitle(this.t('index_more_logs'), '')

        Column({ space: 12 }) {
          this.CheckInCard('☀', this.t('index_sunlight'), this.t('index_sunlight_help'), COLOR_ORANGE, '#FFF1E3', 'sunlight')
          this.CheckInCard('☕', this.t('index_caffeine'), this.t('index_caffeine_help'), '#9B6B48', '#F5E9E0', 'caffeine')
          this.CheckInCard('💊', this.t('index_medication'), this.t('index_medication_help'), COLOR_BLUE, '#E8EEFD', 'medication')
          this.CheckInCard('＋', this.t('index_symptoms'), this.t('index_symptoms_help'), '#D85C67', '#FCE8EA', 'symptom')
        }

        Text(this.t('index_emergency'))
          .fontSize(12)
          .fontColor('#8D5B45')
          .lineHeight(18)
          .padding(14)
          .width('100%')
          .backgroundColor('#FFF4EB')
          .borderRadius(16)
      }
      .padding({ left: 18, right: 18, top: 18, bottom: 110 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  TrendPage() {
    Scroll() {
      Column({ space: 22 }) {
        this.PageHeader(this.t('index_trends'), this.trendSubtitle())

        Column({ space: 18 }) {
          Row() {
            Column({ space: 3 }) {
              Text(this.t('index_week_steps'))
                .fontSize(14)
                .fontColor(COLOR_SECONDARY)
                .width('100%')
              Text(this.hasTrendData ? this.t('steps_format', this.weeklyStepTotal) : this.t('index_no_activity'))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.hasTrendData ? this.t('index_goal_days_format', this.weeklyGoalDays) : '--')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_GREEN)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .backgroundColor(COLOR_LIGHT_GREEN)
              .borderRadius(15)
          }
          .width('100%')

          Row({ space: 10 }) {
            ForEach(this.trendData, (point: TrendPoint) => {
              Column({ space: 7 }) {
                Text(this.shortSteps(point.steps))
                  .fontSize(9)
                  .fontColor(COLOR_SECONDARY)
                Column()
                  .width(18)
                  .height(Math.max(point.value, 6))
                  .linearGradient({
                    angle: 0,
                    colors: point.day === this.t('today_short') ? [[COLOR_GREEN, 0.0], ['#6BC49E', 1.0]] : [['#C9DAD1', 0.0], ['#E2EBE6', 1.0]]
                  })
                  .borderRadius(9)
                Text(point.day)
                  .fontSize(12)
                  .fontColor(point.day === this.t('today_short') ? COLOR_GREEN : COLOR_SECONDARY)
                  .fontWeight(point.day === this.t('today_short') ? FontWeight.Bold : FontWeight.Regular)
              }
              .layoutWeight(1)
              .height(130)
              .justifyContent(FlexAlign.End)
            }, (point: TrendPoint) => point.day)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .padding(18)
        .width('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(24)
        .shadow({ radius: 14, color: '#0B0C2017', offsetY: 4 })

        this.SectionTitle(this.t('index_health_summary'), this.healthUpdatedAt)

        Column({ space: 12 }) {
          Column({ space: 10 }) {
            Row() {
              Text(this.t('index_average_sleep'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT)
              Blank()
              Text(this.sleepRecordDays > 0 ? this.durationText(this.averageSleepMinutes) : '--')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_PURPLE)
              Text('›')
                .fontSize(22)
                .fontColor('#A8B1AC')
            }
            this.ProgressBar(Math.min(this.averageSleepMinutes, 480), 480, COLOR_PURPLE)
            Text(this.sleepRecordDays > 0 ? this.t('index_sleep_coverage_format', this.sleepRecordDays, this.sleepValue()) :
              this.t('index_sleep_no_records'))
              .fontSize(12)
              .fontColor(COLOR_SECONDARY)
              .width('100%')
          }
          .padding(17)
          .backgroundColor(COLOR_CARD)
          .borderRadius(20)
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/SleepDetailPage' });
          })

          Column({ space: 10 }) {
            Row() {
              Text(this.t('index_week_heart_rate'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT)
              Blank()
              Text(this.restingHeartRateDays > 0 ? this.t('heart_rate_format', this.averageRestingHeartRate) : '--')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#D85C67')
            }
            Text(this.restingHeartRateDays > 0 ? this.t('index_heart_coverage_format', this.restingHeartRateDays) :
              this.t('index_heart_no_records'))
              .fontSize(12)
              .fontColor(COLOR_SECONDARY)
              .width('100%')
          }
          .padding(17)
          .backgroundColor(COLOR_CARD)
          .borderRadius(20)

          Column({ space: 10 }) {
            Row() {
              Text(this.t('index_activity_goal'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT)
              Blank()
              Text(this.hasTrendData ? this.t('index_days_of_seven_format', this.weeklyGoalDays) : '--')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_BLUE)
            }
            this.ProgressBar(this.weeklyGoalDays, 7, COLOR_BLUE)
            Text(this.hasTrendData ? this.t('index_activity_summary_format', this.weeklyStepTotal, this.dailyStepGoal) :
              this.t('index_activity_empty'))
              .fontSize(12)
              .fontColor(COLOR_SECONDARY)
              .width('100%')
          }
          .padding(17)
          .backgroundColor(COLOR_CARD)
          .borderRadius(20)
        }

        Row({ space: 14 }) {
          Text('✦')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_GREEN)
            .width(42)
            .height(42)
            .textAlign(TextAlign.Center)
            .backgroundColor(COLOR_LIGHT_GREEN)
            .borderRadius(14)
          Column({ space: 5 }) {
            Text(this.t('index_week_insight'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
              .width('100%')
            Text(this.hasTrendData ?
              (this.weeklyGoalDays >= 4 ? this.t('index_insight_good') : this.t('index_insight_low')) :
              this.t('index_insight_empty'))
              .fontSize(13)
              .fontColor(COLOR_SECONDARY)
              .lineHeight(19)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .padding(17)
        .backgroundColor('#F0F8F4')
        .borderRadius(20)
      }
      .padding({ left: 18, right: 18, top: 18, bottom: 110 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  SettingRow(icon: string, title: string, subtitle: string) {
    Row({ space: 13 }) {
      Text(icon)
        .fontSize(18)
        .fontColor(COLOR_GREEN)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor(COLOR_LIGHT_GREEN)
        .borderRadius(13)
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT)
          .width('100%')
        Text(subtitle)
          .fontSize(12)
          .fontColor(COLOR_SECONDARY)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(25)
        .fontColor('#A8B1AC')
    }
    .padding({ left: 15, right: 15, top: 13, bottom: 13 })
    .width('100%')
  }

  @Builder
  ProfilePage() {
    Scroll() {
      Column({ space: 20 }) {
        this.PageHeader(this.t('index_profile'), this.t('index_profile_subtitle'))

        Row({ space: 15 }) {
          Text(this.t('index_avatar'))
            .fontSize(29)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(66)
            .height(66)
            .textAlign(TextAlign.Center)
            .linearGradient({ angle: 135, colors: [[COLOR_GREEN, 0.0], ['#6BC49E', 1.0]] })
            .borderRadius(22)
          Column({ space: 5 }) {
            Text(this.t('index_user_name'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT)
              .width('100%')
            Text(this.t('index_local_streak'))
              .fontSize(13)
              .fontColor(COLOR_SECONDARY)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('81')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_GREEN)
        }
        .padding(18)
        .width('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(24)

        this.SectionTitle(this.t('index_huawei_health'), this.t(this.healthAuthorized ? 'index_connected' : 'index_disconnected'))

        Column({ space: 13 }) {
          Row({ space: 13 }) {
            Text('♥')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(46)
              .height(46)
              .textAlign(TextAlign.Center)
              .backgroundColor('#D9323B')
              .borderRadius(15)
            Column({ space: 4 }) {
              Text(this.healthStatus)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Text(this.t('index_last_sync_format', this.healthUpdatedAt))
                .fontSize(12)
                .fontColor(COLOR_SECONDARY)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Row({ space: 9 }) {
            Button(this.t(this.healthLoading ? 'index_processing' :
              (this.healthAuthorized ? 'index_refresh' : 'index_connect_authorize')))
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(COLOR_GREEN)
              .borderRadius(18)
              .enabled(!this.healthLoading)
              .onClick(() => {
                if (this.healthAuthorized) {
                  this.refreshHuaweiHealth();
                } else {
                  this.connectHuaweiHealth();
                }
              })
            Button(this.t('index_open_health'))
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontColor('#D9323B')
              .backgroundColor('#FCEBEC')
              .borderRadius(18)
              .onClick(() => this.openHuaweiHealthPrivacy())
          }
          .width('100%')

          Text(this.t('index_health_privacy'))
            .fontSize(11)
            .fontColor(COLOR_SECONDARY)
            .lineHeight(17)
            .width('100%')

          if (this.healthAuthorized) {
            Button(this.t('index_revoke_health'))
              .fontSize(13)
              .fontColor('#B85A50')
              .backgroundColor(Color.Transparent)
              .height(34)
              .onClick(() => this.disconnectHuaweiHealth())
          }
        }
        .padding(17)
        .width('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(22)

        this.SectionTitle(this.t('index_daily_goal'), '')

        Column({ space: 15 }) {
          Row() {
            Text(this.t('index_step_goal'))
              .fontSize(16)
              .fontColor(COLOR_TEXT)
            Blank()
            Text(this.t('steps_format', this.dailyStepGoal))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_GREEN)
          }
          .width('100%')

          Row({ space: 9 }) {
            ForEach([6000, 8000, 10000], (goal: number) => {
              Button(`${goal}`)
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .fontColor(this.dailyStepGoal === goal ? Color.White : COLOR_SECONDARY)
                .backgroundColor(this.dailyStepGoal === goal ? COLOR_GREEN : '#EEF2EF')
                .borderRadius(19)
                .onClick(() => {
                  this.dailyStepGoal = goal;
                  this.persistState();
                })
            }, (goal: number) => `${goal}`)
          }
          .width('100%')

          Row() {
            Text(this.t('reminder_title'))
              .fontSize(16)
              .fontColor(COLOR_TEXT)
            Blank()
            Text(this.t('index_reminder_types'))
              .fontSize(13)
              .fontColor(COLOR_SECONDARY)
            Text('›')
              .fontSize(22)
              .fontColor('#A8B1AC')
          }
          .width('100%')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ReminderSettingsPage' });
          })
        }
        .padding(17)
        .width('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(22)

        this.SectionTitle(this.t('index_settings'), '')

        Column() {
          Column() {
            this.SettingRow('◉', this.t('privacy_page_title'), this.t('index_privacy_setting'))
          }
          .width('100%')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPage' });
          })
          Divider()
            .color('#EDF0EE')
            .margin({ left: 68 })
          this.SettingRow('⚙', this.t('index_device_connection'), this.t(this.healthAuthorized ?
            'index_health_connected' : 'index_device_disconnected'))
          Divider()
            .color('#EDF0EE')
            .margin({ left: 68 })
          this.SettingRow('?', this.t('index_help_feedback'), this.t('index_help_subtitle'))
        }
        .width('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(22)

        Button(this.t('index_reset_today'))
          .fontSize(15)
          .fontColor('#B85A50')
          .backgroundColor('#FBEDEB')
          .width('100%')
          .height(48)
          .borderRadius(18)
          .onClick(() => {
            this.resetConfirmationVisible = true;
          })

        Column({ space: 7 }) {
          Text(this.t('index_brand_footer'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_SECONDARY)
          Text(this.t('index_footer_disclaimer_format', this.lastSavedText))
            .fontSize(11)
            .fontColor('#909A95')
        }
        .width('100%')
      }
      .padding({ left: 18, right: 18, top: 18, bottom: 110 })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  BottomNavigation() {
    Row() {
      ForEach([
        ['⌂', this.t('index_tab_home')], ['＋', this.t('index_tab_record')],
        ['↗', this.t('index_tab_trends')], ['●', this.t('index_tab_profile')]
      ], (item: string[], index: number) => {
        Column({ space: 4 }) {
          Text(item[0])
            .fontSize(index === 1 ? 24 : 19)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedTab === index ? COLOR_GREEN : '#8A9690')
          Text(item[1])
            .fontSize(11)
            .fontWeight(this.selectedTab === index ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.selectedTab === index ? COLOR_GREEN : '#8A9690')
        }
        .layoutWeight(1)
        .height(58)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.selectedTab = index;
        })
      }, (item: string[]) => item[1])
    }
    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
    .width('94%')
    .height(70)
    .backgroundColor('#FAFFFFFF')
    .borderRadius(24)
    .shadow({ radius: 26, color: '#29091610', offsetY: 2 })
    .margin({ bottom: 12 })
  }

  @Builder
  ResetConfirmation() {
    Column() {
      Column({ space: 14 }) {
        Text(this.t('index_reset_title'))
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .width('100%')
        Text(this.t('index_reset_body'))
          .fontSize(14)
          .fontColor(COLOR_SECONDARY)
          .lineHeight(21)
          .width('100%')
        Row({ space: 10 }) {
          Button(this.t('cancel'))
            .layoutWeight(1)
            .height(44)
            .fontColor(COLOR_SECONDARY)
            .backgroundColor('#EEF2EF')
            .borderRadius(18)
            .onClick(() => {
              this.resetConfirmationVisible = false;
            })
          Button(this.t('index_confirm_reset'))
            .layoutWeight(1)
            .height(44)
            .fontColor(Color.White)
            .backgroundColor('#B85A50')
            .borderRadius(18)
            .onClick(() => {
              this.resetToday();
              this.resetConfirmationVisible = false;
            })
        }
        .width('100%')
      }
      .padding(20)
      .width('84%')
      .backgroundColor(Color.White)
      .borderRadius(24)
      .shadow({ radius: 30, color: '#44000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#52000000')
    .onClick(() => {
      this.resetConfirmationVisible = false;
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.selectedTab === 0) {
          this.HomePage()
        } else if (this.selectedTab === 1) {
          this.RecordPage()
        } else if (this.selectedTab === 2) {
          this.TrendPage()
        } else {
          this.ProfilePage()
        }
      }
      .width('100%')
      .height('100%')
      .linearGradient({ angle: 180, colors: [['#F6FAF7', 0.0], [COLOR_BACKGROUND, 1.0]] })

      this.BottomNavigation()

      if (this.resetConfirmationVisible) {
        this.ResetConfirmation()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BACKGROUND)
  }
}
