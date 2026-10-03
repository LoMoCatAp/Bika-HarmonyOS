/**
 * Bika 2*2 桌面卡片：「继续阅读」
 *
 * 动态卡片（isDynamic true）：点击必须用 postCardAction(action:'router')，
 * 不能用 FormLink（官方：FormLink 仅可在静态卡片中使用）。
 * 封面：Image('memory://' + coverKey)，fd 由 FormExtensionAbility 通过 formImages 下发。
 * 颜色：全部 app.color.*（base/dark 同名），跟随系统深浅色。
 */
let widgetCardStorage: LocalStorage = new LocalStorage();

@Entry(widgetCardStorage)
@Component
struct WidgetCard {
  @LocalStorageProp('continueTitle') continueTitle: string = '';
  @LocalStorageProp('continueSubtitle') continueSubtitle: string = '';
  @LocalStorageProp('continueComicId') continueComicId: string = '';
  @LocalStorageProp('continueCoverKey') continueCoverKey: string = '';
  @LocalStorageProp('showCover') showCover: string = 'true';

  private readonly ABILITY_NAME: string = 'EntryAbility';
  private readonly FULL: string = '100%';

  /** 只有开关不是明确关闭、且拿到了 memory:// key 才渲染真实封面 */
  private canShowCover(): boolean {
    return this.showCover !== 'false' && this.continueCoverKey.length > 0;
  }

  private openReader(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: {
        action: 'continue_reading',
        comicId: this.continueComicId,
        comicTitle: this.continueTitle
      }
    });
  }

  /** 排障：确认卡片侧真实收到的下发字段 */
  private trace(): void {
    try {
      console.info('[BikaWidget:WidgetCard] showCover=' + this.showCover +
        ' coverKey=' + this.continueCoverKey + ' title=' + this.continueTitle);
    } catch (err) {
    }
  }

  build() {
    Column() {
      Row() {
        // ─── 封面 / 骨架占位（撑满左侧高度）───
        Stack() {
          if (this.canShowCover()) {
            Image('memory://' + this.continueCoverKey)
              .width(this.FULL)
              .height(this.FULL)
              .objectFit(ImageFit.Cover)
          } else {
            Text('')
              .width(this.FULL)
              .height(this.FULL)
              .backgroundColor($r('app.color.bika_placeholder'))
          }
        }
        .width(52)
        .height(this.FULL)
        .borderRadius(12)
        .clip(true)
        .backgroundColor($r('app.color.bika_primary_tint'))

        Column() {
          if (this.continueTitle.length > 0) {
            Text(this.continueTitle)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.bika_text_title'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text($r('app.string.widget_continue_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.bika_text_title'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.continueSubtitle.length > 0) {
            Text(this.continueSubtitle)
              .fontSize(11)
              .fontColor($r('app.color.bika_text_secondary'))
              .maxLines(2)
              .margin({ top: 4 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text($r('app.string.widget_continue_subtitle'))
              .fontSize(11)
              .fontColor($r('app.color.bika_text_secondary'))
              .maxLines(2)
              .margin({ top: 4 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .height(this.FULL)
        .margin({ left: 10 })
      }
      .width(this.FULL)
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.widget_continue_action'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.bika_primary'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(9)
          .backgroundColor($r('app.color.bika_primary_tint'))
      }
      .width(this.FULL)
      .justifyContent(FlexAlign.Start)
      .margin({ top: 8 })
    }
    .width(this.FULL)
    .height(this.FULL)
    .padding(12)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.bika_card'))
    .borderRadius(16)
    .onClick((): void => this.openReader())
    .onAppear((): void => this.trace())
  }
}
