import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, DividerShowType, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import { ComicViewModel, BikaComicSummary } from '../models/Comic';
import { ComicCard } from '../components/ComicCard';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_BG,
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_INPUT_BG,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_TEXT_SECONDARY,
  COLOR_WHITE,
  SORT_OPTIONS,
  SortOption
} from '../common/Constants';

/**
 * 搜索页（关键词推荐 + 高级搜索 + 排序）
 */
@Entry
@Component
struct SearchPage {
  @State keyword: string = '';
  @State keywords: string[] = [];
  @State results: ComicViewModel[] = [];
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State hasSearched: boolean = false;
  @State currentPage: number = 1;
  @State hasMore: boolean = false;
  @State currentSort: string = 'dd';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  private apiService: ApiService = ApiService.getInstance();
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.loadKeywords();
  }

  private async loadKeywords(): Promise<void> {
    try {
      this.keywords = await this.apiService.getKeywords();
    } catch (err) {
      console.warn('[SearchPage] keywords failed: ' + JSON.stringify(err));
    }
  }

  private async doSearch(reset: boolean): Promise<void> {
    if (this.keyword.trim().length === 0) {
      return;
    }
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMsg = '';
    if (reset) {
      this.currentPage = 1;
    }
    try {
      let result = await this.apiService.advancedSearch(this.keyword.trim(), this.currentSort, this.currentPage);
      let vms = result.comics.map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      this.results = reset ? vms : this.results.concat(vms);
      this.hasMore = this.currentPage < result.pages;
      this.hasSearched = true;
    } catch (err) {
      this.errorMsg = (err as Error).message || '搜索失败';
      console.error('[SearchPage] search failed: ' + this.errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  private immersiveTitleBar(title: string): HdsNavigationTitleBarOptions {
    return {
      content: {
        title: { mainTitle: title },
        divider: { showType: DividerShowType.OFF }
      },
      enableComponentSafeArea: true,
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: { enableScrollEffect: false },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('app.color.bika_bg')
          },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.bika_text_title') },
            backIconStyle: { iconColor: $r('app.color.bika_text_title') }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      }
    };
  }

  build() {
    HdsNavigation(this.stack) {
      Column() {
        // 搜索框
        Row({ space: 10 }) {
          TextInput({ placeholder: '搜索漫画 / 作者 / 标签', text: this.keyword })
            .fontSize(14)
            .backgroundColor(COLOR_INPUT_BG)
            .borderRadius(20)
            .height(40)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.keyword = value;
            })
            .onSubmit(() => this.doSearch(true))
          Button('搜索', { type: ButtonType.Normal })
            .fontSize(14)
            .fontColor(COLOR_WHITE)
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(20)
            .height(40)
            .padding({ left: 18, right: 18 })
            .onClick(() => this.doSearch(true))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })

        if (!this.hasSearched) {
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
                    this.keyword = kw;
                    this.doSearch(true);
                  })
              }, (kw: string) => kw)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 8 })
        } else {
          // 排序 chips
          Row() {
            ForEach(SORT_OPTIONS, (item: SortOption) => {
              Text(item.label)
                .fontSize(13)
                .fontColor(this.currentSort === item.key ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.currentSort === item.key ? COLOR_PRIMARY : COLOR_CARD)
                .borderRadius(15)
                .margin({ right: 8 })
                .onClick(() => {
                  if (this.currentSort !== item.key) {
                    this.currentSort = item.key;
                    this.doSearch(true);
                  }
                })
            }, (item: SortOption) => item.key)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 40 })
          } else if (this.results.length === 0 && !this.isLoading) {
            Text('没有找到相关漫画')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 40 })
          } else {
            Scroll() {
              Grid() {
                ForEach(this.results, (comic: ComicViewModel) => {
                  GridItem() {
                    ComicCard({ comic: comic })
                  }
                  .onClick(() => {
                    router.pushUrl({
                      url: 'pages/ComicDetailPage',
                      params: { comicId: comic.id, comicTitle: comic.title }
                    });
                  })
                }, (comic: ComicViewModel) => comic.id + '_' + this.currentSort)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(12)
              .padding({ left: 12, right: 12, top: 8, bottom: 24 })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .onReachEnd(() => {
              if (this.hasMore && !this.isLoading) {
                this.currentPage++;
                this.doSearch(false);
              }
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.immersiveTitleBar('搜索'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .width('100%')
    .height('100%')
  }
}