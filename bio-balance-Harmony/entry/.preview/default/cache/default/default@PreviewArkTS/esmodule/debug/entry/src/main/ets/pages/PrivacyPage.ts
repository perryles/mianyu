if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface PrivacyPage_Params {
}
/**
 * 隐私与数据页（PEN-11）。
 * 对齐 iOS NSHealthShareUsageDescription 的权限用途说明，并说明本机存储、只读不写、
 * 云备份口径与未来云同步白名单边界。文案集中在 resources/base/element/string.json。
 */
const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
class PrivacyPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: PrivacyPage_Params) {
    }
    updateStateVars(params: PrivacyPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    SectionTitle(title: ResourceStr, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(17:5)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
    }
    BulletRow(icon: string, text: ResourceStr, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(26:5)", "entry");
            Row.width('100%');
            Row.alignItems(VerticalAlign.Top);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(icon);
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(27:7)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_GREEN);
            Text.width(22);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(text);
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(31:7)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_TEXT);
            Text.lineHeight(21);
            Text.textAlign(TextAlign.Start);
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        Row.pop();
    }
    BodyCard(body: ResourceStr, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(44:5)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(body);
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(45:7)", "entry");
            Text.fontSize(14);
            Text.fontColor(COLOR_TEXT);
            Text.lineHeight(22);
            Text.textAlign(TextAlign.Start);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(60:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor(COLOR_BACKGROUND);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(61:7)", "entry");
            Row.width('100%');
            Row.padding({ left: 18, right: 18, top: 18, bottom: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(62:9)", "entry");
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
            Column.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(69:9)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777413, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(70:11)", "entry");
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777412, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(75:11)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(86:7)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
            Scroll.layoutWeight(1);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 20 });
            Column.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(87:9)", "entry");
            Column.padding({ left: 18, right: 18, top: 8, bottom: 40 });
            Column.width('100%');
        }, Column);
        this.SectionTitle.bind(this)({ "id": 16777421, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BodyCard.bind(this)({ "id": 16777414, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.SectionTitle.bind(this)({ "id": 16777423, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(92:11)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.BulletRow.bind(this)('✓', { "id": 16777418, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BulletRow.bind(this)('✓', { "id": 16777416, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BulletRow.bind(this)('✓', { "id": 16777417, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        Column.pop();
        this.SectionTitle.bind(this)({ "id": 16777419, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/PrivacyPage.ets(104:11)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.BulletRow.bind(this)('✓', { "id": 16777409, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BulletRow.bind(this)('✓', { "id": 16777408, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BulletRow.bind(this)('✓', { "id": 16777407, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BulletRow.bind(this)('✓', { "id": 16777410, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        Column.pop();
        this.SectionTitle.bind(this)({ "id": 16777422, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BodyCard.bind(this)({ "id": 16777415, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.SectionTitle.bind(this)({ "id": 16777420, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        this.BodyCard.bind(this)({ "id": 16777411, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "PrivacyPage";
    }
}
registerNamedRoute(() => new PrivacyPage(undefined, {}), "", { bundleName: "com.boundesu.BioBalance", moduleName: "entry", pagePath: "pages/PrivacyPage", pageFullPath: "entry/src/main/ets/pages/PrivacyPage", integratedHsp: "false", moduleType: "followWithHap" });
