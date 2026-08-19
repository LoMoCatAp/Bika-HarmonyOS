import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, DividerShowType, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import { ComicViewModel, BikaComicSummary, isBlockedComic } from '../models/Comic';
import { ComicCard } from '../components/ComicCard';
import {
  COLOR_PRIMARY,
  COLOR_BG,
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_TEXT_SECONDARY,
  COLOR_WHITE,
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
  private apiService: ApiService = ApiService.getInstance();
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    let params = router.getParams() as SearchResultParams;
    if (params && params.keyword) {
      this.keyword = params.keyword;
    }
    this.doSearch(true);
  }

  private async doSearch(reset: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMsg = '';
    if (reset) {
      this.currentPage = 1;
    }
    try {
      let result = await this.apiService.advancedSearch(this.keyword, this.currentSort, this.currentPage);
      let vms = result.comics
        .filter((c: BikaComicSummary) => !isBlockedComic(c.tags))
        .map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      this.results = reset ? vms : this.results.concat(vms);
      this.hasMore = this.currentPage < result.pages;
    } catch (err) {
      this.errorMsg = (err as Error).message || '搜索失败';
      console.error('[SearchResultPage] search failed: ' + this.errorMsg);
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
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

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
            .columnsTemplate(adaptiveListColumns())
            .columnsGap(10)
            .rowsGap(12)
            .padding({ left: 12, right: 12, top: 8, bottom: 24 })
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
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
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.immersiveTitleBar('搜索结果'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .width('100%')
    .height('100%')
  }
}
