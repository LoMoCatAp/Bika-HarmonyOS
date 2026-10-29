import { GlassNavigationHeader } from '../components/GlassNavigationHeader';
import { navigationBlurTitleBar } from '../common/NavigationBlur';
import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { ChannelControlCapsule } from '../components/ChannelControlCapsule';
import { ApiService } from '../network/ApiService';
import { ComicViewModel, BikaComicSummary, isBlockedComic } from '../models/Comic';
import { ComicCard } from '../components/ComicCard';
import { publishContinuationRoute, ROUTE_SEARCH_RESULT } from '../common/ContinuationState';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_BG,
  COLOR_TEXT_HINT,
  COLOR_TEXT_SECONDARY,
  SORT_OPTIONS,
  SortOption,
  adaptiveListColumns
} from '../common/Constants';

/**
 * 搜索结果页（独立页面：排序 chips + 结果网格 + 分页加载）
 */
interface SearchResultParams {
  keyword: string;
}

@Entry
@Component
struct SearchResultPage {
  @State keyword: string = '';
  @State results: ComicViewModel[] = [];
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State currentPage: number = 1;
  @State hasMore: boolean = false;
  @State currentSort: string = 'dd';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  private resultsScroller: Scroller = new Scroller();
  private searchRequestId: number = 0;
  private apiService: ApiService = ApiService.getInstance();
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    let params = router.getParams() as SearchResultParams;
    if (params && params.keyword) {
      this.keyword = params.keyword;
    }
    this.doSearch(true);
  }

  /** 应用接续：本页可见即发布「当前页面」（含关键词） */
  onPageShow(): void {
    publishContinuationRoute(ROUTE_SEARCH_RESULT, { keyword: this.keyword });
  }

  aboutToDisappear(): void {
    // 忽略已离开页面后才返回的请求。
    this.searchRequestId++;
  }

  private async doSearch(reset: boolean): Promise<void> {
    if (this.isLoading && !reset) {
      return;
    }
    const requestId = ++this.searchRequestId;
    this.isLoading = true;
    this.errorMsg = '';
    if (reset) {
      this.currentPage = 1;
      this.results = [];
      this.hasMore = false;
    }
    const page = this.currentPage;
    try {
      const result = await this.apiService.advancedSearch(this.keyword, this.currentSort, page);
      if (requestId !== this.searchRequestId) {
        return;
      }
      const vms = result.comics
        .filter((c: BikaComicSummary) => !isBlockedComic(c.tags))
        .map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      this.results = reset ? vms : this.results.concat(vms);
      this.hasMore = page < result.pages;
    } catch (err) {
      if (requestId === this.searchRequestId) {
        this.errorMsg = (err as Error).message || '搜索失败';
        console.error('[SearchResultPage] search failed: ' + this.errorMsg);
      }
    } finally {
      if (requestId === this.searchRequestId) {
        this.isLoading = false;
      }
    }
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  sortControls() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(SORT_OPTIONS, (item: SortOption): void => {
          ChannelControlCapsule({
            label: item.label,
            selected: this.currentSort === item.key,
            onActivate: (): void => {
              if (this.currentSort !== item.key) {
                this.currentSort = item.key;
                this.resultsScroller.scrollTo({ xOffset: 0, yOffset: 0 });
                this.doSearch(true);
              }
            }
          })
        }, (item: SortOption): string => item.key)
      }
      .height(36)
    }
    .width('100%').height(52)
    .align(Alignment.Start)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .position({ x: 0, y: this.topSafeHeight + 56 })
    .zIndex(2)
  }

  @Builder
  resultContent() {
    Scroll(this.resultsScroller) {
      Column({ space: 12 }) {
        if (this.results.length === 0) {
          Column({ space: 12 }) {
            if (this.isLoading) {
              LoadingProgress().width(32).height(32).color(COLOR_PRIMARY)
            } else {
              Text(this.errorMsg.length > 0 ? this.errorMsg : '没有找到相关漫画')
                .fontSize(14)
                .fontColor(COLOR_TEXT_HINT)
                .textAlign(TextAlign.Center)
              if (this.errorMsg.length > 0) {
                Button('重新加载', { type: ButtonType.Capsule })
                  .fontSize(13)
                  .fontColor(COLOR_PRIMARY)
                  .backgroundColor(COLOR_PRIMARY_TINT)
                  .height(36)
                  .padding({ left: 16, right: 16 })
                  .onClick((): void => { this.doSearch(true); })
              }
            }
          }
          .width('100%')
          .padding({ top: 56, bottom: 56 })
        } else {
          Grid() {
            ForEach(this.results, (comic: ComicViewModel): void => {
              GridItem() { ComicCard({ comic: comic }) }
                .onClick((): void => {
                  router.pushUrl({
                    url: 'pages/ComicDetailPage',
                    params: { comicId: comic.id, comicTitle: comic.title }
                  });
                })
            }, (comic: ComicViewModel): string => comic.id + '_' + this.currentSort)
          }
          .columnsTemplate(adaptiveListColumns())
          .columnsGap(10)
          .rowsGap(12)
          .enableScrollInteraction(false)
          .clip(false)
          .cachedCount(3, true)
          if (this.isLoading) {
            Row({ space: 6 }) {
              LoadingProgress().width(16).height(16).color(COLOR_PRIMARY)
              Text('加载中…').fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Button('加载失败，点击重试', { type: ButtonType.Capsule })
              .fontSize(13)
              .fontColor(COLOR_PRIMARY)
              .backgroundColor(COLOR_PRIMARY_TINT)
              .height(36)
              .padding({ left: 16, right: 16 })
              .onClick((): void => { this.doSearch(false); })
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topSafeHeight + 56 + 60,
        bottom: this.bottomSafeHeight + 24 })
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .clip(false)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onReachEnd((): void => {
      if (this.hasMore && !this.isLoading && this.errorMsg.length === 0) {
        this.currentPage++;
        this.doSearch(false);
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation(this.stack) {
        this.resultContent()
      }
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.MINI)
      .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
      .hideTitleBar(false)
      .hideBackButton(true)
      .bindToScrollable([this.resultsScroller])
      .backgroundColor(COLOR_BG)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%').height('100%')
      GlassNavigationHeader({ title: '搜索结果', onBack: (): void => router.back() })
        .position({ x: 0, y: this.topSafeHeight })
        .zIndex(3)
      // 控件独立位于模糊层上方，文字与输入内容不会被标题栏滤镜处理。
      this.sortControls()
    }
    .backgroundColor(COLOR_BG)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%').height('100%')
  }
}
