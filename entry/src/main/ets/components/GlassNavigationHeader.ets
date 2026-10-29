import { DetailGlassCapsule } from './DetailGlassCapsule';
import { COLOR_TEXT_TITLE } from '../common/Constants';

/** 与主页一样，整条标题透明，只有返回按钮在独立 Navigation.title 内绘制光感。 */
@Component
export struct GlassNavigationHeader {
  @Prop title: string = '';
  @StorageProp('bika_animations') animationsOn: boolean = true;
  onBack: () => void = (): void => {};

  @Builder
  backAction() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontColor([COLOR_TEXT_TITLE])
    }
    .width(40).height(40)
    .backgroundColor(Color.Transparent)
    .accessibilityText('返回')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
    .onClick((): void => this.onBack())
  }

  build() {
    Row({ space: 12 }) {
      DetailGlassCapsule({
        capsuleWidth: 40, capsuleHeight: 40,
        content: (): void => { this.backAction(); }
      })
      Text(this.title)
        .fontSize(24)
        .maxFontScale(1.3)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .accessibilityLevel('yes')
    }
    .width('100%').height(56)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(Color.Transparent)
  }
}
