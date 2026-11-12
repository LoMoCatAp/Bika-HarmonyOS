import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_TEXT_TITLE, COLOR_TEXT_SECONDARY } from '../common/Constants';

@Component
export struct ReaderWidthOptions {
  @Prop contentWidth: number = 780;
  onWidthChange: (width: number) => void = (_width: number): void => {};

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('阅读宽度')
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_TITLE).layoutWeight(1)
        Button('默认', { type: ButtonType.Normal })
          .fontSize(13).fontColor(COLOR_PRIMARY).backgroundColor(Color.Transparent)
          .onClick((): void => this.onWidthChange(780))
      }
      .width('100%').height(44)
      Row({ space: 8 }) {
        Text('窄').fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        Slider({ value: this.contentWidth, min: 480, max: 1200, step: 20, style: SliderStyle.OutSet })
          .layoutWeight(1)
          .trackColor(COLOR_PRIMARY_TINT)
          .selectedColor(COLOR_PRIMARY)
          .showTips(false)
          .onChange((value: number, mode: SliderChangeMode): void => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onWidthChange(value);
            }
          })
        Text('宽').fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      }
      .width('100%').height(44)
    }
    .width('100%').padding({ left: 20, right: 20 })
  }
}
