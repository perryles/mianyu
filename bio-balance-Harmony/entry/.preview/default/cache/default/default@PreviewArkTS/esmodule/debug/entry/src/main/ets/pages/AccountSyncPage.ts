if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface AccountSyncPage_Params {
    signedIn?: boolean;
    syncEnabled?: boolean;
    busy?: boolean;
    status?: number;
    store?: CloudSyncStateStore;
    account?: HuaweiAccountService;
    coordinator?: CloudSyncCoordinator;
}
import type common from "@ohos:app.ability.common";
import { AgcCloudSyncTransport } from "@normalized:N&&&entry/src/main/ets/service/AgcCloudSyncTransport&";
import { CloudSyncCoordinator } from "@normalized:N&&&entry/src/main/ets/service/CloudSyncCoordinator&";
import type { CloudSyncResult } from "@normalized:N&&&entry/src/main/ets/service/CloudSyncCoordinator&";
import { CloudSyncStateStore } from "@normalized:N&&&entry/src/main/ets/service/CloudSyncStateStore&";
import type { CloudSyncSettings } from "@normalized:N&&&entry/src/main/ets/service/CloudSyncStateStore&";
import { HuaweiAccountService } from "@normalized:N&&&entry/src/main/ets/service/HuaweiAccountService&";
const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
class AccountSyncPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__signedIn = new ObservedPropertySimplePU(false, this, "signedIn");
        this.__syncEnabled = new ObservedPropertySimplePU(false, this, "syncEnabled");
        this.__busy = new ObservedPropertySimplePU(false, this, "busy");
        this.__status = new ObservedPropertySimplePU(0, this, "status");
        this.store = undefined;
        this.account = undefined;
        this.coordinator = undefined;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: AccountSyncPage_Params) {
        if (params.signedIn !== undefined) {
            this.signedIn = params.signedIn;
        }
        if (params.syncEnabled !== undefined) {
            this.syncEnabled = params.syncEnabled;
        }
        if (params.busy !== undefined) {
            this.busy = params.busy;
        }
        if (params.status !== undefined) {
            this.status = params.status;
        }
        if (params.store !== undefined) {
            this.store = params.store;
        }
        if (params.account !== undefined) {
            this.account = params.account;
        }
        if (params.coordinator !== undefined) {
            this.coordinator = params.coordinator;
        }
    }
    updateStateVars(params: AccountSyncPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__signedIn.purgeDependencyOnElmtId(rmElmtId);
        this.__syncEnabled.purgeDependencyOnElmtId(rmElmtId);
        this.__busy.purgeDependencyOnElmtId(rmElmtId);
        this.__status.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__signedIn.aboutToBeDeleted();
        this.__syncEnabled.aboutToBeDeleted();
        this.__busy.aboutToBeDeleted();
        this.__status.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __signedIn: ObservedPropertySimplePU<boolean>;
    get signedIn() {
        return this.__signedIn.get();
    }
    set signedIn(newValue: boolean) {
        this.__signedIn.set(newValue);
    }
    private __syncEnabled: ObservedPropertySimplePU<boolean>;
    get syncEnabled() {
        return this.__syncEnabled.get();
    }
    set syncEnabled(newValue: boolean) {
        this.__syncEnabled.set(newValue);
    }
    private __busy: ObservedPropertySimplePU<boolean>;
    get busy() {
        return this.__busy.get();
    }
    set busy(newValue: boolean) {
        this.__busy.set(newValue);
    }
    private __status: ObservedPropertySimplePU<number>;
    get status() {
        return this.__status.get();
    }
    set status(newValue: number) {
        this.__status.set(newValue);
    }
    private store?: CloudSyncStateStore;
    private account?: HuaweiAccountService;
    private coordinator?: CloudSyncCoordinator;
    aboutToAppear(): void {
        const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.store = new CloudSyncStateStore(context);
        this.account = new HuaweiAccountService(context);
        this.coordinator = new CloudSyncCoordinator(this.store, new AgcCloudSyncTransport(this.account), this.account);
        this.restore();
    }
    private async restore(): Promise<void> {
        if (this.store === undefined || this.account === undefined)
            return;
        const accountId: string = await this.account.restoreSession();
        if (accountId.length === 0) {
            await this.store.bindAccount('');
            this.signedIn = false;
            this.syncEnabled = false;
            return;
        }
        const settings: CloudSyncSettings = await this.store.bindAccount(accountId);
        this.signedIn = true;
        this.syncEnabled = settings.enabled;
    }
    private async signIn(): Promise<void> {
        if (this.account === undefined || this.store === undefined || this.busy)
            return;
        this.busy = true;
        try {
            const accountId: string = await this.account.signIn(true);
            await this.store.bindAccount(accountId);
            this.signedIn = true;
            this.syncEnabled = false;
            this.status = 0;
        }
        catch (error) {
            this.status = 3;
        }
        this.busy = false;
    }
    private async signOut(): Promise<void> {
        if (this.account === undefined || this.store === undefined || this.busy)
            return;
        this.busy = true;
        try {
            await this.account.signOut();
        }
        catch (error) { }
        await this.store.bindAccount('');
        this.signedIn = false;
        this.syncEnabled = false;
        this.status = 0;
        this.busy = false;
    }
    private async changeSync(enabled: boolean): Promise<void> {
        if (this.store === undefined || !this.signedIn)
            return;
        const settings: CloudSyncSettings = await this.store.settings();
        this.syncEnabled = await this.store.setEnabled(settings.accountId, settings.generation, enabled) ? enabled : false;
        this.status = 0;
    }
    private async synchronize(): Promise<void> {
        if (this.coordinator === undefined || this.busy || !this.syncEnabled)
            return;
        this.busy = true;
        this.status = 1;
        const result: CloudSyncResult = await this.coordinator.synchronize();
        if (result.status === 'success')
            this.status = 2;
        else if (result.status === 'partial_failure')
            this.status = 4;
        else if (result.status === 'account_changed')
            this.status = 5;
        else
            this.status = 3;
        this.busy = false;
    }
    StatusText(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.status === 1) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777494, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(93:28)", "entry");
                        Text.fontSize(13);
                        Text.fontColor(COLOR_SECONDARY);
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.status === 2) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777500, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(94:33)", "entry");
                        Text.fontSize(13);
                        Text.fontColor(COLOR_GREEN);
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.status === 3) {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777490, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(95:33)", "entry");
                        Text.fontSize(13);
                        Text.fontColor('#B85A50');
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.status === 4) {
                this.ifElseBranchUpdateFunction(3, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777493, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(96:33)", "entry");
                        Text.fontSize(13);
                        Text.fontColor('#B85A50');
                    }, Text);
                    Text.pop();
                });
            }
            else if (this.status === 5) {
                this.ifElseBranchUpdateFunction(4, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777489, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(97:33)", "entry");
                        Text.fontSize(13);
                        Text.fontColor('#B85A50');
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(5, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777491, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(98:10)", "entry");
                        Text.fontSize(13);
                        Text.fontColor(COLOR_SECONDARY);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(102:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor(COLOR_BACKGROUND);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(103:7)", "entry");
            Row.width('100%');
            Row.padding({ left: 18, right: 18, top: 18, bottom: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(104:9)", "entry");
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
            Column.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(106:9)", "entry");
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777503, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(107:11)", "entry");
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777499, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(108:11)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.width('100%');
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(112:7)", "entry");
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
            Scroll.layoutWeight(1);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 18 });
            Column.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(113:9)", "entry");
            Column.padding({ left: 18, right: 18, top: 8, bottom: 40 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 14 });
            Column.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(114:11)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.signedIn ? { "id": 16777497, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" } : { "id": 16777498, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(115:13)", "entry");
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.signedIn ? { "id": 16777496, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" } : { "id": 16777495, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Button.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(117:13)", "entry");
            Button.width('100%');
            Button.height(44);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_GREEN);
            Button.enabled(!this.busy);
            Button.onClick(() => { if (this.signedIn)
                this.signOut();
            else
                this.signIn(); });
        }, Button);
        Button.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(122:11)", "entry");
            Column.padding(17);
            Column.width('100%');
            Column.backgroundColor(COLOR_CARD);
            Column.borderRadius(22);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(123:13)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777501, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(124:15)", "entry");
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(COLOR_TEXT);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(125:15)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Toggle.create({ type: ToggleType.Switch, isOn: this.syncEnabled });
            Toggle.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(126:15)", "entry");
            Toggle.enabled(this.signedIn && !this.busy);
            Toggle.onChange((enabled: boolean) => this.changeSync(enabled));
        }, Toggle);
        Toggle.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777502, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(129:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(20);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777504, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(130:13)", "entry");
            Text.fontSize(13);
            Text.fontColor(COLOR_SECONDARY);
            Text.lineHeight(20);
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777492, "type": 10003, params: [], "bundleName": "com.boundesu.BioBalance", "moduleName": "entry" });
            Button.debugLine("entry/src/main/ets/pages/AccountSyncPage.ets(131:13)", "entry");
            Button.width('100%');
            Button.height(44);
            Button.fontColor(Color.White);
            Button.backgroundColor(COLOR_GREEN);
            Button.enabled(this.signedIn && this.syncEnabled && !this.busy);
            Button.onClick(() => this.synchronize());
        }, Button);
        Button.pop();
        this.StatusText.bind(this)();
        Column.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "AccountSyncPage";
    }
}
registerNamedRoute(() => new AccountSyncPage(undefined, {}), "", { bundleName: "com.boundesu.BioBalance", moduleName: "entry", pagePath: "pages/AccountSyncPage", pageFullPath: "entry/src/main/ets/pages/AccountSyncPage", integratedHsp: "false", moduleType: "followWithHap" });
