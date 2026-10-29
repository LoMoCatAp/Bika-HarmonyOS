import { GlassNavigationHeader } from '../components/GlassNavigationHeader';
import { navigationBlurTitleBar } from '../common/NavigationBlur';
import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { DetailGlassCapsule } from '../components/DetailGlassCapsule';
import { ApiService } from '../network/ApiService';
import { CacheManager } from '../common/CacheManager';
import { publishContinuationRoute, ROUTE_SEARCH } from '../common/ContinuationState';
import {
  COLOR_PRIMARY,
  COLOR_BG,
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_TEXT_SECONDARY
} from '../common/Constants';

/**
 * 搜索页（关键词推荐 + 高级搜索 + 排序）
 */
@Entry
@Component
struct SearchPage {
  @State keyword: string = '';
  @State keywords: string[] = [];
  @State searchHistory: string[] = [];
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('bika_animations') animationsOn: boolean = true;
  private searchScroller: Scroller = new Scroller();
  private apiService: ApiService = ApiService.getInstance();
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.loadKeywords();
    this.loadSearchHistory();
  }

  /** 应用接续：本页可见即发布「当前页面」 */
  onPageShow(): void {
    publishContinuationRoute(ROUTE_SEARCH, {});
  }

  private loadSearchHistory(): void {
    CacheManager.getInstance().then(cache => {
      this.searchHistory = cache.loadSearchHistory();
    });
  }

  private saveSearchKeyword(): void {
    let kw = this.keyword.trim();
    if (kw.length === 0) {
      return;
    }
    CacheManager.getInstance().then(cache => {
      cache.saveSearchHistory(kw);
      this.searchHistory = cache.loadSearchHistory();
    });
  }

  private clearSearchHistory(): void {
    CacheManager.getInstance().then(cache => {
      cache.clearSearchHistory();
      this.searchHistory = [];
    });
  }

  private async loadKeywords(): Promise<void> {
    try {
      this.keywords = await this.apiService.getKeywords();
    } catch (err) {
      console.warn('[SearchPage] keywords failed: ' + JSON.stringify(err));
    }
  }

  /** 执行搜索：保存历史并跳转独立的搜索结果页 */
  private goSearch(kw: string): void {
    let keyword = kw.trim();
    if (keyword.length === 0) {
      return;
    }
    this.keyword = keyword;
    CacheManager.getInstance().then(cache => {
      cache.saveSearchHistory(keyword);
      this.searchHistory = cache.loadSearchHistory();
    });
    router.pushUrl({
      url: 'pages/SearchResultPage',
      params: { keyword: keyword }
    });
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  searchInputContent() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(19)
        .fontColor([COLOR_TEXT_SECONDARY])
      TextInput({ placeholder: '搜索漫画 / 作者 / 标签', text: this.keyword })
        .fontSize(14)
        .fontColor(COLOR_TEXT_TITLE)
        .placeholderColor(COLOR_TEXT_HINT)
        .caretColor(COLOR_PRIMARY)
        .backgroundColor(Color.Transparent)
        .height(44)
        .layoutWeight(1)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string): void => { this.keyword = value; })
        .onSubmit((): void => this.goSearch(this.keyword))
    }
    .width('100%').height(44)
    .padding({ left: 14, right: 4 })
  }

  @Builder
  searchSubmitContent() {
    Button('搜索', { type: ButtonType.Capsule })
      .width('100%').height(44)
      .fontSize(14)
      .fontColor(COLOR_PRIMARY)
      .backgroundColor(Color.Transparent)
      .enabled(this.keyword.trim().length > 0)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.96 : 1 })
      .onClick((): void => this.goSearch(this.keyword))
  }

  @Builder
  searchControls() {
    Row({ space: 10 }) {
      DetailGlassCapsule({ content: (): void => { this.searchInputContent(); } }).layoutWeight(1)
      DetailGlassCapsule({ capsuleWidth: 68, content: (): void => { this.searchSubmitContent(); } })
    }
    .width('100%').height(60)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .position({ x: 0, y: this.topSafeHeight + 56 })
    .zIndex(2)
  }

  @Builder
  searchSuggestions() {
    Scroll(this.searchScroller) {
      Column() {
        // 搜索历史
        if (this.searchHistory.length > 0) {
            Column() {
              Row() {
                Text('最近搜索')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_HINT)
                  .layoutWeight(1)
                Text('清空')
                  .fontSize(13)
                  .fontColor(COLOR_PRIMARY)
                  .onClick(() => this.clearSearchHistory())
              }
              .width('100%')
              .margin({ bottom: 10 })
              Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                ForEach(this.searchHistory, (kw: string) => {
                  Text(kw)
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_TITLE)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(COLOR_CARD)
                    .border({ width: 1, color: COLOR_DIVIDER, radius: 15 })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.goSearch(kw);
                    })
                }, (kw: string) => kw)
              }
              .width('100%')
            }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 8 })
        }

        // 关键词推荐
        Column() {
            Text('热门搜索')
              .fontSize(13)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .margin({ bottom: 10 })
            Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
              ForEach(this.keywords, (kw: string) => {
                Text(kw)
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_TITLE)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(COLOR_CARD)
                  .border({ width: 1, color: COLOR_DIVIDER, radius: 15 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.goSearch(kw);
                  })
              }, (kw: string) => kw)
            }
            .width('100%')
          }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 8 })
      }
      .width('100%')
      .padding({ top: this.topSafeHeight + 56 + 68, bottom: this.bottomSafeHeight + 24 })
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .clip(false)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation(this.stack) {
        this.searchSuggestions()
      }
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.MINI)
      .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
      .hideTitleBar(false)
      .hideBackButton(true)
      .bindToScrollable([this.searchScroller])
      .backgroundColor(COLOR_BG)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%').height('100%')
      GlassNavigationHeader({ title: '搜索', onBack: (): void => router.back() })
        .position({ x: 0, y: this.topSafeHeight })
        .zIndex(3)
      // 控件独立位于模糊层上方，文字与输入内容不会被标题栏滤镜处理。
      this.searchControls()
    }
    .backgroundColor(COLOR_BG)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%').height('100%')
  }
}
