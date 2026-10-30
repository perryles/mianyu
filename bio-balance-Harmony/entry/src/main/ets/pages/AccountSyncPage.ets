import type common from '@ohos.app.ability.common';
import { AgcCloudSyncTransport } from '../service/AgcCloudSyncTransport';
import { CloudSyncCoordinator, CloudSyncResult } from '../service/CloudSyncCoordinator';
import { CloudSyncSettings, CloudSyncStateStore } from '../service/CloudSyncStateStore';
import { HuaweiAccountService } from '../service/HuaweiAccountService';

const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';

@Entry
@Component
struct AccountSyncPage {
  @State signedIn: boolean = false;
  @State syncEnabled: boolean = false;
  @State busy: boolean = false;
  @State status: number = 0;
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
    if (this.store === undefined || this.account === undefined) return;
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
    if (this.account === undefined || this.store === undefined || this.busy) return;
    this.busy = true;
    try {
      const accountId: string = await this.account.signIn(true);
      await this.store.bindAccount(accountId);
      this.signedIn = true;
      this.syncEnabled = false;
      this.status = 0;
    } catch (error) {
      this.status = 3;
    }
    this.busy = false;
  }

  private async signOut(): Promise<void> {
    if (this.account === undefined || this.store === undefined || this.busy) return;
    this.busy = true;
    try { await this.account.signOut(); } catch (error) {}
    await this.store.bindAccount('');
    this.signedIn = false;
    this.syncEnabled = false;
    this.status = 0;
    this.busy = false;
  }

  private async changeSync(enabled: boolean): Promise<void> {
    if (this.store === undefined || !this.signedIn) return;
    const settings: CloudSyncSettings = await this.store.settings();
    this.syncEnabled = await this.store.setEnabled(settings.accountId, settings.generation, enabled) ? enabled : false;
    this.status = 0;
  }

  private async synchronize(): Promise<void> {
    if (this.coordinator === undefined || this.busy || !this.syncEnabled) return;
    this.busy = true;
    this.status = 1;
    const result: CloudSyncResult = await this.coordinator.synchronize();
    if (result.status === 'success') this.status = 2;
    else if (result.status === 'partial_failure') this.status = 4;
    else if (result.status === 'account_changed') this.status = 5;
    else this.status = 3;
    this.busy = false;
  }

  @Builder
  StatusText() {
    if (this.status === 1) Text($r('app.string.account_sync_running')).fontSize(13).fontColor(COLOR_SECONDARY)
    else if (this.status === 2) Text($r('app.string.account_sync_success')).fontSize(13).fontColor(COLOR_GREEN)
    else if (this.status === 3) Text($r('app.string.account_sync_failed')).fontSize(13).fontColor('#B85A50')
    else if (this.status === 4) Text($r('app.string.account_sync_partial')).fontSize(13).fontColor('#B85A50')
    else if (this.status === 5) Text($r('app.string.account_sync_account_changed')).fontSize(13).fontColor('#B85A50')
    else Text($r('app.string.account_sync_idle')).fontSize(13).fontColor(COLOR_SECONDARY)
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text('‹').fontSize(28).fontColor(COLOR_TEXT).width(38).height(38).textAlign(TextAlign.Center)
          .onClick(() => this.getUIContext().getRouter().back())
        Column({ space: 3 }) {
          Text($r('app.string.account_sync_title')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT).width('100%')
          Text($r('app.string.account_sync_subtitle')).fontSize(13).fontColor(COLOR_SECONDARY).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ left: 18, right: 18, top: 18, bottom: 12 })

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 14 }) {
            Text(this.signedIn ? $r('app.string.account_sync_signed_in') : $r('app.string.account_sync_signed_out'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT).width('100%')
            Button(this.signedIn ? $r('app.string.account_sync_sign_out') : $r('app.string.account_sync_sign_in'))
              .width('100%').height(44).fontColor(Color.White).backgroundColor(COLOR_GREEN).enabled(!this.busy)
              .onClick(() => { if (this.signedIn) this.signOut(); else this.signIn(); })
          }.padding(17).width('100%').backgroundColor(COLOR_CARD).borderRadius(22).alignItems(HorizontalAlign.Start)

          Column({ space: 12 }) {
            Row() {
              Text($r('app.string.account_sync_switch')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.syncEnabled }).enabled(this.signedIn && !this.busy)
                .onChange((enabled: boolean) => this.changeSync(enabled))
            }.width('100%')
            Text($r('app.string.account_sync_switch_note')).fontSize(13).fontColor(COLOR_SECONDARY).lineHeight(20).width('100%')
            Text($r('app.string.account_sync_whitelist')).fontSize(13).fontColor(COLOR_SECONDARY).lineHeight(20).width('100%')
            Button($r('app.string.account_sync_now')).width('100%').height(44).fontColor(Color.White).backgroundColor(COLOR_GREEN)
              .enabled(this.signedIn && this.syncEnabled && !this.busy).onClick(() => this.synchronize())
            this.StatusText()
          }.padding(17).width('100%').backgroundColor(COLOR_CARD).borderRadius(22).alignItems(HorizontalAlign.Start)
        }.padding({ left: 18, right: 18, top: 8, bottom: 40 }).width('100%')
      }.scrollBar(BarState.Off).width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(COLOR_BACKGROUND)
  }
}
