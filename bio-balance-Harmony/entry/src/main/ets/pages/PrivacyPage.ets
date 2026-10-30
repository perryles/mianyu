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

@Entry
@Component
struct PrivacyPage {
  @Builder
  SectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(COLOR_SECONDARY)
      .width('100%')
  }

  @Builder
  BulletRow(icon: string, text: ResourceStr) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(14)
        .fontColor(COLOR_GREEN)
        .width(22)
      Text(text)
        .fontSize(14)
        .fontColor(COLOR_TEXT)
        .lineHeight(21)
        .textAlign(TextAlign.Start)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  BodyCard(body: ResourceStr) {
    Column({ space: 10 }) {
      Text(body)
        .fontSize(14)
        .fontColor(COLOR_TEXT)
        .lineHeight(22)
        .textAlign(TextAlign.Start)
        .width('100%')
    }
    .padding(17)
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(22)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text('‹')
          .fontSize(28)
          .fontColor(COLOR_TEXT)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .onClick(() => this.getUIContext().getRouter().back())
        Column({ space: 3 }) {
          Text($r('app.string.privacy_page_title'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT)
            .width('100%')
          Text($r('app.string.privacy_page_subtitle'))
            .fontSize(13)
            .fontColor(COLOR_SECONDARY)
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 12 })

      Scroll() {
        Column({ space: 20 }) {
          this.SectionTitle($r('app.string.privacy_section_permission'))
          this.BodyCard($r('app.string.privacy_permission_body'))

          this.SectionTitle($r('app.string.privacy_section_scope'))
          Column({ space: 12 }) {
            this.BulletRow('✓', $r('app.string.privacy_scope_steps'))
            this.BulletRow('✓', $r('app.string.privacy_scope_heart'))
            this.BulletRow('✓', $r('app.string.privacy_scope_sleep'))
          }
          .padding(17)
          .width('100%')
          .backgroundColor(COLOR_CARD)
          .borderRadius(22)
          .alignItems(HorizontalAlign.Start)

          this.SectionTitle($r('app.string.privacy_section_boundary'))
          Column({ space: 12 }) {
            this.BulletRow('✓', $r('app.string.privacy_boundary_readonly'))
            this.BulletRow('✓', $r('app.string.privacy_boundary_local'))
            this.BulletRow('✓', $r('app.string.privacy_boundary_backup'))
            this.BulletRow('✓', $r('app.string.privacy_boundary_sync'))
          }
          .padding(17)
          .width('100%')
          .backgroundColor(COLOR_CARD)
          .borderRadius(22)
          .alignItems(HorizontalAlign.Start)

          this.SectionTitle($r('app.string.privacy_section_revoke'))
          this.BodyCard($r('app.string.privacy_revoke_body'))

          this.SectionTitle($r('app.string.privacy_section_disclaimer'))
          this.BodyCard($r('app.string.privacy_disclaimer_body'))
        }
        .padding({ left: 18, right: 18, top: 8, bottom: 40 })
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BACKGROUND)
  }
}
