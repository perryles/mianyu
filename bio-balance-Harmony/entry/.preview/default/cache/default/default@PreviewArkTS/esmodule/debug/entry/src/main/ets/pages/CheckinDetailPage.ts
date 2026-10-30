if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface CheckinDetailPage_Params {
    pageType?: string;
    loaded?: boolean;
    statusText?: string;
    sunlightInput?: string;
    sunlightMinutes?: number;
    sunlightSaved?: boolean;
    caffeineList?: CaffeineItem[];
    caffeineOptions?: number[];
    selectedCaffeineIndex?: number;
    medicationList?: MedicationItem[];
    nameInput?: string;
    doseInput?: string;
    symptomList?: SymptomItem[];
    symptomTypes?: string[];
    selectedSymptomIndex?: number;
    selectedIntensity?: number;
}
import type common from "@ohos:app.ability.common";
import { CheckinRecordStore } from "@normalized:N&&&entry/src/main/ets/model/CheckinRecordStore&";
const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
const COLOR_LIGHT_GREEN: string = '#E2F4EA';
const COLOR_ORANGE: string = '#F09A50';
const COLOR_BLUE: string = '#4F7FEA';
const COLOR_RED: string = '#D85C67';
interface CaffeineItem {
    id: string;
    time: string;
    amount: number;
}
interface MedicationItem {
    id: string;
    time: string;
    name: string;
    dose: string;
}
interface SymptomItem {
    id: string;
    time: string;
    type: string;
    intensity: number;
}
interface CheckinPageParams {
    type: string;
}
class CheckinDetailPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__pageType = new ObservedPropertySimplePU('', this, "pageType");
        this.__loaded = new ObservedPropertySimplePU(false, this, "loaded");
        this.__statusText = new ObservedPropertySimplePU('', this, "statusText");
        this.__sunlightInput = new ObservedPropertySimplePU('', this, "sunlightInput");
        this.__sunlightMinutes = new ObservedPropertySimplePU(0, this, "sunlightMinutes");
        this.__sunlightSaved = new ObservedPropertySimplePU(false, this, "sunlightSaved");
        this.__caffeineList = new ObservedPropertyObjectPU([], this, "caffeineList");
        this.__caffeineOptions = new ObservedPropertyObjectPU([50, 100, 150], this, "caffeineOptions");
        this.__selectedCaffeineIndex = new ObservedPropertySimplePU(1, this, "selectedCaffeineIndex");
        this.__medicationList = new ObservedPropertyObjectPU([], this, "medicationList");
        this.__nameInput = new ObservedPropertySimplePU('', this, "nameInput");
        this.__doseInput = new ObservedPropertySimplePU('', this, "doseInput");
        this.__symptomList = new ObservedPropertyObjectPU([], this, "symptomList");
        this.__symptomTypes = new ObservedPropertyObjectPU(['symptom_headache', 'symptom_fatigue', 'symptom_anxiety', 'symptom_insomnia',
            'symptom_neck_pain', 'symptom_other'], this, "symptomTypes");
        this.__selectedSymptomIndex = new ObservedPropertySimplePU(0, this, "selectedSymptomIndex");
        this.__selectedIntensity = new ObservedPropertySimplePU(3, this, "selectedIntensity");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: CheckinDetailPage_Params) {
        if (params.pageType !== undefined) {
            this.pageType = params.pageType;
        }
        if (params.loaded !== undefined) {
            this.loaded = params.loaded;
        }
        if (params.statusText !== undefined) {
            this.statusText = params.statusText;
        }
        if (params.sunlightInput !== undefined) {
            this.sunlightInput = params.sunlightInput;
        }
        if (params.sunlightMinutes !== undefined) {
            this.sunlightMinutes = params.sunlightMinutes;
        }
        if (params.sunlightSaved !== undefined) {
            this.sunlightSaved = params.sunlightSaved;
        }
        if (params.caffeineList !== undefined) {
            this.caffeineList = params.caffeineList;
        }
        if (params.caffeineOptions !== undefined) {
            this.caffeineOptions = params.caffeineOptions;
        }
        if (params.selectedCaffeineIndex !== undefined) {
            this.selectedCaffeineIndex = params.selectedCaffeineIndex;
        }
        if (params.medicationList !== undefined) {
            this.medicationList = params.medicationList;
        }
        if (params.nameInput !== undefined) {
            this.nameInput = params.nameInput;
        }
        if (params.doseInput !== undefined) {
            this.doseInput = params.doseInput;
        }
        if (params.symptomList !== undefined) {
            this.symptomList = params.symptomList;
        }
        if (params.symptomTypes !== undefined) {
            this.symptomTypes = params.symptomTypes;
        }
        if (params.selectedSymptomIndex !== undefined) {
            this.selectedSymptomIndex = params.selectedSymptomIndex;
        }
        if (params.selectedIntensity !== undefined) {
            this.selectedIntensity = params.selectedIntensity;
        }
    }
    updateStateVars(params: CheckinDetailPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__pageType.purgeDependencyOnElmtId(rmElmtId);
        this.__loaded.purgeDependencyOnElmtId(rmElmtId);
        this.__statusText.purgeDependencyOnElmtId(rmElmtId);
        this.__sunlightInput.purgeDependencyOnElmtId(rmElmtId);
        this.__sunlightMinutes.purgeDependencyOnElmtId(rmElmtId);
        this.__sunlightSaved.purgeDependencyOnElmtId(rmElmtId);
        this.__caffeineList.purgeDependencyOnElmtId(rmElmtId);
        this.__caffeineOptions.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedCaffeineIndex.purgeDependencyOnElmtId(rmElmtId);
        this.__medicationList.purgeDependencyOnElmtId(rmElmtId);
        this.__nameInput.purgeDependencyOnElmtId(rmElmtId);
        this.__doseInput.purgeDependencyOnElmtId(rmElmtId);
        this.__symptomList.purgeDependencyOnElmtId(rmElmtId);
        this.__symptomTypes.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedSymptomIndex.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedIntensity.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__pageType.aboutToBeDeleted();
        this.__loaded.aboutToBeDeleted();
        this.__statusText.aboutToBeDeleted();
        this.__sunlightInput.aboutToBeDeleted();
        this.__sunlightMinutes.aboutToBeDeleted();
        this.__sunlightSaved.aboutToBeDeleted();
        this.__caffeineList.aboutToBeDeleted();
        this.__caffeineOptions.aboutToBeDeleted();
        this.__selectedCaffeineIndex.aboutToBeDeleted();
        this.__medicationList.aboutToBeDeleted();
        this.__nameInput.aboutToBeDeleted();
        this.__doseInput.aboutToBeDeleted();
        this.__symptomList.aboutToBeDeleted();
        this.__symptomTypes.aboutToBeDeleted();
        this.__selectedSymptomIndex.aboutToBeDeleted();
        this.__selectedIntensity.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __pageType: ObservedPropertySimplePU<string>;
    get pageType() {
        return this.__pageType.get();
    }
    set pageType(newValue: string) {
        this.__pageType.set(newValue);
    }
    private __loaded: ObservedPropertySimplePU<boolean>;
    get loaded() {
        return this.__loaded.get();
    }
    set loaded(newValue: boolean) {
        this.__loaded.set(newValue);
    }
    private __statusText: ObservedPropertySimplePU<string>;
    get statusText() {
        return this.__statusText.get();
    }
    set statusText(newValue: string) {
        this.__statusText.set(newValue);
    }
    private __sunlightInput: ObservedPropertySimplePU<string>;
    get sunlightInput() {
        return this.__sunlightInput.get();
    }
    set sunlightInput(newValue: string) {
        this.__sunlightInput.set(newValue);
    }
    private __sunlightMinutes: ObservedPropertySimplePU<number>;
    get sunlightMinutes() {
        return this.__sunlightMinutes.get();
    }
    set sunlightMinutes(newValue: number) {
        this.__sunlightMinutes.set(newValue);
    }
    private __sunlightSaved: ObservedPropertySimplePU<boolean>;
    get sunlightSaved() {
        return this.__sunlightSaved.get();
    }
    set sunlightSaved(newValue: boolean) {
        this.__sunlightSaved.set(newValue);
    }
    private __caffeineList: ObservedPropertyObjectPU<CaffeineItem[]>;
    get caffeineList() {
        return this.__caffeineList.get();
    }
    set caffeineList(newValue: CaffeineItem[]) {
        this.__caffeineList.set(newValue);
    }
    private __caffeineOptions: ObservedPropertyObjectPU<number[]>;
    get caffeineOptions() {
        return this.__caffeineOptions.get();
    }
    set caffeineOptions(newValue: number[]) {
        this.__caffeineOptions.set(newValue);
    }
    private __selectedCaffeineIndex: ObservedPropertySimplePU<number>;
    get selectedCaffeineIndex() {
        return this.__selectedCaffeineIndex.get();
    }
    set selectedCaffeineIndex(newValue: number) {
        this.__selectedCaffeineIndex.set(newValue);
    }
    private __medicationList: ObservedPropertyObjectPU<MedicationItem[]>;
    get medicationList() {
        return this.__medicationList.get();
    }
    set medicationList(newValue: MedicationItem[]) {
        this.__medicationList.set(newValue);
    }
    private __nameInput: ObservedPropertySimplePU<string>;
    get nameInput() {
        return this.__nameInput.get();
    }
    set nameInput(newValue: string) {
        this.__nameInput.set(newValue);
    }
    private __doseInput: ObservedPropertySimplePU<string>;
    get doseInput() {
        return this.__doseInput.get();
    }
    set doseInput(newValue: string) {
        this.__doseInput.set(newValue);
    }
    private __symptomList: ObservedPropertyObjectPU<SymptomItem[]>;
    get symptomList() {
        return this.__symptomList.get();
    }
    set symptomList(newValue: SymptomItem[]) {
        this.__symptomList.set(newValue);
    }
    private __symptomTypes: ObservedPropertyObjectPU<string[]>;
    get symptomTypes() {
        return this.__symptomTypes.get();
    }
    set symptomTypes(newValue: string[]) {
        this.__symptomTypes.set(newValue);
    }
    private __selectedSymptomIndex: ObservedPropertySimplePU<number>;
    get selectedSymptomIndex() {
        return this.__selectedSymptomIndex.get();
    }
    set selectedSymptomIndex(newValue: number) {
        this.__selectedSymptomIndex.set(newValue);
    }
    private __selectedIntensity: ObservedPropertySimplePU<number>;
    get selectedIntensity() {
        return this.__selectedIntensity.get();
    }
    set selectedIntensity(newValue: number) {
        this.__selectedIntensity.set(newValue);
    }
    private title(): string {
        if (this.pageType === 'sunlight') {
            return this.t('checkin_sunlight_title');
        }
        if (this.pageType === 'caffeine') {
            return this.t('checkin_caffeine_title');
        }
        if (this.pageType === 'medication') {
            return this.t('checkin_medication_title');
        }
        return this.t('checkin_symptom_title');
    }
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
        this.pageType = this.readType();
        this.statusText = this.t('local_only');
        this.loadToday();
    }
    private readType(): string {
        const params = this.getUIContext().getRouter().getParams() as CheckinPageParams | undefined;
        const raw: string = params !== undefined && params !== null ? params.type : '';
        if (raw === 'sunlight' || raw === 'caffeine' || raw === 'medication' || raw === 'symptom') {
            return raw;
        }
        return 'sunlight';
    }
    private async loadToday(): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            this.statusText = this.t('local_storage_unavailable');
            this.loaded = true;
            return;
        }
        const today: string = CheckinRecordStore.dateKey();
        if (this.pageType === 'sunlight') {
            const record = await CheckinRecordStore.loadSunlight(context, today);
            this.sunlightMinutes = record.minutes;
            this.sunlightSaved = record.minutes > 0;
        }
        else if (this.pageType === 'caffeine') {
            this.caffeineList = await CheckinRecordStore.loadCaffeine(context, today);
        }
        else if (this.pageType === 'medication') {
            this.medicationList = await CheckinRecordStore.loadMedication(context, today);
        }
        else if (this.pageType === 'symptom') {
            this.symptomList = await CheckinRecordStore.loadSymptoms(context, today);
        }
        this.loaded = true;
    }
    private async saveSunlight(): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        const parsed: number = Number.parseInt(this.sunlightInput, 10);
        if (Number.isNaN(parsed) || parsed < 0 || parsed > 1440) {
            this.statusText = this.t('checkin_invalid_minutes');
            return;
        }
        await CheckinRecordStore.saveSunlight(context, CheckinRecordStore.dateKey(), parsed);
        this.sunlightMinutes = parsed;
        this.sunlightSaved = parsed > 0;
        this.sunlightInput = '';
        this.statusText = this.t('checkin_sunlight_saved');
    }
    private async addCaffeine(): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        const amount: number = this.caffeineOptions[this.selectedCaffeineIndex];
        this.caffeineList = await CheckinRecordStore.addCaffeine(context, CheckinRecordStore.dateKey(), amount);
        this.statusText = this.t('checkin_caffeine_saved');
    }
    private async removeCaffeine(id: string): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        this.caffeineList = await CheckinRecordStore.removeCaffeine(context, CheckinRecordStore.dateKey(), id);
    }
    private async addMedication(): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        const name: string = this.nameInput.trim();
        const dose: string = this.doseInput.trim();
        if (name.length === 0) {
            this.statusText = this.t('checkin_medication_name_required');
            return;
        }
        this.medicationList = await CheckinRecordStore.addMedication(context, CheckinRecordStore.dateKey(), name, dose);
        this.nameInput = '';
        this.doseInput = '';
        this.statusText = this.t('checkin_medication_saved');
    }
    private async removeMedication(id: string): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        this.medicationList = await CheckinRecordStore.removeMedication(context, CheckinRecordStore.dateKey(), id);
    }
    private async addSymptom(): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        const type: string = this.symptomTypes[this.selectedSymptomIndex];
        this.symptomList = await CheckinRecordStore.addSymptom(context, CheckinRecordStore.dateKey(), type, this.selectedIntensity);
        this.statusText = this.t('checkin_symptom_saved');
    }
    private async removeSymptom(id: string): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            return;
        }
        this.symptomList = await CheckinRecordStore.removeSymptom(context, CheckinRecordStore.dateKey(), id);
    }
    private intensityLabel(value: number): string {
        const keys: string[] = ['intensity_very_light', 'intensity_light', 'intensity_medium', 'intensity_heavy', 'intensity_severe'];
        return this.t(keys[value - 1]);
    }
    private symptomLabel(value: string): string {
        const resourceIndex: number = this.symptomTypes.indexOf(value);
        if (resourceIndex >= 0)
            return this.t(value);
        const legacyValues: string[] = [
            '\u5934\u75db', '\u4e4f\u529b', '\u7126\u8651', '\u5931\u7720', '\u80a9\u9888\u9178\u75db', '\u5176\u4ed6'
        ];
        const legacyIndex: number = legacyValues.indexOf(value);
        return legacyIndex >= 0 ? this.t(this.symptomTypes[legacyIndex]) : value;
    }
    private minutesText(minutes: number): string {
        if (minutes <= 0) {
            return this.t('checkin_not_recorded');
        }
        return this.t('minutes_format', minutes);
    }
    Header(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(219:5)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(220:7)", "entry");
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
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(227:7)", "entry");
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.title());
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(228:9)", "entry");
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777371, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(233:9)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
    }
    SunlightSection(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(245:5)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(246:7)", "entry");
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.sunlightSaved ? this.minutesText(this.sunlightMinutes) : this.t('checkin_not_recorded_today'));
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(247:9)", "entry");
            Text.fontSize(26);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_ORANGE);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777375, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(252:9)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(19);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(260:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ text: this.sunlightInput, placeholder: { "id": 16777376, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" } });
            TextInput.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(261:9)", "entry");
            TextInput.type(InputType.Number);
            TextInput.layoutWeight(1);
            TextInput.height(44);
            TextInput.fontSize(14);
            TextInput.backgroundColor('#F4F7F5');
            TextInput.borderRadius(14);
            TextInput.onChange((value: string) => {
                this.sunlightInput = value;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777443, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Button.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(271:9)", "entry");
            Button.height(44);
            Button.fontSize(14);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_ORANGE);
            Button.borderRadius(14);
            Button.onClick(() => this.saveSunlight());
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
    }
    CaffeineSection(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(289:5)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777372, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(290:7)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(295:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = (_item, index: number) => {
                const amount = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 4 });
                    Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(297:11)", "entry");
                    Column.layoutWeight(1);
                    Column.height(54);
                    Column.justifyContent(FlexAlign.Center);
                    Column.backgroundColor(this.selectedCaffeineIndex === index ? COLOR_GREEN : '#F1F5F2');
                    Column.borderRadius(14);
                    Column.onClick(() => {
                        this.selectedCaffeineIndex = index;
                    });
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`${amount}`);
                    Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(298:13)", "entry");
                    Text.fontSize(16);
                    Text.fontWeight(FontWeight.Bold);
                    Text.fontColor(this.selectedCaffeineIndex === index ? Color.White : COLOR_TEXT);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create('mg');
                    Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(302:13)", "entry");
                    Text.fontSize(10);
                    Text.fontColor(this.selectedCaffeineIndex === index ? '#E8FFF4' : COLOR_SECONDARY);
                }, Text);
                Text.pop();
                Column.pop();
            };
            this.forEachUpdateFunction(elmtId, this.caffeineOptions, forEachItemGenFunction, (amount: number) => `${amount}`, true, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777357, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Button.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(317:7)", "entry");
            Button.width('100%');
            Button.height(44);
            Button.fontSize(15);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_GREEN);
            Button.borderRadius(16);
            Button.onClick(() => this.addCaffeine());
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.caffeineList.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Divider.create();
                        Divider.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(327:9)", "entry");
                        Divider.color('#EDF0EE');
                    }, Divider);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const item = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 12 });
                                Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(330:11)", "entry");
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 3 });
                                Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(331:13)", "entry");
                                Column.layoutWeight(1);
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`${item.amount} mg`);
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(332:15)", "entry");
                                Text.fontSize(16);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(COLOR_TEXT);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(item.time);
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(337:15)", "entry");
                                Text.fontSize(12);
                                Text.fontColor(COLOR_SECONDARY);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            Column.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create({ "id": 16777383, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(344:13)", "entry");
                                Text.fontSize(13);
                                Text.fontColor(COLOR_RED);
                                Text.onClick(() => this.removeCaffeine(item.id));
                            }, Text);
                            Text.pop();
                            Row.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.caffeineList, forEachItemGenFunction, (item: CaffeineItem) => item.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    MedicationSection(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(361:5)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777373, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(362:7)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ text: this.nameInput, placeholder: { "id": 16777364, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" } });
            TextInput.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(367:7)", "entry");
            TextInput.height(44);
            TextInput.fontSize(14);
            TextInput.backgroundColor('#F4F7F5');
            TextInput.borderRadius(14);
            TextInput.width('100%');
            TextInput.onChange((value: string) => {
                this.nameInput = value;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ text: this.doseInput, placeholder: { "id": 16777363, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" } });
            TextInput.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(376:7)", "entry");
            TextInput.height(44);
            TextInput.fontSize(14);
            TextInput.backgroundColor('#F4F7F5');
            TextInput.borderRadius(14);
            TextInput.width('100%');
            TextInput.onChange((value: string) => {
                this.doseInput = value;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777356, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Button.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(385:7)", "entry");
            Button.width('100%');
            Button.height(44);
            Button.fontSize(15);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_BLUE);
            Button.borderRadius(16);
            Button.onClick(() => this.addMedication());
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.medicationList.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Divider.create();
                        Divider.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(395:9)", "entry");
                        Divider.color('#EDF0EE');
                    }, Divider);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const item = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 12 });
                                Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(398:11)", "entry");
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 3 });
                                Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(399:13)", "entry");
                                Column.layoutWeight(1);
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(item.name);
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(400:15)", "entry");
                                Text.fontSize(16);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(COLOR_TEXT);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(item.dose.length > 0 ? `${item.dose} · ${item.time}` : item.time);
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(405:15)", "entry");
                                Text.fontSize(12);
                                Text.fontColor(COLOR_SECONDARY);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            Column.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create({ "id": 16777383, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(412:13)", "entry");
                                Text.fontSize(13);
                                Text.fontColor(COLOR_RED);
                                Text.onClick(() => this.removeMedication(item.id));
                            }, Text);
                            Text.pop();
                            Row.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.medicationList, forEachItemGenFunction, (item: MedicationItem) => item.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    SymptomSection(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(429:5)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777374, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(430:7)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(435:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = (_item, index: number) => {
                const type = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.symptomLabel(type));
                    Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(437:13)", "entry");
                    Text.fontSize(13);
                    Text.fontColor(this.selectedSymptomIndex === index ? Color.White : COLOR_TEXT);
                    Text.padding({ left: 12, right: 12, top: 8, bottom: 8 });
                    Text.backgroundColor(this.selectedSymptomIndex === index ? COLOR_GREEN : '#F1F5F2');
                    Text.borderRadius(14);
                    Text.onClick(() => {
                        this.selectedSymptomIndex = index;
                    });
                }, Text);
                Text.pop();
            };
            this.forEachUpdateFunction(elmtId, this.symptomTypes, forEachItemGenFunction, (type: string) => type, true, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(450:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777361, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(451:9)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(454:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.intensityLabel(this.selectedIntensity));
            Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(455:9)", "entry");
            Text.fontSize(14);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_RED);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(462:7)", "entry");
            Row.width('100%');
            Row.justifyContent(FlexAlign.SpaceBetween);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const value = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`${value}`);
                    Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(464:11)", "entry");
                    Text.width(34);
                    Text.height(34);
                    Text.textAlign(TextAlign.Center);
                    Text.fontSize(14);
                    Text.fontColor(this.selectedIntensity === value ? Color.White : COLOR_SECONDARY);
                    Text.borderRadius(17);
                    Text.backgroundColor(this.selectedIntensity === value ? COLOR_RED : '#F1F5F2');
                    Text.onClick(() => {
                        this.selectedIntensity = value;
                    });
                }, Text);
                Text.pop();
            };
            this.forEachUpdateFunction(elmtId, [1, 2, 3, 4, 5], forEachItemGenFunction, (value: number) => `${value}`, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777358, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Button.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(480:7)", "entry");
            Button.width('100%');
            Button.height(44);
            Button.fontSize(15);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_RED);
            Button.borderRadius(16);
            Button.onClick(() => this.addSymptom());
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.symptomList.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Divider.create();
                        Divider.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(490:9)", "entry");
                        Divider.color('#EDF0EE');
                    }, Divider);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const item = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 12 });
                                Row.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(493:11)", "entry");
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 3 });
                                Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(494:13)", "entry");
                                Column.layoutWeight(1);
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.symptomLabel(item.type));
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(495:15)", "entry");
                                Text.fontSize(16);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(COLOR_TEXT);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`${this.intensityLabel(item.intensity)} · ${item.time}`);
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(500:15)", "entry");
                                Text.fontSize(12);
                                Text.fontColor(COLOR_SECONDARY);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            Column.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create({ "id": 16777383, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                                Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(507:13)", "entry");
                                Text.fontSize(13);
                                Text.fontColor(COLOR_RED);
                                Text.onClick(() => this.removeSymptom(item.id));
                            }, Text);
                            Text.pop();
                            Row.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.symptomList, forEachItemGenFunction, (item: SymptomItem) => item.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(523:5)", "entry");
            Column.padding({ left: 18, right: 18, top: 14, bottom: 18 });
            Column.width('100%');
            Column.height('100%');
            Column.linearGradient({ angle: 180, colors: [['#F6FAF7', 0.0], [COLOR_BACKGROUND, 1.0]] });
        }, Column);
        this.Header.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(526:7)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.layoutWeight(1);
            Scroll.width('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 14 });
            Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(527:9)", "entry");
            Column.padding({ left: 18, right: 18, top: 10, bottom: 30 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!this.loaded) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(529:13)", "entry");
                        Column.padding(30);
                        Column.width('100%');
                        Column.justifyContent(FlexAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777402, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(530:15)", "entry");
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
                        If.create();
                        if (this.pageType === 'sunlight') {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.SunlightSection.bind(this)();
                            });
                        }
                        else if (this.pageType === 'caffeine') {
                            this.ifElseBranchUpdateFunction(1, () => {
                                this.CaffeineSection.bind(this)();
                            });
                        }
                        else if (this.pageType === 'medication') {
                            this.ifElseBranchUpdateFunction(2, () => {
                                this.MedicationSection.bind(this)();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(3, () => {
                                this.SymptomSection.bind(this)();
                            });
                        }
                    }, If);
                    If.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.statusText.length > 0) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.statusText);
                                    Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(549:15)", "entry");
                                    Text.fontSize(13);
                                    Text.fontColor(COLOR_GREEN);
                                    Text.lineHeight(19);
                                    Text.padding(12);
                                    Text.width('100%');
                                    Text.backgroundColor(COLOR_LIGHT_GREEN);
                                    Text.borderRadius(14);
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
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777370, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/CheckinDetailPage.ets(559:13)", "entry");
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
        return "CheckinDetailPage";
    }
}
registerNamedRoute(() => new CheckinDetailPage(undefined, {}), "", { bundleName: "com.boundesu.BioBalance", moduleName: "entry", pagePath: "pages/CheckinDetailPage", pageFullPath: "entry/src/main/ets/pages/CheckinDetailPage", integratedHsp: "false", moduleType: "followWithHap" });
