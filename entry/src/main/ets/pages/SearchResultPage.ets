import { GlassNavigationHeader } from '../components/GlassNavigationHeader';
import { navigationBlurTitleBar } from '../common/NavigationBlur';
import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { ChannelControlCapsule } from '../components/ChannelControlCapsule';
import { ApiService } from '../network/ApiService';
import { ComicViewModel, BikaComicSummary, ComicSearchKind, normalizeComicSearchKind, isBlockedComic } from '../models/Comic';
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
  searchKind?: string;
}

@Entry
@Component
struct SearchResultPage {
  @State keyword: string = '';
  @State searchKind: ComicSearchKind = 'keyword';
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
    if (params && typeof params.keyword === 'string') {
      this.keyword = params.keyword.trim();
    }
    this.searchKind = normalizeComicSearchKind(params?.searchKind);
    this.doSearch(true);
  }

  /** 应用接续：本页可见即发布「当前页面」（含关键词） */
  onPageShow(): void {
    publishContinuationRoute(ROUTE_SEARCH_RESULT, { keyword: this.keyword, searchKind: this.searchKind });
  }

  aboutToDisappear(): void {
    // 忽略已离开页面后才返回的请求。
    this.searchRequestId++;
  }

  private async doSearch(reset: boolean): Promise<void> {
    if (!reset && (this.isLoading || !this.hasMore)) {
      return;
    }
    if (this.keyword.trim().length === 0) {
      this.searchRequestId++;
      this.isLoading = false;
      this.hasMore = false;
      this.results = [];
      this.errorMsg = '请输入搜索关键词';
      return;
    }
    const requestId = ++this.searchRequestId;
    this.isLoading = true;
    this.errorMsg = '';
    if (reset) {
      this.currentPage = 0;
      this.results = [];
      this.hasMore = false;
    }
    const page = reset ? 1 : this.currentPage + 1;
    const keyword = this.keyword;
    const sort = this.currentSort;
    const kind = this.searchKind;
    try {
      const result = await this.apiService.searchComics(keyword, sort, page, kind);
      if (requestId !== this.searchRequestId) {
        return;
      }
      const ids = new Set<string>(reset ? [] : this.results.map((comic: ComicViewModel): string => comic.id));
      const vms = result.comics
        .filter((comic: BikaComicSummary): boolean => {
          if (!comic._id || ids.has(comic._id) || isBlockedComic(comic.tags)) {
            return false;
          }
          ids.add(comic._id);
          return true;
        })
        .map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      this.results = reset ? vms : this.results.concat(vms);
      this.currentPage = page;
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

  private searchTitle(): string {
    const label = this.searchKind === 'author' ? '作者' : this.searchKind === 'tag' ? '标签'
      : this.searchKind === 'category' ? '分类' : '搜索';
    return this.keyword.length > 0 ? label + '：' + this.keyword : '搜索结果';
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
              Text(this.errorMsg.length > 0 ? this.errorMsg : this.hasMore ? '当前页暂无可展示的漫画' : '没有找到相关漫画')
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
                  .onClick((): void => { this.doSearch(this.currentPage === 0); })
              } else if (this.hasMore) {
                Button('继续加载', { type: ButtonType.Capsule })
                  .fontSize(13).fontColor(COLOR_PRIMARY).backgroundColor(COLOR_PRIMARY_TINT)
                  .height(36).padding({ left: 16, right: 16 })
                  .onClick((): void => { this.doSearch(false); })
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
          } else if (this.hasMore) {
            Button('加载更多', { type: ButtonType.Capsule })
              .fontSize(13).fontColor(COLOR_PRIMARY).backgroundColor(COLOR_PRIMARY_TINT)
              .height(36).padding({ left: 16, right: 16 })
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
      GlassNavigationHeader({ title: this.searchTitle(), onBack: (): void => router.back() })
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
