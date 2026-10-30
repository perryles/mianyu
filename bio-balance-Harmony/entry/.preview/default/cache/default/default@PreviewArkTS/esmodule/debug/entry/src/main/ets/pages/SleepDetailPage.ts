if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SleepDetailPage_Params {
    loading?: boolean;
    statusText?: string;
    hasSleep?: boolean;
    sleepMinutes?: number;
    sleepScore?: number;
    days?: SleepDayPoint[];
    stages?: SleepStages;
    healthService?: HuaweiHealthService;
}
import type common from "@ohos:app.ability.common";
import { HuaweiHealthService } from "@normalized:N&&&entry/src/main/ets/service/HuaweiHealthService&";
import type { HuaweiHealthSnapshot, SleepStages } from "@normalized:N&&&entry/src/main/ets/service/HuaweiHealthService&";
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
class SleepDetailPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__loading = new ObservedPropertySimplePU(true, this, "loading");
        this.__statusText = new ObservedPropertySimplePU('', this, "statusText");
        this.__hasSleep = new ObservedPropertySimplePU(false, this, "hasSleep");
        this.__sleepMinutes = new ObservedPropertySimplePU(0, this, "sleepMinutes");
        this.__sleepScore = new ObservedPropertySimplePU(0, this, "sleepScore");
        this.__days = new ObservedPropertyObjectPU([], this, "days");
        this.__stages = new ObservedPropertyObjectPU({
            deepMinutes: 0,
            shallowMinutes: 0,
            dreamMinutes: 0,
            awakeMinutes: 0,
            totalMinutes: 0,
            hasDetails: false
        }, this, "stages");
        this.healthService = new HuaweiHealthService();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SleepDetailPage_Params) {
        if (params.loading !== undefined) {
            this.loading = params.loading;
        }
        if (params.statusText !== undefined) {
            this.statusText = params.statusText;
        }
        if (params.hasSleep !== undefined) {
            this.hasSleep = params.hasSleep;
        }
        if (params.sleepMinutes !== undefined) {
            this.sleepMinutes = params.sleepMinutes;
        }
        if (params.sleepScore !== undefined) {
            this.sleepScore = params.sleepScore;
        }
        if (params.days !== undefined) {
            this.days = params.days;
        }
        if (params.stages !== undefined) {
            this.stages = params.stages;
        }
        if (params.healthService !== undefined) {
            this.healthService = params.healthService;
        }
    }
    updateStateVars(params: SleepDetailPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__loading.purgeDependencyOnElmtId(rmElmtId);
        this.__statusText.purgeDependencyOnElmtId(rmElmtId);
        this.__hasSleep.purgeDependencyOnElmtId(rmElmtId);
        this.__sleepMinutes.purgeDependencyOnElmtId(rmElmtId);
        this.__sleepScore.purgeDependencyOnElmtId(rmElmtId);
        this.__days.purgeDependencyOnElmtId(rmElmtId);
        this.__stages.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__loading.aboutToBeDeleted();
        this.__statusText.aboutToBeDeleted();
        this.__hasSleep.aboutToBeDeleted();
        this.__sleepMinutes.aboutToBeDeleted();
        this.__sleepScore.aboutToBeDeleted();
        this.__days.aboutToBeDeleted();
        this.__stages.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __loading: ObservedPropertySimplePU<boolean>;
    get loading() {
        return this.__loading.get();
    }
    set loading(newValue: boolean) {
        this.__loading.set(newValue);
    }
    private __statusText: ObservedPropertySimplePU<string>;
    get statusText() {
        return this.__statusText.get();
    }
    set statusText(newValue: string) {
        this.__statusText.set(newValue);
    }
    private __hasSleep: ObservedPropertySimplePU<boolean>;
    get hasSleep() {
        return this.__hasSleep.get();
    }
    set hasSleep(newValue: boolean) {
        this.__hasSleep.set(newValue);
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
    private __days: ObservedPropertyObjectPU<SleepDayPoint[]>;
    get days() {
        return this.__days.get();
    }
    set days(newValue: SleepDayPoint[]) {
        this.__days.set(newValue);
    }
    private __stages: ObservedPropertyObjectPU<SleepStages>;
    get stages() {
        return this.__stages.get();
    }
    set stages(newValue: SleepStages) {
        this.__stages.set(newValue);
    }
    private healthService: HuaweiHealthService;
    private t(name: string, first?: string | number, second?: string | number): string {
        const context = this.getUIContext().getHostContext();
        if (context === undefined)
            return '';
        if (first === undefined)
            return context.resourceManager.getStringByNameSync(name);
        if (second === undefined)
            return context.resourceManager.getStringByNameSync(name, first);
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
    StageBar(label: string, minutes: number, percent: number, color: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(195:5)", "entry");
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.durationText(minutes));
            Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(196:7)", "entry");
            Text.fontSize(14);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(201:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(202:9)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(205:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${percent}%`);
            Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(206:9)", "entry");
            Text.fontSize(13);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(color);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Start });
            Stack.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(212:7)", "entry");
            Stack.width('100%');
            Stack.height(8);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(213:9)", "entry");
            Row.height(8);
            Row.width('100%');
            Row.backgroundColor('#EAEFEB');
            Row.borderRadius(4);
        }, Row);
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(218:9)", "entry");
            Row.height(8);
            Row.width(`${percent}%`);
            Row.backgroundColor(color);
            Row.borderRadius(4);
        }, Row);
        Row.pop();
        Stack.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(231:5)", "entry");
            Column.padding({ left: 18, right: 18, top: 14, bottom: 18 });
            Column.width('100%');
            Column.height('100%');
            Column.linearGradient({ angle: 180, colors: [['#F6FAF7', 0.0], [COLOR_BACKGROUND, 1.0]] });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(232:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(233:9)", "entry");
            Text.fontSize(28);
            Text.fontColor(COLOR_TEXT);
            Text.width(38);
            Text.height(38);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => this.getUIContext().getRouter().back());
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(240:9)", "entry");
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777449, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(241:11)", "entry");
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.statusText);
            Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(246:11)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(255:7)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.layoutWeight(1);
            Scroll.width('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(256:9)", "entry");
            Column.padding({ left: 18, right: 18, top: 10, bottom: 30 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.loading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(258:13)", "entry");
                        Column.padding(30);
                        Column.width('100%');
                        Column.justifyContent(FlexAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777402, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(259:15)", "entry");
                        Text.fontSize(14);
                        Text.fontColor(COLOR_SECONDARY);
                    }, Text);
                    Text.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 14 });
                        Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(267:13)", "entry");
                        Column.padding(18);
                        Column.width('100%');
                        Column.backgroundColor(COLOR_CARD);
                        Column.borderRadius(24);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(268:15)", "entry");
                        Row.width('100%');
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 4 });
                        Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(269:17)", "entry");
                        Column.layoutWeight(1);
                        Column.alignItems(HorizontalAlign.Start);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777454, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(270:19)", "entry");
                        Text.fontSize(14);
                        Text.fontColor(COLOR_SECONDARY);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.hasSleep ? this.durationText(this.sleepMinutes) : '--');
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(274:19)", "entry");
                        Text.fontSize(26);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(COLOR_TEXT);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    Column.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 4 });
                        Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(282:17)", "entry");
                        Column.alignItems(HorizontalAlign.End);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777459, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(283:19)", "entry");
                        Text.fontSize(14);
                        Text.fontColor(COLOR_SECONDARY);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.hasSleep && this.sleepScore > 0 ? this.t('score_format', this.sleepScore) : '--');
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(287:19)", "entry");
                        Text.fontSize(26);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(COLOR_PURPLE);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    Column.pop();
                    Row.pop();
                    Column.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 14 });
                        Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(302:13)", "entry");
                        Column.padding(18);
                        Column.width('100%');
                        Column.backgroundColor(COLOR_CARD);
                        Column.borderRadius(24);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777468, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(303:15)", "entry");
                        Text.fontSize(16);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(COLOR_TEXT);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create({ space: 10 });
                        Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(308:15)", "entry");
                        Row.width('100%');
                        Row.height(150);
                        Row.alignItems(VerticalAlign.Bottom);
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const point = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 6 });
                                Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(310:19)", "entry");
                                Column.layoutWeight(1);
                                Column.height(150);
                                Column.justifyContent(FlexAlign.End);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.durationText(point.minutes));
                                Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(311:21)", "entry");
                                Text.fontSize(9);
                                Text.fontColor(COLOR_SECONDARY);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create();
                                Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(314:21)", "entry");
                                Column.width(20);
                                Column.height(`${point.heightPercent}%`);
                                Column.linearGradient({
                                    angle: 0,
                                    colors: point.label === this.t('today_short') ? [[COLOR_GREEN, 0.0], ['#6BC49E', 1.0]] : [['#C9DAD1', 0.0], ['#E2EBE6', 1.0]]
                                });
                                Column.borderRadius(10);
                            }, Column);
                            Column.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(point.label);
                                Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(322:21)", "entry");
                                Text.fontSize(12);
                                Text.fontColor(point.label === this.t('today_short') ? COLOR_GREEN : COLOR_SECONDARY);
                                Text.fontWeight(point.label === this.t('today_short') ? FontWeight.Bold : FontWeight.Regular);
                            }, Text);
                            Text.pop();
                            Column.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.days, forEachItemGenFunction, (point: SleepDayPoint) => point.label, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Row.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777469, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(335:15)", "entry");
                        Text.fontSize(14);
                        Text.fontWeight(FontWeight.Medium);
                        Text.fontColor(COLOR_TEXT);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create({ space: 10 });
                        Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(340:15)", "entry");
                        Row.width('100%');
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const point = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 5 });
                                Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(342:19)", "entry");
                                Column.layoutWeight(1);
                                Column.justifyContent(FlexAlign.Center);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(point.score > 0 ? `${point.score}` : '--');
                                Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(343:21)", "entry");
                                Text.fontSize(13);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(point.score > 0 ? COLOR_GREEN : '#A8B1AC');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(point.label);
                                Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(347:21)", "entry");
                                Text.fontSize(11);
                                Text.fontColor(COLOR_SECONDARY);
                            }, Text);
                            Text.pop();
                            Column.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.days, forEachItemGenFunction, (point: SleepDayPoint) => `score_${point.label}`, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Row.pop();
                    Column.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 12 });
                        Column.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(362:13)", "entry");
                        Column.padding(18);
                        Column.width('100%');
                        Column.backgroundColor(COLOR_CARD);
                        Column.borderRadius(24);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(363:15)", "entry");
                        Row.width('100%');
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777467, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(364:17)", "entry");
                        Text.fontSize(16);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(COLOR_TEXT);
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                        Blank.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(368:17)", "entry");
                    }, Blank);
                    Blank.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.stages.hasDetails ? this.t('sleep_stage_total_format', this.durationText(this.stages.totalMinutes)) :
                            this.t('sleep_no_details'));
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(369:17)", "entry");
                        Text.fontSize(12);
                        Text.fontColor(COLOR_SECONDARY);
                    }, Text);
                    Text.pop();
                    Row.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const row = _item;
                            this.StageBar.bind(this)(row.name, row.minutes, row.percent, row.color);
                        };
                        this.forEachUpdateFunction(elmtId, this.stageRows(), forEachItemGenFunction, (row: StageRow) => row.key, false, false);
                    }, ForEach);
                    ForEach.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.stageHint());
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(378:15)", "entry");
                        Text.fontSize(12);
                        Text.fontColor(COLOR_SECONDARY);
                        Text.lineHeight(18);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                    Column.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777456, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/SleepDetailPage.ets(389:13)", "entry");
                        Text.fontSize(12);
                        Text.fontColor(COLOR_SECONDARY);
                        Text.lineHeight(18);
                        Text.width('100%');
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "SleepDetailPage";
    }
}
registerNamedRoute(() => new SleepDetailPage(undefined, {}), "", { bundleName: "com.boundesu.BioBalance", moduleName: "entry", pagePath: "pages/SleepDetailPage", pageFullPath: "entry/src/main/ets/pages/SleepDetailPage", integratedHsp: "false", moduleType: "followWithHap" });
