import { ReaderPageLayout } from '../models/ReaderPageSpread';
import { ReaderTurnEffect } from '../models/ReaderCurlGeometry';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_TEXT_TITLE, COLOR_TEXT_SECONDARY } from '../common/Constants';

@Component
export struct ReaderLayoutOptions {
  @Prop layout: ReaderPageLayout = 'auto';
  @Prop firstSingle: boolean = false;
  @Prop effect: ReaderTurnEffect = 'slide';
  @Prop showTurnEffect: boolean = true;
  onEffectChange: (effect: ReaderTurnEffect) => void = (_effect: ReaderTurnEffect): void => {};
  onLayoutChange: (layout: ReaderPageLayout) => void = (_layout: ReaderPageLayout): void => {};
  onFirstSingleChange: (enabled: boolean) => void = (_enabled: boolean): void => {};

  @Builder
  layoutButton(value: ReaderPageLayout, label: string) {
    Button(label, { type: ButtonType.Capsule })
      .layoutWeight(1)
      .height(36)
      .fontSize(14)
      .fontColor(this.layout === value ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.layout === value ? COLOR_PRIMARY_TINT : Color.Transparent)
      .accessibilitySelected(this.layout === value)
      .onClick((): void => this.onLayoutChange(value))
  }

  @Builder
  effectButton(value: ReaderTurnEffect, label: string) {
    Button(label, { type: ButtonType.Capsule })
      .layoutWeight(1)
      .height(36)
      .fontSize(14)
      .fontColor(this.effect === value ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.effect === value ? COLOR_PRIMARY_TINT : Color.Transparent)
      .accessibilitySelected(this.effect === value)
      .onClick((): void => this.onEffectChange(value))
  }

  build() {
    Column({ space: 0 }) {
      if (this.showTurnEffect) {
        Text('翻页动效')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .width('100%')
          .padding({ top: 12, bottom: 10 })
        Row({ space: 8 }) {
          this.effectButton('slide', '滑动')
          this.effectButton('curl', '仿真')
        }
        .width('100%')
      }
      Text('页面布局')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .width('100%')
        .padding({ top: 12, bottom: 10 })
      Row({ space: 8 }) {
        this.layoutButton('auto', '自动')
        this.layoutButton('single', '单页')
        this.layoutButton('double', '双页')
      }
      .width('100%')
      Row() {
        Text('首图单独显示')
          .fontSize(15)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.firstSingle })
          .selectedColor(COLOR_PRIMARY)
          .onChange((enabled: boolean): void => this.onFirstSingleChange(enabled))
      }
      .width('100%').height(48)
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }
}
