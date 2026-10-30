import type common from '@ohos.app.ability.common';
import { ReminderService, REMINDER_PRESETS } from '../service/ReminderService';
import type { ReminderPreset, ReminderSetting } from '../service/ReminderService';

const COLOR_BACKGROUND: string = '#F4F7F5';
const COLOR_CARD: string = '#FFFFFFFF';
const COLOR_TEXT: string = '#17221D';
const COLOR_SECONDARY: string = '#68756E';
const COLOR_GREEN: string = '#1E8E63';
const COLOR_LIGHT_GREEN: string = '#E2F4EA';

@Entry
@Component
struct ReminderSettingsPage {
  @State settings: ReminderSetting[] = [];
  @State statusText: string = '';
  @State loaded: boolean = false;

  private t(name: string, first?: string | number, second?: string | number): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) return '';
    if (first === undefined) return context.resourceManager.getStringByNameSync(name);
    if (second === undefined) return context.resourceManager.getStringByNameSync(name, first);
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
            this.statusText = this.t('reminder_time_saved_format', this.presetTitle(REMINDER_PRESETS[index]),
              this.timeText(value.hour, value.minute));
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

  @Builder
  ReminderCard(preset: ReminderPreset, index: number) {
    Column({ space: 12 }) {
      Row({ space: 13 }) {
        Text(this.iconFor(preset))
          .fontSize(20)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .backgroundColor(COLOR_LIGHT_GREEN)
          .borderRadius(14)
        Column({ space: 4 }) {
          Text(this.presetTitle(preset))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
          Text(this.t(this.settings[index].enabled ? 'reminder_daily' : 'reminder_off'))
            .fontSize(12)
            .fontColor(COLOR_SECONDARY)
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.settings[index].enabled })
          .selectedColor(COLOR_GREEN)
          .onChange((isOn: boolean) => {
            this.toggleReminder(index, isOn);
          })
      }
      .width('100%')

      Divider()
        .color('#EDF0EE')

      Row() {
        Text($r('app.string.reminder_time'))
          .fontSize(14)
          .fontColor(COLOR_SECONDARY)
        Blank()
        Text(this.timeText(this.settings[index].hour, this.settings[index].minute))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_GREEN)
        Text(' ›')
          .fontSize(18)
          .fontColor('#A8B1AC')
      }
      .width('100%')
      .onClick(() => this.pickTime(index))
    }
    .padding(17)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
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
          Text($r('app.string.reminder_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
          Text($r('app.string.reminder_subtitle'))
            .fontSize(13)
            .fontColor(COLOR_SECONDARY)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Scroll() {
        Column({ space: 14 }) {
          ForEach(REMINDER_PRESETS, (preset: ReminderPreset, index: number) => {
            this.ReminderCard(preset, index)
          }, (preset: ReminderPreset) => preset.key)

          Text($r('app.string.reminder_disclaimer'))
            .fontSize(12)
            .fontColor(COLOR_SECONDARY)
            .lineHeight(18)
            .width('100%')

          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(13)
              .fontColor(COLOR_GREEN)
              .lineHeight(19)
              .padding(12)
              .width('100%')
              .backgroundColor(COLOR_LIGHT_GREEN)
              .borderRadius(14)
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
