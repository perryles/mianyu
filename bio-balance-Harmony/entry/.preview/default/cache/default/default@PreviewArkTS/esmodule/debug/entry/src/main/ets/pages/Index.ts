if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    selectedTab?: number;
    waterCups?: number;
    steps?: number;
    mood?: number;
    actionCompleted?: boolean;
    notificationEnabled?: boolean;
    dailyStepGoal?: number;
    breathingSeconds?: number;
    breathingActive?: boolean;
    loaded?: boolean;
    lastSavedText?: string;
    resetConfirmationVisible?: boolean;
    restingHeartRate?: number;
    sleepMinutes?: number;
    sleepScore?: number;
    hasSteps?: boolean;
    hasRestingHeartRate?: boolean;
    hasSleep?: boolean;
    healthAuthorized?: boolean;
    healthLoading?: boolean;
    healthStatus?: string;
    healthUpdatedAt?: string;
    hasTrendData?: boolean;
    weeklyStepTotal?: number;
    weeklyGoalDays?: number;
    averageRestingHeartRate?: number;
    restingHeartRateDays?: number;
    averageSleepMinutes?: number;
    sleepRecordDays?: number;
    trendData?: TrendPoint[];
    dataStore?: preferences.Preferences | undefined;
    breathingTimer?: number;
    healthService?: HuaweiHealthService;
}
import bundleManager from "@ohos:bundle.bundleManager";
import type common from "@ohos:app.ability.common";
import preferences from "@ohos:data.preferences";
import { HealthScoreEngine } from "@normalized:N&&&entry/src/main/ets/model/HealthScoreEngine&";
import { HuaweiHealthService } from "@normalized:N&&&entry/src/main/ets/service/HuaweiHealthService&";
import type { HealthServiceResult, HuaweiHealthSnapshot } from "@normalized:N&&&entry/src/main/ets/service/HuaweiHealthService&";
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
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__selectedTab = new ObservedPropertySimplePU(0, this, "selectedTab");
        this.__waterCups = new ObservedPropertySimplePU(4, this, "waterCups");
        this.__steps = new ObservedPropertySimplePU(0, this, "steps");
        this.__mood = new ObservedPropertySimplePU(3, this, "mood");
        this.__actionCompleted = new ObservedPropertySimplePU(false, this, "actionCompleted");
        this.__notificationEnabled = new ObservedPropertySimplePU(true, this, "notificationEnabled");
        this.__dailyStepGoal = new ObservedPropertySimplePU(8000, this, "dailyStepGoal");
        this.__breathingSeconds = new ObservedPropertySimplePU(60, this, "breathingSeconds");
        this.__breathingActive = new ObservedPropertySimplePU(false, this, "breathingActive");
        this.__loaded = new ObservedPropertySimplePU(false, this, "loaded");
        this.__lastSavedText = new ObservedPropertySimplePU('', this, "lastSavedText");
        this.__resetConfirmationVisible = new ObservedPropertySimplePU(false, this, "resetConfirmationVisible");
        this.__restingHeartRate = new ObservedPropertySimplePU(0, this, "restingHeartRate");
        this.__sleepMinutes = new ObservedPropertySimplePU(0, this, "sleepMinutes");
        this.__sleepScore = new ObservedPropertySimplePU(0, this, "sleepScore");
        this.__hasSteps = new ObservedPropertySimplePU(false, this, "hasSteps");
        this.__hasRestingHeartRate = new ObservedPropertySimplePU(false, this, "hasRestingHeartRate");
        this.__hasSleep = new ObservedPropertySimplePU(false, this, "hasSleep");
        this.__healthAuthorized = new ObservedPropertySimplePU(false, this, "healthAuthorized");
        this.__healthLoading = new ObservedPropertySimplePU(false, this, "healthLoading");
        this.__healthStatus = new ObservedPropertySimplePU('', this, "healthStatus");
        this.__healthUpdatedAt = new ObservedPropertySimplePU('', this, "healthUpdatedAt");
        this.__hasTrendData = new ObservedPropertySimplePU(false, this, "hasTrendData");
        this.__weeklyStepTotal = new ObservedPropertySimplePU(0, this, "weeklyStepTotal");
        this.__weeklyGoalDays = new ObservedPropertySimplePU(0, this, "weeklyGoalDays");
        this.__averageRestingHeartRate = new ObservedPropertySimplePU(0, this, "averageRestingHeartRate");
        this.__restingHeartRateDays = new ObservedPropertySimplePU(0, this, "restingHeartRateDays");
        this.__averageSleepMinutes = new ObservedPropertySimplePU(0, this, "averageSleepMinutes");
        this.__sleepRecordDays = new ObservedPropertySimplePU(0, this, "sleepRecordDays");
        this.__trendData = new ObservedPropertyObjectPU([
            { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 },
            { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 }, { day: '', value: 0, steps: 0 },
            { day: '', value: 0, steps: 0 }
        ], this, "trendData");
        this.dataStore = undefined;
        this.breathingTimer = -1;
        this.healthService = new HuaweiHealthService();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.selectedTab !== undefined) {
            this.selectedTab = params.selectedTab;
        }
        if (params.waterCups !== undefined) {
            this.waterCups = params.waterCups;
        }
        if (params.steps !== undefined) {
            this.steps = params.steps;
        }
        if (params.mood !== undefined) {
            this.mood = params.mood;
        }
        if (params.actionCompleted !== undefined) {
            this.actionCompleted = params.actionCompleted;
        }
        if (params.notificationEnabled !== undefined) {
            this.notificationEnabled = params.notificationEnabled;
        }
        if (params.dailyStepGoal !== undefined) {
            this.dailyStepGoal = params.dailyStepGoal;
        }
        if (params.breathingSeconds !== undefined) {
            this.breathingSeconds = params.breathingSeconds;
        }
        if (params.breathingActive !== undefined) {
            this.breathingActive = params.breathingActive;
        }
        if (params.loaded !== undefined) {
            this.loaded = params.loaded;
        }
        if (params.lastSavedText !== undefined) {
            this.lastSavedText = params.lastSavedText;
        }
        if (params.resetConfirmationVisible !== undefined) {
            this.resetConfirmationVisible = params.resetConfirmationVisible;
        }
        if (params.restingHeartRate !== undefined) {
            this.restingHeartRate = params.restingHeartRate;
        }
        if (params.sleepMinutes !== undefined) {
            this.sleepMinutes = params.sleepMinutes;
        }
        if (params.sleepScore !== undefined) {
            this.sleepScore = params.sleepScore;
        }
        if (params.hasSteps !== undefined) {
            this.hasSteps = params.hasSteps;
        }
        if (params.hasRestingHeartRate !== undefined) {
            this.hasRestingHeartRate = params.hasRestingHeartRate;
        }
        if (params.hasSleep !== undefined) {
            this.hasSleep = params.hasSleep;
        }
        if (params.healthAuthorized !== undefined) {
            this.healthAuthorized = params.healthAuthorized;
        }
        if (params.healthLoading !== undefined) {
            this.healthLoading = params.healthLoading;
        }
        if (params.healthStatus !== undefined) {
            this.healthStatus = params.healthStatus;
        }
        if (params.healthUpdatedAt !== undefined) {
            this.healthUpdatedAt = params.healthUpdatedAt;
        }
        if (params.hasTrendData !== undefined) {
            this.hasTrendData = params.hasTrendData;
        }
        if (params.weeklyStepTotal !== undefined) {
            this.weeklyStepTotal = params.weeklyStepTotal;
        }
        if (params.weeklyGoalDays !== undefined) {
            this.weeklyGoalDays = params.weeklyGoalDays;
        }
        if (params.averageRestingHeartRate !== undefined) {
            this.averageRestingHeartRate = params.averageRestingHeartRate;
        }
        if (params.restingHeartRateDays !== undefined) {
            this.restingHeartRateDays = params.restingHeartRateDays;
        }
        if (params.averageSleepMinutes !== undefined) {
            this.averageSleepMinutes = params.averageSleepMinutes;
        }
        if (params.sleepRecordDays !== undefined) {
            this.sleepRecordDays = params.sleepRecordDays;
        }
        if (params.trendData !== undefined) {
            this.trendData = params.trendData;
        }
        if (params.dataStore !== undefined) {
            this.dataStore = params.dataStore;
        }
        if (params.breathingTimer !== undefined) {
            this.breathingTimer = params.breathingTimer;
        }
        if (params.healthService !== undefined) {
            this.healthService = params.healthService;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__selectedTab.purgeDependencyOnElmtId(rmElmtId);
        this.__waterCups.purgeDependencyOnElmtId(rmElmtId);
        this.__steps.purgeDependencyOnElmtId(rmElmtId);
        this.__mood.purgeDependencyOnElmtId(rmElmtId);
        this.__actionCompleted.purgeDependencyOnElmtId(rmElmtId);
        this.__notificationEnabled.purgeDependencyOnElmtId(rmElmtId);
        this.__dailyStepGoal.purgeDependencyOnElmtId(rmElmtId);
        this.__breathingSeconds.purgeDependencyOnElmtId(rmElmtId);
        this.__breathingActive.purgeDependencyOnElmtId(rmElmtId);
        this.__loaded.purgeDependencyOnElmtId(rmElmtId);
        this.__lastSavedText.purgeDependencyOnElmtId(rmElmtId);
        this.__resetConfirmationVisible.purgeDependencyOnElmtId(rmElmtId);
        this.__restingHeartRate.purgeDependencyOnElmtId(rmElmtId);
        this.__sleepMinutes.purgeDependencyOnElmtId(rmElmtId);
        this.__sleepScore.purgeDependencyOnElmtId(rmElmtId);
        this.__hasSteps.purgeDependencyOnElmtId(rmElmtId);
        this.__hasRestingHeartRate.purgeDependencyOnElmtId(rmElmtId);
        this.__hasSleep.purgeDependencyOnElmtId(rmElmtId);
        this.__healthAuthorized.purgeDependencyOnElmtId(rmElmtId);
        this.__healthLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__healthStatus.purgeDependencyOnElmtId(rmElmtId);
        this.__healthUpdatedAt.purgeDependencyOnElmtId(rmElmtId);
        this.__hasTrendData.purgeDependencyOnElmtId(rmElmtId);
        this.__weeklyStepTotal.purgeDependencyOnElmtId(rmElmtId);
        this.__weeklyGoalDays.purgeDependencyOnElmtId(rmElmtId);
        this.__averageRestingHeartRate.purgeDependencyOnElmtId(rmElmtId);
        this.__restingHeartRateDays.purgeDependencyOnElmtId(rmElmtId);
        this.__averageSleepMinutes.purgeDependencyOnElmtId(rmElmtId);
        this.__sleepRecordDays.purgeDependencyOnElmtId(rmElmtId);
        this.__trendData.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__selectedTab.aboutToBeDeleted();
        this.__waterCups.aboutToBeDeleted();
        this.__steps.aboutToBeDeleted();
        this.__mood.aboutToBeDeleted();
        this.__actionCompleted.aboutToBeDeleted();
        this.__notificationEnabled.aboutToBeDeleted();
        this.__dailyStepGoal.aboutToBeDeleted();
        this.__breathingSeconds.aboutToBeDeleted();
        this.__breathingActive.aboutToBeDeleted();
        this.__loaded.aboutToBeDeleted();
        this.__lastSavedText.aboutToBeDeleted();
        this.__resetConfirmationVisible.aboutToBeDeleted();
        this.__restingHeartRate.aboutToBeDeleted();
        this.__sleepMinutes.aboutToBeDeleted();
        this.__sleepScore.aboutToBeDeleted();
        this.__hasSteps.aboutToBeDeleted();
        this.__hasRestingHeartRate.aboutToBeDeleted();
        this.__hasSleep.aboutToBeDeleted();
        this.__healthAuthorized.aboutToBeDeleted();
        this.__healthLoading.aboutToBeDeleted();
        this.__healthStatus.aboutToBeDeleted();
        this.__healthUpdatedAt.aboutToBeDeleted();
        this.__hasTrendData.aboutToBeDeleted();
        this.__weeklyStepTotal.aboutToBeDeleted();
        this.__weeklyGoalDays.aboutToBeDeleted();
        this.__averageRestingHeartRate.aboutToBeDeleted();
        this.__restingHeartRateDays.aboutToBeDeleted();
        this.__averageSleepMinutes.aboutToBeDeleted();
        this.__sleepRecordDays.aboutToBeDeleted();
        this.__trendData.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __selectedTab: ObservedPropertySimplePU<number>;
    get selectedTab() {
        return this.__selectedTab.get();
    }
    set selectedTab(newValue: number) {
        this.__selectedTab.set(newValue);
    }
    private __waterCups: ObservedPropertySimplePU<number>;
    get waterCups() {
        return this.__waterCups.get();
    }
    set waterCups(newValue: number) {
        this.__waterCups.set(newValue);
    }
    private __steps: ObservedPropertySimplePU<number>;
    get steps() {
        return this.__steps.get();
    }
    set steps(newValue: number) {
        this.__steps.set(newValue);
    }
    private __mood: ObservedPropertySimplePU<number>;
    get mood() {
        return this.__mood.get();
    }
    set mood(newValue: number) {
        this.__mood.set(newValue);
    }
    private __actionCompleted: ObservedPropertySimplePU<boolean>;
    get actionCompleted() {
        return this.__actionCompleted.get();
    }
    set actionCompleted(newValue: boolean) {
        this.__actionCompleted.set(newValue);
    }
    private __notificationEnabled: ObservedPropertySimplePU<boolean>;
    get notificationEnabled() {
        return this.__notificationEnabled.get();
    }
    set notificationEnabled(newValue: boolean) {
        this.__notificationEnabled.set(newValue);
    }
    private __dailyStepGoal: ObservedPropertySimplePU<number>;
    get dailyStepGoal() {
        return this.__dailyStepGoal.get();
    }
    set dailyStepGoal(newValue: number) {
        this.__dailyStepGoal.set(newValue);
    }
    private __breathingSeconds: ObservedPropertySimplePU<number>;
    get breathingSeconds() {
        return this.__breathingSeconds.get();
    }
    set breathingSeconds(newValue: number) {
        this.__breathingSeconds.set(newValue);
    }
    private __breathingActive: ObservedPropertySimplePU<boolean>;
    get breathingActive() {
        return this.__breathingActive.get();
    }
    set breathingActive(newValue: boolean) {
        this.__breathingActive.set(newValue);
    }
    private __loaded: ObservedPropertySimplePU<boolean>;
    get loaded() {
        return this.__loaded.get();
    }
    set loaded(newValue: boolean) {
        this.__loaded.set(newValue);
    }
    private __lastSavedText: ObservedPropertySimplePU<string>;
    get lastSavedText() {
        return this.__lastSavedText.get();
    }
    set lastSavedText(newValue: string) {
        this.__lastSavedText.set(newValue);
    }
    private __resetConfirmationVisible: ObservedPropertySimplePU<boolean>;
    get resetConfirmationVisible() {
        return this.__resetConfirmationVisible.get();
    }
    set resetConfirmationVisible(newValue: boolean) {
        this.__resetConfirmationVisible.set(newValue);
    }
    private __restingHeartRate: ObservedPropertySimplePU<number>;
    get restingHeartRate() {
        return this.__restingHeartRate.get();
    }
    set restingHeartRate(newValue: number) {
        this.__restingHeartRate.set(newValue);
    }
    private __sleepMinutes: ObservedPropertySimplePU<number>;
    get sleepMinutes() {
        return this.__sleepMinutes.get();
    }
    set sleepMinutes(newValue: number) {
        this.__sleepMinutes.set(newValue);
    }
    private __sleepScore: ObservedPropertySimplePU<number>;
    get sleepScore() {
        return this.__sleepScore.get();
    }
    set sleepScore(newValue: number) {
        this.__sleepScore.set(newValue);
    }
    private __hasSteps: ObservedPropertySimplePU<boolean>;
    get hasSteps() {
        return this.__hasSteps.get();
    }
    set hasSteps(newValue: boolean) {
        this.__hasSteps.set(newValue);
    }
    private __hasRestingHeartRate: ObservedPropertySimplePU<boolean>;
    get hasRestingHeartRate() {
        return this.__hasRestingHeartRate.get();
    }
    set hasRestingHeartRate(newValue: boolean) {
        this.__hasRestingHeartRate.set(newValue);
    }
    private __hasSleep: ObservedPropertySimplePU<boolean>;
    get hasSleep() {
        return this.__hasSleep.get();
    }
    set hasSleep(newValue: boolean) {
        this.__hasSleep.set(newValue);
    }
    private __healthAuthorized: ObservedPropertySimplePU<boolean>;
    get healthAuthorized() {
        return this.__healthAuthorized.get();
    }
    set healthAuthorized(newValue: boolean) {
        this.__healthAuthorized.set(newValue);
    }
    private __healthLoading: ObservedPropertySimplePU<boolean>;
    get healthLoading() {
        return this.__healthLoading.get();
    }
    set healthLoading(newValue: boolean) {
        this.__healthLoading.set(newValue);
    }
    private __healthStatus: ObservedPropertySimplePU<string>;
    get healthStatus() {
        return this.__healthStatus.get();
    }
    set healthStatus(newValue: string) {
        this.__healthStatus.set(newValue);
    }
    private __healthUpdatedAt: ObservedPropertySimplePU<string>;
    get healthUpdatedAt() {
        return this.__healthUpdatedAt.get();
    }
    set healthUpdatedAt(newValue: string) {
        this.__healthUpdatedAt.set(newValue);
    }
    private __hasTrendData: ObservedPropertySimplePU<boolean>;
    get hasTrendData() {
        return this.__hasTrendData.get();
    }
    set hasTrendData(newValue: boolean) {
        this.__hasTrendData.set(newValue);
    }
    private __weeklyStepTotal: ObservedPropertySimplePU<number>;
    get weeklyStepTotal() {
        return this.__weeklyStepTotal.get();
    }
    set weeklyStepTotal(newValue: number) {
        this.__weeklyStepTotal.set(newValue);
    }
    private __weeklyGoalDays: ObservedPropertySimplePU<number>;
    get weeklyGoalDays() {
        return this.__weeklyGoalDays.get();
    }
    set weeklyGoalDays(newValue: number) {
        this.__weeklyGoalDays.set(newValue);
    }
    private __averageRestingHeartRate: ObservedPropertySimplePU<number>;
    get averageRestingHeartRate() {
        return this.__averageRestingHeartRate.get();
    }
    set averageRestingHeartRate(newValue: number) {
        this.__averageRestingHeartRate.set(newValue);
    }
    private __restingHeartRateDays: ObservedPropertySimplePU<number>;
    get restingHeartRateDays() {
        return this.__restingHeartRateDays.get();
    }
    set restingHeartRateDays(newValue: number) {
        this.__restingHeartRateDays.set(newValue);
    }
    private __averageSleepMinutes: ObservedPropertySimplePU<number>;
    get averageSleepMinutes() {
        return this.__averageSleepMinutes.get();
    }
    set averageSleepMinutes(newValue: number) {
        this.__averageSleepMinutes.set(newValue);
    }
    private __sleepRecordDays: ObservedPropertySimplePU<number>;
    get sleepRecordDays() {
        return this.__sleepRecordDays.get();
    }
    set sleepRecordDays(newValue: number) {
        this.__sleepRecordDays.set(newValue);
    }
    private __trendData: ObservedPropertyObjectPU<TrendPoint[]>;
    get trendData() {
        return this.__trendData.get();
    }
    set trendData(newValue: TrendPoint[]) {
        this.__trendData.set(newValue);
    }
    private dataStore: preferences.Preferences | undefined;
    private breathingTimer: number;
    private healthService: HuaweiHealthService;
    aboutToAppear(): void {
        this.lastSavedText = this.t('index_data_local');
        this.healthStatus = this.t('index_health_waiting');
        this.healthUpdatedAt = this.t('index_not_synced');
        this.loadLocalState();
    }
    private t(name: string, first?: string | number, second?: string | number, third?: string | number): string {
        const context = this.getUIContext().getHostContext();
        if (context === undefined)
            return '';
        if (first === undefined)
            return context.resourceManager.getStringByNameSync(name);
        if (second === undefined)
            return context.resourceManager.getStringByNameSync(name, first);
        if (third === undefined)
            return context.resourceManager.getStringByNameSync(name, first, second);
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
            }
            else {
                this.persistState();
            }
            this.loaded = true;
            this.initializeHuaweiHealth();
        }
        catch (error) {
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
        }
        catch (error) {
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
        }
        catch (error) {
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
            }
            else {
                this.healthStatus = this.t('index_health_install');
            }
        }
        catch (error) {
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
    PageHeader(title: string, subtitle: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 5 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(454:5)", "entry");
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(455:7)", "entry");
            Text.fontSize(29);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(subtitle);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(460:7)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
    }
    SectionTitle(title: string, detail: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(471:5)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(472:7)", "entry");
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(476:7)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (detail.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(detail);
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(478:9)", "entry");
                        Text.fontSize(13);
                        Text.fontColor(COLOR_GREEN);
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    MetricCard(icon: string, label: string, value: string, detail: string, tint: string, surface: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(488:5)", "entry");
            Column.alignItems(HorizontalAlign.Start);
            Column.padding(15);
            Column.height(138);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
            Column.shadow({ radius: 16, color: '#100C2017', offsetY: 5 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(489:7)", "entry");
            Row.width('100%');
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(icon);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(490:9)", "entry");
            Text.fontSize(21);
            Text.width(38);
            Text.height(38);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(surface);
            Text.borderRadius(12);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(497:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(detail);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(498:9)", "entry");
            Text.fontSize(11);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(tint);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(value);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(506:7)", "entry");
            Text.fontSize(25);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(511:7)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
    }
    ProgressBar(value: number, total: number, tint: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Start });
            Stack.debugLine("entry/src/main/ets/pages/Index.ets(526:5)", "entry");
            Stack.width('100%');
            Stack.height(8);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(527:7)", "entry");
            Row.height(8);
            Row.width('100%');
            Row.backgroundColor('#EAEFEB');
            Row.borderRadius(4);
        }, Row);
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(532:7)", "entry");
            Row.height(8);
            Row.width(`${Math.min(value / total, 1) * 100}%`);
            Row.backgroundColor(tint);
            Row.borderRadius(4);
        }, Row);
        Row.pop();
        Stack.pop();
    }
    HomePage(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/Index.ets(544:5)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
            Scroll.height('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 22 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(545:7)", "entry");
            Column.width('100%');
            Column.padding({ left: 18, right: 18, top: 18, bottom: 110 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 5 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(546:9)", "entry");
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.dateTitle());
            Text.debugLine("entry/src/main/ets/pages/Index.ets(547:11)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_GREEN);
            Text.fontWeight(FontWeight.Medium);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_greeting_format', this.greeting()));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(552:11)", "entry");
            Text.fontSize(28);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 18 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(560:9)", "entry");
            Row.padding(20);
            Row.width('100%');
            Row.linearGradient({ angle: 135, colors: [[COLOR_GREEN, 0.0], ['#45AF82', 1.0]] });
            Row.borderRadius(28);
            Row.shadow({ radius: 22, color: '#331E8E63', offsetY: 9 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Center });
            Stack.debugLine("entry/src/main/ets/pages/Index.ets(561:11)", "entry");
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Circle.create({ width: 112, height: 112 });
            Circle.debugLine("entry/src/main/ets/pages/Index.ets(562:13)", "entry");
            Circle.fill('#FFFFFF55');
            Circle.stroke('#FFFFFF88');
            Circle.strokeWidth(1);
        }, Circle);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 0 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(566:13)", "entry");
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.healthScore()}`);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(567:15)", "entry");
            Text.fontSize(39);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(Color.White);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_today_status'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(571:15)", "entry");
            Text.fontSize(12);
            Text.fontColor('#E8FFF4');
        }, Text);
        Text.pop();
        Column.pop();
        Stack.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 9 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(577:11)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.healthSummaryTitle());
            Text.debugLine("entry/src/main/ets/pages/Index.ets(578:13)", "entry");
            Text.fontSize(21);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(Color.White);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.healthSummaryDetail());
            Text.debugLine("entry/src/main/ets/pages/Index.ets(583:13)", "entry");
            Text.fontSize(14);
            Text.fontColor('#E9FFF5');
            Text.lineHeight(21);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_local_assessment'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(588:13)", "entry");
            Text.fontSize(11);
            Text.fontColor('#CFF4E3');
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        this.SectionTitle.bind(this)(this.t('index_health_overview'), this.t('index_today'));
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Grid.create();
            Grid.debugLine("entry/src/main/ets/pages/Index.ets(604:9)", "entry");
            Grid.columnsTemplate('1fr 1fr');
            Grid.columnsGap(12);
            Grid.rowsGap(12);
            Grid.width('100%');
            Grid.height(288);
        }, Grid);
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
                GridItem.debugLine("entry/src/main/ets/pages/Index.ets(605:11)", "entry");
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.MetricCard.bind(this)('♥', this.t('index_resting_heart_rate'), this.hasRestingHeartRate ?
                    this.t('heart_rate_format', this.restingHeartRate) : '--', this.t(this.healthAuthorized ? 'index_health_source' : 'index_pending_auth'), '#D85C67', '#FCE8EA');
                GridItem.pop();
            };
            observedDeepRender();
        }
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
                GridItem.onClick(() => {
                    this.getUIContext().getRouter().pushUrl({ url: 'pages/SleepDetailPage' });
                });
                GridItem.debugLine("entry/src/main/ets/pages/Index.ets(610:11)", "entry");
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.MetricCard.bind(this)('☾', this.t('index_sleep'), this.sleepValue(), this.hasSleep && this.sleepScore > 0 ? this.t('score_format', this.sleepScore) :
                    this.t('index_health_source'), COLOR_PURPLE, '#EEE9FA');
                GridItem.pop();
            };
            observedDeepRender();
        }
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
                GridItem.debugLine("entry/src/main/ets/pages/Index.ets(618:11)", "entry");
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.MetricCard.bind(this)('👟', this.t('index_today_steps'), this.hasSteps ? `${this.steps}` : '--', this.healthAuthorized ? `${HealthScoreEngine.percentage(this.steps, this.dailyStepGoal)}%` :
                    this.t('index_pending_auth'), COLOR_BLUE, '#E8EEFD');
                GridItem.pop();
            };
            observedDeepRender();
        }
        {
            const itemCreation2 = (elmtId, isInitialRender) => {
                GridItem.create(() => { }, false);
                GridItem.debugLine("entry/src/main/ets/pages/Index.ets(623:11)", "entry");
            };
            const observedDeepRender = () => {
                this.observeComponentCreation2(itemCreation2, GridItem);
                this.MetricCard.bind(this)('💧', this.t('index_water'), this.t('index_cups_format', this.waterCups), this.t(this.waterCups >= 8 ? 'index_goal_met' : 'index_continue'), COLOR_GREEN, COLOR_LIGHT_GREEN);
                GridItem.pop();
            };
            observedDeepRender();
        }
        Grid.pop();
        this.SectionTitle.bind(this)(this.t('index_today_priority'), this.t(this.actionCompleted ? 'index_completed' : 'index_one_item'));
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 14 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(636:9)", "entry");
            Row.padding(17);
            Row.width('100%');
            Row.backgroundColor(COLOR_CARD);
            Row.borderRadius(22);
            Row.shadow({ radius: 14, color: '#0D0C2017', offsetY: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.actionCompleted ? '✓' : '↗');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(637:11)", "entry");
            Text.fontSize(22);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.actionCompleted ? Color.White : COLOR_GREEN);
            Text.width(50);
            Text.height(50);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(this.actionCompleted ? COLOR_GREEN : COLOR_LIGHT_GREEN);
            Text.borderRadius(17);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(646:11)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t(this.actionCompleted ? 'index_action_done' : 'index_action_stretch'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(647:13)", "entry");
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t(this.actionCompleted ? 'index_action_done_help' : 'index_action_stretch_help'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(652:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(19);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t(this.actionCompleted ? 'index_undo' : 'index_complete'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(660:11)", "entry");
            Button.fontSize(13);
            Button.fontColor(this.actionCompleted ? COLOR_SECONDARY : Color.White);
            Button.backgroundColor(this.actionCompleted ? '#EDF1EE' : COLOR_GREEN);
            Button.height(38);
            Button.borderRadius(19);
            Button.onClick(() => this.toggleAction());
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(674:9)", "entry");
            Row.padding(16);
            Row.width('100%');
            Row.backgroundColor('#F8FCFA');
            Row.border({ width: 1, color: '#DDEBE3' });
            Row.borderRadius(20);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('＋');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(675:11)", "entry");
            Text.fontSize(24);
            Text.fontColor(COLOR_GREEN);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(678:11)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_quick_water'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(679:13)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_water_goal_format', this.waterCups));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(684:13)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t('index_record'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(691:11)", "entry");
            Button.fontSize(13);
            Button.fontColor(COLOR_GREEN);
            Button.backgroundColor(COLOR_LIGHT_GREEN);
            Button.height(38);
            Button.borderRadius(19);
            Button.onClick(() => this.addWater());
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
        Scroll.pop();
    }
    CheckInCard(icon: string, title: string, subtitle: string, tint: string, surface: string, routeType: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 14 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(715:5)", "entry");
            Row.padding(16);
            Row.width('100%');
            Row.backgroundColor(COLOR_CARD);
            Row.borderRadius(20);
            Row.shadow({ radius: 12, color: '#0B0C2017', offsetY: 3 });
            Row.onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/CheckinDetailPage', params: { type: routeType } });
            });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(icon);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(716:7)", "entry");
            Text.fontSize(22);
            Text.fontColor(tint);
            Text.width(48);
            Text.height(48);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(surface);
            Text.borderRadius(16);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(724:7)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(725:9)", "entry");
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(subtitle);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(730:9)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('›');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(737:7)", "entry");
            Text.fontSize(26);
            Text.fontColor('#A8B1AC');
        }, Text);
        Text.pop();
        Row.pop();
    }
    RecordPage(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/Index.ets(753:5)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
            Scroll.height('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 20 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(754:7)", "entry");
            Column.padding({ left: 18, right: 18, top: 18, bottom: 110 });
            Column.width('100%');
        }, Column);
        this.PageHeader.bind(this)(this.t('index_daily_checkin'), this.t('index_daily_checkin_subtitle'));
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 13 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(757:9)", "entry");
            Column.padding(17);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(758:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_mood_question'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(759:13)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(763:13)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.moodLabel());
            Text.debugLine("entry/src/main/ets/pages/Index.ets(764:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_GREEN);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(770:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = (_item, index: number) => {
                const label = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 6 });
                    Column.debugLine("entry/src/main/ets/pages/Index.ets(773:15)", "entry");
                    Column.layoutWeight(1);
                    Column.height(72);
                    Column.justifyContent(FlexAlign.Center);
                    Column.backgroundColor(this.mood === index + 1 ? COLOR_GREEN : '#F1F5F2');
                    Column.borderRadius(16);
                    Column.onClick(() => this.setMood(index + 1));
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(['😫', '😕', '😌', '🙂', '😄'][index]);
                    Text.debugLine("entry/src/main/ets/pages/Index.ets(774:17)", "entry");
                    Text.fontSize(22);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.t(label));
                    Text.debugLine("entry/src/main/ets/pages/Index.ets(776:19)", "entry");
                    Text.fontSize(11);
                    Text.fontColor(this.mood === index + 1 ? Color.White : COLOR_SECONDARY);
                }, Text);
                Text.pop();
                Column.pop();
            };
            this.forEachUpdateFunction(elmtId, ['index_mood_tired', 'index_mood_low_short', 'index_mood_calm', 'index_mood_good', 'index_mood_great_short'], forEachItemGenFunction, (label: string) => label, true, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        Column.pop();
        this.SectionTitle.bind(this)(this.t('index_quick_actions'), '');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 14 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(796:9)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 9 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(797:11)", "entry");
            Column.layoutWeight(1);
            Column.padding(17);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('💧');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(798:13)", "entry");
            Text.fontSize(29);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_drink_water'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(800:13)", "entry");
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_cups_format', this.waterCups));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(804:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t('index_add_cup'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(807:13)", "entry");
            Button.fontSize(13);
            Button.fontColor(COLOR_GREEN);
            Button.backgroundColor(COLOR_LIGHT_GREEN);
            Button.height(36);
            Button.borderRadius(18);
            Button.onClick(() => this.addWater());
        }, Button);
        Button.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 9 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(820:11)", "entry");
            Column.layoutWeight(1);
            Column.padding(17);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.breathingActive ? '◌' : '🌿');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(821:13)", "entry");
            Text.fontSize(29);
            Text.rotate({ angle: this.breathingActive ? 180 : 0 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_breathe'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(824:13)", "entry");
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.breathingActive ? this.t('index_seconds_format', this.breathingSeconds) : this.t('index_one_minute'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(828:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t(this.breathingActive ? 'index_in_progress' : 'index_start'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(831:13)", "entry");
            Button.fontSize(13);
            Button.fontColor(COLOR_PURPLE);
            Button.backgroundColor('#EEE9FA');
            Button.height(36);
            Button.borderRadius(18);
            Button.enabled(!this.breathingActive);
            Button.onClick(() => this.startBreathing());
        }, Button);
        Button.pop();
        Column.pop();
        Row.pop();
        this.SectionTitle.bind(this)(this.t('index_more_logs'), '');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(849:9)", "entry");
        }, Column);
        this.CheckInCard.bind(this)('☀', this.t('index_sunlight'), this.t('index_sunlight_help'), COLOR_ORANGE, '#FFF1E3', 'sunlight');
        this.CheckInCard.bind(this)('☕', this.t('index_caffeine'), this.t('index_caffeine_help'), '#9B6B48', '#F5E9E0', 'caffeine');
        this.CheckInCard.bind(this)('💊', this.t('index_medication'), this.t('index_medication_help'), COLOR_BLUE, '#E8EEFD', 'medication');
        this.CheckInCard.bind(this)('＋', this.t('index_symptoms'), this.t('index_symptoms_help'), '#D85C67', '#FCE8EA', 'symptom');
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_emergency'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(856:9)", "entry");
            Text.fontSize(12);
            Text.fontColor('#8D5B45');
            Text.lineHeight(18);
            Text.padding(14);
            Text.width('100%');
            Text.backgroundColor('#FFF4EB');
            Text.borderRadius(16);
        }, Text);
        Text.pop();
        Column.pop();
        Scroll.pop();
    }
    TrendPage(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/Index.ets(875:5)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
            Scroll.height('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 22 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(876:7)", "entry");
            Column.padding({ left: 18, right: 18, top: 18, bottom: 110 });
            Column.width('100%');
        }, Column);
        this.PageHeader.bind(this)(this.t('index_trends'), this.trendSubtitle());
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 18 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(879:9)", "entry");
            Column.padding(18);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(24);
            Column.shadow({ radius: 14, color: '#0B0C2017', offsetY: 4 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(880:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(881:13)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_week_steps'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(882:15)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.hasTrendData ? this.t('steps_format', this.weeklyStepTotal) : this.t('index_no_activity'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(886:15)", "entry");
            Text.fontSize(22);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.hasTrendData ? this.t('index_goal_days_format', this.weeklyGoalDays) : '--');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(894:13)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_GREEN);
            Text.padding({ left: 12, right: 12, top: 7, bottom: 7 });
            Text.backgroundColor(COLOR_LIGHT_GREEN);
            Text.borderRadius(15);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(904:11)", "entry");
            Row.width('100%');
            Row.alignItems(VerticalAlign.Bottom);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const point = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 7 });
                    Column.debugLine("entry/src/main/ets/pages/Index.ets(906:15)", "entry");
                    Column.layoutWeight(1);
                    Column.height(130);
                    Column.justifyContent(FlexAlign.End);
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.shortSteps(point.steps));
                    Text.debugLine("entry/src/main/ets/pages/Index.ets(907:17)", "entry");
                    Text.fontSize(9);
                    Text.fontColor(COLOR_SECONDARY);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create();
                    Column.debugLine("entry/src/main/ets/pages/Index.ets(910:17)", "entry");
                    Column.width(18);
                    Column.height(Math.max(point.value, 6));
                    Column.linearGradient({
                        angle: 0,
                        colors: point.day === this.t('today_short') ? [[COLOR_GREEN, 0.0], ['#6BC49E', 1.0]] : [['#C9DAD1', 0.0], ['#E2EBE6', 1.0]]
                    });
                    Column.borderRadius(9);
                }, Column);
                Column.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(point.day);
                    Text.debugLine("entry/src/main/ets/pages/Index.ets(918:17)", "entry");
                    Text.fontSize(12);
                    Text.fontColor(point.day === this.t('today_short') ? COLOR_GREEN : COLOR_SECONDARY);
                    Text.fontWeight(point.day === this.t('today_short') ? FontWeight.Bold : FontWeight.Regular);
                }, Text);
                Text.pop();
                Column.pop();
            };
            this.forEachUpdateFunction(elmtId, this.trendData, forEachItemGenFunction, (point: TrendPoint) => point.day, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        Column.pop();
        this.SectionTitle.bind(this)(this.t('index_health_summary'), this.healthUpdatedAt);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(939:9)", "entry");
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(940:11)", "entry");
            Column.padding(17);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(20);
            Column.onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/SleepDetailPage' });
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(941:13)", "entry");
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_average_sleep'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(942:15)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(946:15)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.sleepRecordDays > 0 ? this.durationText(this.averageSleepMinutes) : '--');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(947:15)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_PURPLE);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('›');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(951:15)", "entry");
            Text.fontSize(22);
            Text.fontColor('#A8B1AC');
        }, Text);
        Text.pop();
        Row.pop();
        this.ProgressBar.bind(this)(Math.min(this.averageSleepMinutes, 480), 480, COLOR_PURPLE);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.sleepRecordDays > 0 ? this.t('index_sleep_coverage_format', this.sleepRecordDays, this.sleepValue()) :
                this.t('index_sleep_no_records'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(956:13)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(969:11)", "entry");
            Column.padding(17);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(20);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(970:13)", "entry");
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_week_heart_rate'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(971:15)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(975:15)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.restingHeartRateDays > 0 ? this.t('heart_rate_format', this.averageRestingHeartRate) : '--');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(976:15)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#D85C67');
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.restingHeartRateDays > 0 ? this.t('index_heart_coverage_format', this.restingHeartRateDays) :
                this.t('index_heart_no_records'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(981:13)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(991:11)", "entry");
            Column.padding(17);
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(20);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(992:13)", "entry");
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_activity_goal'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(993:15)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(997:15)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.hasTrendData ? this.t('index_days_of_seven_format', this.weeklyGoalDays) : '--');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(998:15)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_BLUE);
        }, Text);
        Text.pop();
        Row.pop();
        this.ProgressBar.bind(this)(this.weeklyGoalDays, 7, COLOR_BLUE);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.hasTrendData ? this.t('index_activity_summary_format', this.weeklyStepTotal, this.dailyStepGoal) :
                this.t('index_activity_empty'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1004:13)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 14 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1015:9)", "entry");
            Row.padding(17);
            Row.backgroundColor('#F0F8F4');
            Row.borderRadius(20);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('✦');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1016:11)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_GREEN);
            Text.width(42);
            Text.height(42);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(COLOR_LIGHT_GREEN);
            Text.borderRadius(14);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 5 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1025:11)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_week_insight'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1026:13)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.hasTrendData ?
                (this.weeklyGoalDays >= 4 ? this.t('index_insight_good') : this.t('index_insight_low')) :
                this.t('index_insight_empty'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1031:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(19);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        Column.pop();
        Scroll.pop();
    }
    SettingRow(icon: string, title: string, subtitle: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 13 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1056:5)", "entry");
            Row.padding({ left: 15, right: 15, top: 13, bottom: 13 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(icon);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1057:7)", "entry");
            Text.fontSize(18);
            Text.fontColor(COLOR_GREEN);
            Text.width(40);
            Text.height(40);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(COLOR_LIGHT_GREEN);
            Text.borderRadius(13);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1065:7)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1066:9)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(subtitle);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1071:9)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('›');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1078:7)", "entry");
            Text.fontSize(25);
            Text.fontColor('#A8B1AC');
        }, Text);
        Text.pop();
        Row.pop();
    }
    ProfilePage(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/Index.ets(1088:5)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
            Scroll.height('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 20 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1089:7)", "entry");
            Column.padding({ left: 18, right: 18, top: 18, bottom: 110 });
            Column.width('100%');
        }, Column);
        this.PageHeader.bind(this)(this.t('index_profile'), this.t('index_profile_subtitle'));
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 15 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1092:9)", "entry");
            Row.padding(18);
            Row.width('100%');
            Row.backgroundColor(COLOR_CARD);
            Row.borderRadius(24);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_avatar'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1093:11)", "entry");
            Text.fontSize(29);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(Color.White);
            Text.width(66);
            Text.height(66);
            Text.textAlign(TextAlign.Center);
            Text.linearGradient({ angle: 135, colors: [[COLOR_GREEN, 0.0], ['#6BC49E', 1.0]] });
            Text.borderRadius(22);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 5 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1102:11)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_user_name'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1103:13)", "entry");
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_local_streak'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1108:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('81');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1115:11)", "entry");
            Text.fontSize(22);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_GREEN);
        }, Text);
        Text.pop();
        Row.pop();
        this.SectionTitle.bind(this)(this.t('index_huawei_health'), this.t(this.healthAuthorized ? 'index_connected' : 'index_disconnected'));
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 13 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1127:9)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 13 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1128:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('♥');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1129:13)", "entry");
            Text.fontSize(19);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(Color.White);
            Text.width(46);
            Text.height(46);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor('#D9323B');
            Text.borderRadius(15);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1138:13)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.healthStatus);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1139:15)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_last_sync_format', this.healthUpdatedAt));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1144:15)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 9 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1154:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t(this.healthLoading ? 'index_processing' :
                (this.healthAuthorized ? 'index_refresh' : 'index_connect_authorize')));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(1155:13)", "entry");
            Button.layoutWeight(1);
            Button.height(42);
            Button.fontSize(14);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_GREEN);
            Button.borderRadius(18);
            Button.enabled(!this.healthLoading);
            Button.onClick(() => {
                if (this.healthAuthorized) {
                    this.refreshHuaweiHealth();
                }
                else {
                    this.connectHuaweiHealth();
                }
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t('index_open_health'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(1171:13)", "entry");
            Button.layoutWeight(1);
            Button.height(42);
            Button.fontSize(14);
            Button.fontColor('#D9323B');
            Button.backgroundColor('#FCEBEC');
            Button.borderRadius(18);
            Button.onClick(() => this.openHuaweiHealthPrivacy());
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_health_privacy'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1182:11)", "entry");
            Text.fontSize(11);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(17);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.healthAuthorized) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel(this.t('index_revoke_health'));
                        Button.debugLine("entry/src/main/ets/pages/Index.ets(1189:13)", "entry");
                        Button.fontSize(13);
                        Button.fontColor('#B85A50');
                        Button.backgroundColor(Color.Transparent);
                        Button.height(34);
                        Button.onClick(() => this.disconnectHuaweiHealth());
                    }, Button);
                    Button.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
        this.SectionTitle.bind(this)(this.t('index_daily_goal'), '');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 15 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1204:9)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1205:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_step_goal'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1206:13)", "entry");
            Text.fontSize(16);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(1209:13)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('steps_format', this.dailyStepGoal));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1210:13)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_GREEN);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 9 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1217:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const goal = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel(`${goal}`);
                    Button.debugLine("entry/src/main/ets/pages/Index.ets(1219:15)", "entry");
                    Button.layoutWeight(1);
                    Button.height(38);
                    Button.fontSize(13);
                    Button.fontColor(this.dailyStepGoal === goal ? Color.White : COLOR_SECONDARY);
                    Button.backgroundColor(this.dailyStepGoal === goal ? COLOR_GREEN : '#EEF2EF');
                    Button.borderRadius(19);
                    Button.onClick(() => {
                        this.dailyStepGoal = goal;
                        this.persistState();
                    });
                }, Button);
                Button.pop();
            };
            this.forEachUpdateFunction(elmtId, [6000, 8000, 10000], forEachItemGenFunction, (goal: number) => `${goal}`, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1234:11)", "entry");
            Row.width('100%');
            Row.onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/ReminderSettingsPage' });
            });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('reminder_title'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1235:13)", "entry");
            Text.fontSize(16);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(1238:13)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_reminder_types'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1239:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('›');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1242:13)", "entry");
            Text.fontSize(22);
            Text.fontColor('#A8B1AC');
        }, Text);
        Text.pop();
        Row.pop();
        Column.pop();
        this.SectionTitle.bind(this)(this.t('index_settings'), '');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1258:9)", "entry");
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1259:11)", "entry");
            Column.width('100%');
            Column.onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPage' });
            });
        }, Column);
        this.SettingRow.bind(this)('◉', this.t('privacy_page_title'), this.t('index_privacy_setting'));
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
            Divider.debugLine("entry/src/main/ets/pages/Index.ets(1266:11)", "entry");
            Divider.color('#EDF0EE');
            Divider.margin({ left: 68 });
        }, Divider);
        this.SettingRow.bind(this)('⚙', this.t('index_device_connection'), this.t(this.healthAuthorized ?
            'index_health_connected' : 'index_device_disconnected'));
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
            Divider.debugLine("entry/src/main/ets/pages/Index.ets(1271:11)", "entry");
            Divider.color('#EDF0EE');
            Divider.margin({ left: 68 });
        }, Divider);
        this.SettingRow.bind(this)('?', this.t('index_help_feedback'), this.t('index_help_subtitle'));
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t('index_reset_today'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(1280:9)", "entry");
            Button.fontSize(15);
            Button.fontColor('#B85A50');
            Button.backgroundColor('#FBEDEB');
            Button.width('100%');
            Button.height(48);
            Button.borderRadius(18);
            Button.onClick(() => {
                this.resetConfirmationVisible = true;
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 7 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1291:9)", "entry");
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_brand_footer'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1292:11)", "entry");
            Text.fontSize(13);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_footer_disclaimer_format', this.lastSavedText));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1296:11)", "entry");
            Text.fontSize(11);
            Text.fontColor('#909A95');
        }, Text);
        Text.pop();
        Column.pop();
        Column.pop();
        Scroll.pop();
    }
    BottomNavigation(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1312:5)", "entry");
            Row.padding({ left: 12, right: 12, top: 5, bottom: 5 });
            Row.width('94%');
            Row.height(70);
            Row.backgroundColor('#FAFFFFFF');
            Row.borderRadius(24);
            Row.shadow({ radius: 26, color: '#29091610', offsetY: 2 });
            Row.margin({ bottom: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = (_item, index: number) => {
                const item = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 4 });
                    Column.debugLine("entry/src/main/ets/pages/Index.ets(1317:9)", "entry");
                    Column.layoutWeight(1);
                    Column.height(58);
                    Column.justifyContent(FlexAlign.Center);
                    Column.onClick(() => {
                        this.selectedTab = index;
                    });
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(item[0]);
                    Text.debugLine("entry/src/main/ets/pages/Index.ets(1318:11)", "entry");
                    Text.fontSize(index === 1 ? 24 : 19);
                    Text.fontWeight(FontWeight.Bold);
                    Text.fontColor(this.selectedTab === index ? COLOR_GREEN : '#8A9690');
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(item[1]);
                    Text.debugLine("entry/src/main/ets/pages/Index.ets(1322:11)", "entry");
                    Text.fontSize(11);
                    Text.fontWeight(this.selectedTab === index ? FontWeight.Bold : FontWeight.Regular);
                    Text.fontColor(this.selectedTab === index ? COLOR_GREEN : '#8A9690');
                }, Text);
                Text.pop();
                Column.pop();
            };
            this.forEachUpdateFunction(elmtId, [
                ['⌂', this.t('index_tab_home')], ['＋', this.t('index_tab_record')],
                ['↗', this.t('index_tab_trends')], ['●', this.t('index_tab_profile')]
            ], forEachItemGenFunction, (item: string[]) => item[1], true, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
    }
    ResetConfirmation(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1346:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.justifyContent(FlexAlign.Center);
            Column.backgroundColor('#52000000');
            Column.onClick(() => {
                this.resetConfirmationVisible = false;
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 14 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1347:7)", "entry");
            Column.padding(20);
            Column.width('84%');
            Column.backgroundColor(Color.White);
            Column.borderRadius(24);
            Column.shadow({ radius: 30, color: '#44000000', offsetY: 8 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_reset_title'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1348:9)", "entry");
            Text.fontSize(21);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t('index_reset_body'));
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1353:9)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(21);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1358:9)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t('cancel'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(1359:11)", "entry");
            Button.layoutWeight(1);
            Button.height(44);
            Button.fontColor(COLOR_SECONDARY);
            Button.backgroundColor('#EEF2EF');
            Button.borderRadius(18);
            Button.onClick(() => {
                this.resetConfirmationVisible = false;
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.t('index_confirm_reset'));
            Button.debugLine("entry/src/main/ets/pages/Index.ets(1368:11)", "entry");
            Button.layoutWeight(1);
            Button.height(44);
            Button.fontColor(Color.White);
            Button.backgroundColor('#B85A50');
            Button.borderRadius(18);
            Button.onClick(() => {
                this.resetToday();
                this.resetConfirmationVisible = false;
            });
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Bottom });
            Stack.debugLine("entry/src/main/ets/pages/Index.ets(1397:5)", "entry");
            Stack.width('100%');
            Stack.height('100%');
            Stack.backgroundColor(COLOR_BACKGROUND);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1398:7)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.linearGradient({ angle: 180, colors: [['#F6FAF7', 0.0], [COLOR_BACKGROUND, 1.0]] });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.selectedTab === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.HomePage.bind(this)();
                });
            }
            else if (this.selectedTab === 1) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.RecordPage.bind(this)();
                });
            }
            else if (this.selectedTab === 2) {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.TrendPage.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(3, () => {
                    this.ProfilePage.bind(this)();
                });
            }
        }, If);
        If.pop();
        Column.pop();
        this.BottomNavigation.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.resetConfirmationVisible) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.ResetConfirmation.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "com.boundesu.BioBalance", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
