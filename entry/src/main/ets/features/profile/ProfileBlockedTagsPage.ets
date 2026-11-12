import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_BG, COLOR_TEXT_HINT, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_DIVIDER } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileBlockedTagsPage {
  blockedTagsScroller: Scroller = new Scroller();
  @Link blockedTags: string[];
  toggleBlockedTag: (tag: string) => void = (tag: string): void => {};
  @Link blockedLoading: boolean;
  @Link keywordTags: string[];
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
      Scroll(this.blockedTagsScroller) {
          Column({ space: 12 }) {
            Column() {
              Text('已屏蔽')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              if (this.blockedTags.length === 0) {
                Text('暂无屏蔽标签')
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_HINT)
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })
              } else {
                Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                  ForEach(this.blockedTags, (tag: string) => {
                    Text(tag)
                      .fontSize(13)
                      .fontColor(COLOR_PRIMARY)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(COLOR_PRIMARY_TINT)
                      .border({ width: 1, color: COLOR_PRIMARY, radius: 15 })
                      .margin({ left: 16, bottom: 8 })
                      .onClick(() => this.toggleBlockedTag(tag))
                  }, (tag: string) => tag)
                }
                .width('100%')
                .padding({ bottom: 8 })
              }
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

            Column() {
              Text('可选标签')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              if (this.blockedLoading && this.keywordTags.length === 0) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color(COLOR_PRIMARY)
                  Text('加载标签中…')
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .width('100%')
                .padding({ left: 16, bottom: 12 })
              } else {
                Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                  ForEach(this.keywordTags, (tag: string) => {
                    Text(tag)
                      .fontSize(13)
                      .fontColor(this.blockedTags.indexOf(tag) >= 0 ? COLOR_PRIMARY : COLOR_TEXT_TITLE)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(this.blockedTags.indexOf(tag) >= 0 ? COLOR_PRIMARY_TINT : COLOR_CARD)
                      .border({
                        width: 1,
                        color: this.blockedTags.indexOf(tag) >= 0 ? COLOR_PRIMARY : COLOR_DIVIDER,
                        radius: 15
                      })
                      .margin({ left: 16, bottom: 8 })
                      .onClick(() => this.toggleBlockedTag(tag))
                  }, (tag: string) => tag)
                }
                .width('100%')
                .padding({ bottom: 8 })
              }
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

            Text('屏蔽后，频道列表与搜索结果将不再显示含该标签的漫画。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16, top: 4 })
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
    .bindToScrollable([this.blockedTagsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}
