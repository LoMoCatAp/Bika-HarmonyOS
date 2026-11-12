import { router } from '@kit.ArkUI';
import { ComicViewModel, buildImageUrl, BikaNotification, BikaComment } from '../../models/Comic';
import { NetImage } from '../../components/NetImage';
import { ComicCard } from '../../components/ComicCard';
import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { HistoryItem } from '../../common/CacheManager';
import { COLOR_PRIMARY, COLOR_BG, COLOR_TEXT_HINT, COLOR_TEXT_DISABLED, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_PLACEHOLDER, COLOR_DIVIDER, adaptiveListColumns } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { DownloadListView } from '../downloads/DownloadListView';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileFavouritesPage {
  favouritesScroller: Scroller = new Scroller();
  @Link favLoading: boolean;
  @Link favComics: ComicViewModel[];
  @Link favSort: string;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  favouritesControlsHeight: number = 52;
  @Link favHasMore: boolean;
  loadFavourites: (reset: boolean) => Promise<void> = async (reset: boolean): Promise<void> => {};
  closeSubpage: () => void = (): void => {};

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      Scroll(this.favouritesScroller) {
        Column() {

          if (this.favLoading && this.favComics.length === 0) {
            LoadingProgress()
              .width(28).height(28).color(COLOR_PRIMARY)
              .margin({ top: 24, bottom: 16 })
          }
          Grid() {
            ForEach(this.favComics, (comic: ComicViewModel) => {
              GridItem() {
                ComicCard({ comic: comic })
              }
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/ComicDetailPage',
                  params: { comicId: comic.id, comicTitle: comic.title }
                });
              })
            }, (comic: ComicViewModel) => comic.id + '_' + this.favSort)
          }
          .columnsTemplate(adaptiveListColumns())
          .enableScrollInteraction(false)
          .clip(false)
          .cachedCount(3, true)
          .columnsGap(10)
          .rowsGap(12)
          .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafeHeight + 76 })
        }
        .width('100%')
        .padding({ top: this.topSafeHeight + 56 + this.favouritesControlsHeight })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onReachEnd(() => {
        if (this.favHasMore && !this.favLoading) {
          this.loadFavourites(false);
        }
      })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.favouritesScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileHistoryPage {
  historyScroller: Scroller = new Scroller();
  @Link historyItems: HistoryItem[];
  confirmDeleteHistory: (item: HistoryItem) => void = (item: HistoryItem): void => {};
  confirmClearHistory: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  closeSubpage: () => void = (): void => {};

  private historyTimeLabel(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    let d = new Date(timestamp);
    let now = new Date();
    let pad = (n: number): string => n < 10 ? '0' + n : String(n);
    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()) {
      return '今天 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
    return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      List({ space: 0, scroller: this.historyScroller }) {
        if (this.historyItems.length === 0) {
          ListItem() {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(36)
              .fontColor([COLOR_TEXT_DISABLED])
            Text('暂无浏览记录')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
          }
        } else {
          ListItemGroup() {
            ForEach(this.historyItems, (item: HistoryItem, index: number) => {
              ListItem() {
                Row() {
                  if (item.coverUrl.length > 0) {
                    NetImage({
                      src: item.coverUrl,
                      fit: ImageFit.Cover,
                      radius: 8,
                      fillParent: true
                    })
                      .width(48)
                      .height(64)
                  } else {
                    Image($r('app.media.ic_default_avatar'))
                      .width(48)
                      .height(64)
                      .borderRadius(8)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(COLOR_PLACEHOLDER)
                  }
                  Column({ space: 4 }) {
                    Text(item.title)
                      .fontSize(15)
                      .fontColor(COLOR_TEXT_TITLE)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('看到第 ' + item.order + ' 话 · ' + this.historyTimeLabel(item.timestamp))
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_HINT)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(18)
                    .fontColor([COLOR_TEXT_HINT])
                    .padding(6)
                    .onClick(() => {
                      this.confirmDeleteHistory(item);
                    })
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([COLOR_TEXT_DISABLED])
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/ComicDetailPage',
                    params: { comicId: item.comicId, comicTitle: item.title }
                  });
                })
              }
              if (index < this.historyItems.length - 1) {
                ListItem() {
                  Divider().height(1).color(COLOR_DIVIDER).margin({ left: 76 })
                }
              }
            }, (item: HistoryItem) => item.comicId)

            ListItem() {
              Row() {
                Text('清空全部历史')
                  .fontSize(14)
                  .fontColor('#C62828')
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.confirmClearHistory();
              })
            }
          }
          .width('100%')
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%').height('100%')
      .contentStartOffset(this.topSafeHeight + this.subpageContentTop)
      .contentEndOffset(this.bottomSafeHeight + 40)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .cachedCount(3, true)
      .clip(false)
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.historyScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileDownloadsPage {
  downloadsScroller: Scroller = new Scroller();
  closeSubpage: () => void = (): void => {};

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      DownloadListView({ scroller: this.downloadsScroller })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.downloadsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileNotificationsPage {
  notificationsScroller: Scroller = new Scroller();
  @Link notifications: BikaNotification[];
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  closeSubpage: () => void = (): void => {};

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      List({ space: 0, scroller: this.notificationsScroller }) {
        if (this.notifications.length === 0) {
          ListItem() {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.bell'))
              .fontSize(36)
              .fontColor([COLOR_TEXT_DISABLED])
            Text('暂无通知')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
          }
        } else {
        ListItemGroup() {
          ForEach(this.notifications, (n: BikaNotification, index: number) => {
            ListItem() {
              Row() {
                if (n._comic && n._comic.thumb && n._comic.thumb.path) {
                  NetImage({
                    src: buildImageUrl(n._comic.thumb),
                    fit: ImageFit.Cover,
                    radius: 10,
                    fillParent: true
                  })
                    .width(48)
                    .height(64)
                }
                Column({ space: 4 }) {
                  Text(n.content)
                    .fontSize(14)
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(n.created_at ? n.created_at.substring(0, 10) : '')
                    .fontSize(10)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            if (index < this.notifications.length - 1) {
              ListItem() {
                Divider().height(1).color(COLOR_DIVIDER).margin({ left: 76 })
              }
            }
          }, (n: BikaNotification) => n._id)
          }
          .width('100%')
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%').height('100%')
      .contentStartOffset(this.topSafeHeight + this.subpageContentTop)
      .contentEndOffset(this.bottomSafeHeight + 40)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .cachedCount(3, true)
      .clip(false)
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.notificationsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileCommentsPage {
  commentsScroller: Scroller = new Scroller();
  @Link myComments: BikaComment[];
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  closeSubpage: () => void = (): void => {};

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      List({ space: 0, scroller: this.commentsScroller }) {
        if (this.myComments.length === 0) {
          ListItem() {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(36)
              .fontColor([COLOR_TEXT_DISABLED])
            Text('暂无评论')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
          }
        } else {
        ListItemGroup() {
          ForEach(this.myComments, (comment: BikaComment, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(comment.content)
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_TITLE)
                Row() {
                  Text(comment.created_at ? comment.created_at.substring(0, 10) : '')
                    .fontSize(10)
                    .fontColor(COLOR_TEXT_HINT)
                  Blank()
                  Text('赞 ' + (comment.likesCount ?? 0))
                    .fontSize(10)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            if (index < this.myComments.length - 1) {
              ListItem() {
                Divider().height(1).color(COLOR_DIVIDER).margin({ left: 16 })
              }
            }
          }, (comment: BikaComment) => comment._id)
          }
          .width('100%')
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%').height('100%')
      .contentStartOffset(this.topSafeHeight + this.subpageContentTop)
      .contentEndOffset(this.bottomSafeHeight + 40)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .cachedCount(3, true)
      .clip(false)
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.commentsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}
