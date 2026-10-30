if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface ReminderSettingsPage_Params {
    settings?: ReminderSetting[];
    statusText?: string;
    loaded?: boolean;
}
import type common from "@ohos:app.ability.common";
import { ReminderService, REMINDER_PRESETS } from "@normalized:N&&&entry/src/main/ets/service/ReminderService&";
import type { ReminderPreset, ReminderSetting } from "@normalized:N&&&entry/src/main/ets/service/ReminderService&";
const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
const COLOR_LIGHT_GREEN: string = '#E2F4EA';
class ReminderSettingsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__settings = new ObservedPropertyObjectPU([], this, "settings");
        this.__statusText = new ObservedPropertySimplePU('', this, "statusText");
        this.__loaded = new ObservedPropertySimplePU(false, this, "loaded");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: ReminderSettingsPage_Params) {
        if (params.settings !== undefined) {
            this.settings = params.settings;
        }
        if (params.statusText !== undefined) {
            this.statusText = params.statusText;
        }
        if (params.loaded !== undefined) {
            this.loaded = params.loaded;
        }
    }
    updateStateVars(params: ReminderSettingsPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__settings.purgeDependencyOnElmtId(rmElmtId);
        this.__statusText.purgeDependencyOnElmtId(rmElmtId);
        this.__loaded.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__settings.aboutToBeDeleted();
        this.__statusText.aboutToBeDeleted();
        this.__loaded.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __settings: ObservedPropertyObjectPU<ReminderSetting[]>;
    get settings() {
        return this.__settings.get();
    }
    set settings(newValue: ReminderSetting[]) {
        this.__settings.set(newValue);
    }
    private __statusText: ObservedPropertySimplePU<string>;
    get statusText() {
        return this.__statusText.get();
    }
    set statusText(newValue: string) {
        this.__statusText.set(newValue);
    }
    private __loaded: ObservedPropertySimplePU<boolean>;
    get loaded() {
        return this.__loaded.get();
    }
    set loaded(newValue: boolean) {
        this.__loaded.set(newValue);
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
    private presetTitle(preset: ReminderPreset): string {
        return this.t(preset.titleKey);
    }
    aboutToAppear(): void {
        this.loadSettings();
    }
    private async loadSettings(): Promise<void> {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) {
            this.statusText = this.t('reminder_storage_unavailable');
            this.loaded = true;
            return;
        }
        const list: ReminderSetting[] = [];
        for (let index = 0; index < REMINDER_PRESETS.length; index++) {
            const preset: ReminderPreset = REMINDER_PRESETS[index];
            const setting: ReminderSetting = await ReminderService.loadSetting(context, preset.key);
            list.push(setting);
        }
        this.settings = list;
        this.loaded = true;
    }
    private timeText(hour: number, minute: number): string {
        return `${`${hour}`.padStart(2, '0')}:${`${minute}`.padStart(2, '0')}`;
    }
    private async toggleReminder(index: number, enabled: boolean): Promise<void> {
        const current: ReminderSetting = this.settings[index];
        if (enabled) {
            const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
            if (context === undefined) {
                return;
            }
            const granted: boolean = await ReminderService.requestNotificationPermission(context);
            if (!granted) {
                this.statusText = this.t('reminder_permission_required');
                return;
            }
        }
        const hostContext = this.getUIContext().getHostContext();
        if (hostContext === undefined) {
            return;
        }
        const updated: ReminderSetting = { enabled, hour: current.hour, minute: current.minute };
        await ReminderService.saveSetting(hostContext, REMINDER_PRESETS[index].key, updated);
        const list: ReminderSetting[] = this.settings.slice();
        list[index] = updated;
        this.settings = list;
        const title: string = this.presetTitle(REMINDER_PRESETS[index]);
        this.statusText = this.t(enabled ? 'reminder_enabled_format' : 'reminder_disabled_format', title);
    }
    private pickTime(index: number): void {
        const current: ReminderSetting = this.settings[index];
        TimePickerDialog.show({
            selected: new Date(2026, 0, 1, current.hour, current.minute),
            useMilitaryTime: true,
            onAccept: (value: TimePickerResult) => {
                const updated: ReminderSetting = { enabled: current.enabled, hour: value.hour, minute: value.minute };
                const list: ReminderSetting[] = this.settings.slice();
                list[index] = updated;
                this.settings = list;
                const hostContext = this.getUIContext().getHostContext();
                if (hostContext !== undefined) {
                    ReminderService.saveSetting(hostContext, REMINDER_PRESETS[index].key, updated).then(() => {
                        this.statusText = this.t('reminder_time_saved_format', this.presetTitle(REMINDER_PRESETS[index]), this.timeText(value.hour, value.minute));
                    }).catch(() => {
                        this.statusText = this.t('reminder_time_save_failed');
                    });
                }
            }
        });
    }
    private iconFor(preset: ReminderPreset): string {
        if (preset.key === 'water') {
            return '💧';
        }
        if (preset.key === 'medication') {
            return '💊';
        }
        return '🚶';
    }
    ReminderCard(preset: ReminderPreset, index: number, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(117:5)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 13 });
            Row.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(118:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.iconFor(preset));
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(119:9)", "entry");
            Text.fontSize(20);
            Text.width(44);
            Text.height(44);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(COLOR_LIGHT_GREEN);
            Text.borderRadius(14);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(126:9)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.presetTitle(preset));
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(127:11)", "entry");
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.t(this.settings[index].enabled ? 'reminder_daily' : 'reminder_off'));
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(132:11)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Toggle.create({ type: ToggleType.Switch, isOn: this.settings[index].enabled });
            Toggle.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(139:9)", "entry");
            Toggle.selectedColor(COLOR_GREEN);
            Toggle.onChange((isOn: boolean) => {
                this.toggleReminder(index, isOn);
            });
        }, Toggle);
        Toggle.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
            Divider.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(147:7)", "entry");
            Divider.color('#EDF0EE');
        }, Divider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(150:7)", "entry");
            Row.width('100%');
            Row.onClick(() => this.pickTime(index));
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777437, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(151:9)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_SECONDARY);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(154:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.timeText(this.settings[index].hour, this.settings[index].minute));
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(155:9)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_GREEN);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(' ›');
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(159:9)", "entry");
            Text.fontSize(18);
            Text.fontColor('#A8B1AC');
        }, Text);
        Text.pop();
        Row.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(173:5)", "entry");
            Column.padding({ left: 18, right: 18, top: 14, bottom: 18 });
            Column.width('100%');
            Column.height('100%');
            Column.linearGradient({ angle: 180, colors: [['#F6FAF7', 0.0], [COLOR_BACKGROUND, 1.0]] });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(174:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(175:9)", "entry");
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
            Column.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(182:9)", "entry");
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777440, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(183:11)", "entry");
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777436, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(188:11)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(197:7)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.layoutWeight(1);
            Scroll.width('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 14 });
            Column.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(198:9)", "entry");
            Column.padding({ left: 18, right: 18, top: 10, bottom: 30 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = (_item, index: number) => {
                const preset = _item;
                this.ReminderCard.bind(this)(preset, index);
            };
            this.forEachUpdateFunction(elmtId, REMINDER_PRESETS, forEachItemGenFunction, (preset: ReminderPreset) => preset.key, true, false);
        }, ForEach);
        ForEach.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777426, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(203:11)", "entry");
            Text.fontSize(12);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(18);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.statusText.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.statusText);
                        Text.debugLine("entry/src/main/ets/pages/ReminderSettingsPage.ets(210:13)", "entry");
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
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "ReminderSettingsPage";
    }
}
registerNamedRoute(() => new ReminderSettingsPage(undefined, {}), "", { bundleName: "com.boundesu.BioBalance", moduleName: "entry", pagePath: "pages/ReminderSettingsPage", pageFullPath: "entry/src/main/ets/pages/ReminderSettingsPage", integratedHsp: "false", moduleType: "followWithHap" });
