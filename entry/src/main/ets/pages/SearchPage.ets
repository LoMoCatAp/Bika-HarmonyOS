import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import { CacheManager } from '../common/CacheManager';
import {
  COLOR_PRIMARY,
  COLOR_BG,
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_INPUT_BG,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_WHITE
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
  private apiService: ApiService = ApiService.getInstance();
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.loadKeywords();
    this.loadSearchHistory();
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

  private immersiveTitleBar(title: string): HdsNavigationTitleBarOptions {
    return {
      content: { title: { mainTitle: title } },
      enableComponentSafeArea: true,
      avoidLayoutSafeArea: true,
      style: {
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
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
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
            .onSubmit(() => this.goSearch(this.keyword))
          Button('搜索', { type: ButtonType.Normal })
            .fontSize(14)
            .fontColor(COLOR_WHITE)
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(20)
            .height(40)
            .padding({ left: 18, right: 18 })
            .onClick(() => this.goSearch(this.keyword))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })

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