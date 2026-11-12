import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_DIVIDER } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { CHANGELOG_ENTRIES } from '../../common/Changelog';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileAboutPage {
  aboutScroller: Scroller = new Scroller();
  accentColor: ResourceColor = $r('app.color.bika_primary');
  openChangelog: () => void = (): void => {};
  openPrivacyPolicy: () => void = (): void => {};
  openExternalLink: (url: string) => void = (url: string): void => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  closeSubpage: () => void = (): void => {};

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      Scroll(this.aboutScroller) {
        Column({ space: 14 }) {
          Text('应用信息')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
          Column({ space: 6 }) {
            Text('Bika')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('HarmonyOS 原生客户端')
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
            Text('版本 ' + CHANGELOG_ENTRIES[0].version)
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('文档')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('更新日志')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('查看版本功能变化')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
          .onClick(() => {
            this.openChangelog();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('隐私政策')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('账户、资料、文件与网络说明')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
          .onClick(() => {
            this.openPrivacyPolicy();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })

          Text('开源')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.link'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('GitHub 项目主页')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('github.com/LoMoCatAp/Bika-HarmonyOS')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
          .onClick(() => {
            this.openExternalLink('https://github.com/LoMoCatAp/Bika-HarmonyOS');
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.aboutScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}
