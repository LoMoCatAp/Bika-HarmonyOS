import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { ImageLoader } from '../../common/ImageLoader';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_HINT, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_DIVIDER } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileStoragePage {
  storageScroller: Scroller = new Scroller();
  @Link storageRefreshing: boolean;
  @Link downloadSizeBytes: number;
  confirmClearAllDownloads: () => void = (): void => {};
  @Link cacheSizeBytes: number;
  confirmClearImageCache: () => void = (): void => {};
  refreshStorage: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  closeSubpage: () => void = (): void => {};

  private sizeLabelForStorage(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes >= 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    if (bytes >= 1024) {
      return (bytes / 1024).toFixed(0) + ' KB';
    }
    return bytes + ' B';
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      Scroll(this.storageScroller) {
          Column({ space: 12 }) {
            Column() {
              Text('下载')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              Row() {
                Column({ space: 3 }) {
                  Text('已下载漫画占用')
                    .fontSize(15)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text(this.storageRefreshing ? '计算中…' : this.sizeLabelForStorage(this.downloadSizeBytes))
                    .fontSize(13)
                    .fontColor(COLOR_PRIMARY)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('清空')
                  .fontSize(14)
                  .fontColor('#C62828')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(COLOR_PRIMARY_TINT)
                  .borderRadius(14)
                  .onClick(() => this.confirmClearAllDownloads())
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 16 })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

            Column() {
              Text('缓存')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              Row() {
                Column({ space: 3 }) {
                  Text('图片与页面缓存')
                    .fontSize(15)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text('内存 ' + ImageLoader.cachedCount() + ' 张 · 磁盘 ' +
                    this.sizeLabelForStorage(this.cacheSizeBytes))
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('清理')
                  .fontSize(14)
                  .fontColor(COLOR_PRIMARY)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(COLOR_PRIMARY_TINT)
                  .borderRadius(14)
                  .onClick(() => {
                    this.confirmClearImageCache();
                    setTimeout(() => this.refreshStorage(), 600);
                  })
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 16 })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

            Row() {
              Text('刷新统计')
                .fontSize(15)
                .fontColor(COLOR_PRIMARY)
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => this.refreshStorage())
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
    .bindToScrollable([this.storageScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
    .onShown(() => {
      this.refreshStorage();
    })
  }
}
