import type common from '@ohos.app.ability.common';
import { CheckinRecordStore } from '../model/CheckinRecordStore';

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

@Entry
@Component
struct CheckinDetailPage {
  @State pageType: string = '';
  @State loaded: boolean = false;
  @State statusText: string = '';
  @State sunlightInput: string = '';
  @State sunlightMinutes: number = 0;
  @State sunlightSaved: boolean = false;
  @State caffeineList: CaffeineItem[] = [];
  @State caffeineOptions: number[] = [50, 100, 150];
  @State selectedCaffeineIndex: number = 1;
  @State medicationList: MedicationItem[] = [];
  @State nameInput: string = '';
  @State doseInput: string = '';
  @State symptomList: SymptomItem[] = [];
  @State symptomTypes: string[] = ['symptom_headache', 'symptom_fatigue', 'symptom_anxiety', 'symptom_insomnia',
    'symptom_neck_pain', 'symptom_other'];
  @State selectedSymptomIndex: number = 0;
  @State selectedIntensity: number = 3;

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
    if (context === undefined) return '';
    if (first === undefined) return context.resourceManager.getStringByNameSync(name);
    if (second === undefined) return context.resourceManager.getStringByNameSync(name, first);
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
    } else if (this.pageType === 'caffeine') {
      this.caffeineList = await CheckinRecordStore.loadCaffeine(context, today);
    } else if (this.pageType === 'medication') {
      this.medicationList = await CheckinRecordStore.loadMedication(context, today);
    } else if (this.pageType === 'symptom') {
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
    if (resourceIndex >= 0) return this.t(value);
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

  @Builder
  Header() {
    Row({ space: 12 }) {
      Text('‹')
        .fontSize(28)
        .fontColor(COLOR_TEXT)
        .width(38)
        .height(38)
        .textAlign(TextAlign.Center)
        .onClick(() => this.getUIContext().getRouter().back())
      Column({ space: 3 }) {
        Text(this.title())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT)
          .width('100%')
        Text($r('app.string.checkin_private_subtitle'))
          .fontSize(13)
          .fontColor(COLOR_SECONDARY)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  SunlightSection() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text(this.sunlightSaved ? this.minutesText(this.sunlightMinutes) : this.t('checkin_not_recorded_today'))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_ORANGE)
          .width('100%')
        Text($r('app.string.checkin_sunlight_help'))
          .fontSize(13)
          .fontColor(COLOR_SECONDARY)
          .lineHeight(19)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)

      Row({ space: 10 }) {
        TextInput({ text: this.sunlightInput, placeholder: $r('app.string.checkin_sunlight_placeholder') })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor('#F4F7F5')
          .borderRadius(14)
          .onChange((value: string) => {
            this.sunlightInput = value;
          })
        Button($r('app.string.save'))
          .height(44)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(COLOR_ORANGE)
          .borderRadius(14)
          .onClick(() => this.saveSunlight())
      }
      .width('100%')
    }
    .padding(17)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
  }

  @Builder
  CaffeineSection() {
    Column({ space: 12 }) {
      Text($r('app.string.checkin_record_intake'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(this.caffeineOptions, (amount: number, index: number) => {
          Column({ space: 4 }) {
            Text(`${amount}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.selectedCaffeineIndex === index ? Color.White : COLOR_TEXT)
            Text('mg')
              .fontSize(10)
              .fontColor(this.selectedCaffeineIndex === index ? '#E8FFF4' : COLOR_SECONDARY)
          }
          .layoutWeight(1)
          .height(54)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.selectedCaffeineIndex === index ? COLOR_GREEN : '#F1F5F2')
          .borderRadius(14)
          .onClick(() => {
            this.selectedCaffeineIndex = index;
          })
        }, (amount: number) => `${amount}`)
      }
      .width('100%')
      Button($r('app.string.checkin_add_once'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(COLOR_GREEN)
        .borderRadius(16)
        .onClick(() => this.addCaffeine())

      if (this.caffeineList.length > 0) {
        Divider()
          .color('#EDF0EE')
        ForEach(this.caffeineList, (item: CaffeineItem) => {
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(`${item.amount} mg`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Text(item.time)
                .fontSize(12)
                .fontColor(COLOR_SECONDARY)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text($r('app.string.delete'))
              .fontSize(13)
              .fontColor(COLOR_RED)
              .onClick(() => this.removeCaffeine(item.id))
          }
          .width('100%')
        }, (item: CaffeineItem) => item.id)
      }
    }
    .padding(17)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
  }

  @Builder
  MedicationSection() {
    Column({ space: 12 }) {
      Text($r('app.string.checkin_record_medication'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      TextInput({ text: this.nameInput, placeholder: $r('app.string.checkin_medication_name_placeholder') })
        .height(44)
        .fontSize(14)
        .backgroundColor('#F4F7F5')
        .borderRadius(14)
        .width('100%')
        .onChange((value: string) => {
          this.nameInput = value;
        })
      TextInput({ text: this.doseInput, placeholder: $r('app.string.checkin_medication_dose_placeholder') })
        .height(44)
        .fontSize(14)
        .backgroundColor('#F4F7F5')
        .borderRadius(14)
        .width('100%')
        .onChange((value: string) => {
          this.doseInput = value;
        })
      Button($r('app.string.checkin_add_medication'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(COLOR_BLUE)
        .borderRadius(16)
        .onClick(() => this.addMedication())

      if (this.medicationList.length > 0) {
        Divider()
          .color('#EDF0EE')
        ForEach(this.medicationList, (item: MedicationItem) => {
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(item.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Text(item.dose.length > 0 ? `${item.dose} · ${item.time}` : item.time)
                .fontSize(12)
                .fontColor(COLOR_SECONDARY)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text($r('app.string.delete'))
              .fontSize(13)
              .fontColor(COLOR_RED)
              .onClick(() => this.removeMedication(item.id))
          }
          .width('100%')
        }, (item: MedicationItem) => item.id)
      }
    }
    .padding(17)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
  }

  @Builder
  SymptomSection() {
    Column({ space: 12 }) {
      Text($r('app.string.checkin_record_symptom'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(this.symptomTypes, (type: string, index: number) => {
            Text(this.symptomLabel(type))
            .fontSize(13)
            .fontColor(this.selectedSymptomIndex === index ? Color.White : COLOR_TEXT)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.selectedSymptomIndex === index ? COLOR_GREEN : '#F1F5F2')
            .borderRadius(14)
            .onClick(() => {
              this.selectedSymptomIndex = index;
            })
        }, (type: string) => type)
      }
      .width('100%')

      Row() {
        Text($r('app.string.checkin_intensity'))
          .fontSize(14)
          .fontColor(COLOR_SECONDARY)
        Blank()
        Text(this.intensityLabel(this.selectedIntensity))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_RED)
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach([1, 2, 3, 4, 5], (value: number) => {
          Text(`${value}`)
            .width(34)
            .height(34)
            .textAlign(TextAlign.Center)
            .fontSize(14)
            .fontColor(this.selectedIntensity === value ? Color.White : COLOR_SECONDARY)
            .borderRadius(17)
            .backgroundColor(this.selectedIntensity === value ? COLOR_RED : '#F1F5F2')
            .onClick(() => {
              this.selectedIntensity = value;
            })
        }, (value: number) => `${value}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Button($r('app.string.checkin_add_symptom'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(COLOR_RED)
        .borderRadius(16)
        .onClick(() => this.addSymptom())

      if (this.symptomList.length > 0) {
        Divider()
          .color('#EDF0EE')
        ForEach(this.symptomList, (item: SymptomItem) => {
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text(this.symptomLabel(item.type))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT)
                .width('100%')
              Text(`${this.intensityLabel(item.intensity)} · ${item.time}`)
                .fontSize(12)
                .fontColor(COLOR_SECONDARY)
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text($r('app.string.delete'))
              .fontSize(13)
              .fontColor(COLOR_RED)
              .onClick(() => this.removeSymptom(item.id))
          }
          .width('100%')
        }, (item: SymptomItem) => item.id)
      }
    }
    .padding(17)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
  }

  build() {
    Column({ space: 16 }) {
      this.Header()

      Scroll() {
        Column({ space: 14 }) {
          if (!this.loaded) {
            Column() {
              Text($r('app.string.loading'))
                .fontSize(14)
                .fontColor(COLOR_SECONDARY)
            }
            .padding(30)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            if (this.pageType === 'sunlight') {
              this.SunlightSection()
            } else if (this.pageType === 'caffeine') {
              this.CaffeineSection()
            } else if (this.pageType === 'medication') {
              this.MedicationSection()
            } else {
              this.SymptomSection()
            }

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

            Text($r('app.string.checkin_privacy_emergency'))
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
