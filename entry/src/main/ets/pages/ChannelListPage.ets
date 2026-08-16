import { router } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, DividerShowType, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import { ComicViewModel, BikaComicSummary, BikaKnightUser, buildImageUrl } from '../models/Comic';
import { ComicCard } from '../components/ComicCard';
import { NetImage } from '../components/NetImage';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_BG,
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_GLASS_TOP,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_TEXT_SECONDARY,
  COLOR_TEXT_DISABLED,
  COLOR_WHITE,
  SORT_OPTIONS,
  SortOption,
  ChannelKind
} from '../common/Constants';

/**
 * 频道漫画列表页（
 * 沉浸毛玻璃返回栏 + 顶部筛选 + 内容网格/骑士榜）
 */

interface ChannelListParams {
  label: string;
  kind: ChannelKind;
}

const LEADERBOARD_TABS: string[] = ['H24', 'D7', 'D30', 'knights'];
const LEADERBOARD_TAB_LABELS: string[] = ['日榜 (24H)', '周榜 (7D)', '月榜 (30D)', '骑士榜'];

@Entry
@Component
struct ChannelListPage {
  @State label: string = '';
  @State kind: ChannelKind = 'topic';
  @State comics: ComicViewModel[] = [];
  @State knights: BikaKnightUser[] = [];
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State currentPage: number = 1;
  @State hasMore: boolean = false;
  @State currentSort: string = 'dd';
  @State leaderboardTab: number = 0;
  /** 筛选（主题/排除主题/状态/话数/页数五组，客户端过滤） */
  @State filterTopics: string[] = [];
  @State filterExcludeTopics: string[] = [];
  @State filterStatus: string = '全部';
  @State filterEps: string = '全部';
  @State filterPages: string = '全部';
  @State showFilter: boolean = false;
  /** 筛选子面板：'' | 'topics' | 'excludeTopics' */
  @State filterSubPanel: string = '';
  private readonly TOPIC_OPTIONS: string[] = [
    '全彩', '長篇', '同人', '短篇', '圓神領域', '碧藍幻想', 'CG雜圖', '英語 ENG', '生肉',
    '純愛', '百合花園', '耽美花園', '偽娘哲學', '後宮閃光', '扶他樂園', '單行本',
    '姐姐系', '妹妹系', 'SM', '性轉換', '足の恋', '人妻', 'NTR', '強暴', '非人類',
    '艦隊收藏', 'Love Live', 'SAO 刀劍神域', 'Fate', '東方', 'WEBTOON', '禁書目錄',
    '歐美', 'Cosplay', '重口地帶'
  ];
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  private apiService: ApiService = ApiService.getInstance();
  private listScroller: Scroller = new Scroller();
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    let params = router.getParams() as ChannelListParams;
    if (params) {
      this.label = params.label || '';
      this.kind = params.kind || 'topic';
    }
    this.load(true);
  }

  private isFixedChannel(): boolean {
    return this.kind === 'leaderboard' || this.kind === 'random';
  }

  /** 是否有筛选条件 */
  private hasFilter(): boolean {
    return this.filterStatus !== '全部' || this.filterEps !== '全部' || this.filterPages !== '全部' ||
      this.filterTopics.length > 0 || this.filterExcludeTopics.length > 0;
  }

  /** 主题多选切换 */
  private toggleTopic(v: string, exclude: boolean): void {
    let arr = exclude ? this.filterExcludeTopics : this.filterTopics;
    let idx = arr.indexOf(v);
    if (idx >= 0) {
      let next = arr.slice();
      next.splice(idx, 1);
      if (exclude) {
        this.filterExcludeTopics = next;
      } else {
        this.filterTopics = next;
      }
    } else {
      if (exclude) {
        this.filterExcludeTopics = arr.concat(v);
      } else {
        this.filterTopics = arr.concat(v);
      }
    }
    this.load(true);
  }

  /** 客户端过滤 */
  private applyFilters(vms: ComicViewModel[]): ComicViewModel[] {
    return vms.filter((c: ComicViewModel) => {
      // 主题：选中任一命中（any）
      if (this.filterTopics.length > 0) {
        let hit = false;
        for (let t of this.filterTopics) {
          if (c.categories.indexOf(t) >= 0) {
            hit = true;
            break;
          }
        }
        if (!hit) {
          return false;
        }
      }
      // 排除主题：任一命中即排除
      for (let t of this.filterExcludeTopics) {
        if (c.categories.indexOf(t) >= 0) {
          return false;
        }
      }
      if (this.filterStatus === '连载' && c.finished) {
        return false;
      }
      if (this.filterStatus === '完结' && !c.finished) {
        return false;
      }
      if (this.filterEps === '单话 (1话)' && c.epsCount !== 1) {
        return false;
      }
      if (this.filterEps === '短篇 (2-5话)' && (c.epsCount < 2 || c.epsCount > 5)) {
        return false;
      }
      if (this.filterEps === '中篇 (6-20话)' && (c.epsCount < 6 || c.epsCount > 20)) {
        return false;
      }
      if (this.filterEps === '长篇 (21-100话)' && (c.epsCount < 21 || c.epsCount > 100)) {
        return false;
      }
      if (this.filterEps === '超长篇 (100话以上)' && c.epsCount <= 100) {
        return false;
      }
      if (c.pagesCount > 0) {
        if (this.filterPages === '少页 (<50页)' && c.pagesCount >= 50) {
          return false;
        }
        if (this.filterPages === '中等 (50-200页)' && (c.pagesCount < 50 || c.pagesCount > 200)) {
          return false;
        }
        if (this.filterPages === '多页 (200-500页)' && (c.pagesCount < 201 || c.pagesCount > 500)) {
          return false;
        }
        if (this.filterPages === '超多页 (500页以上)' && c.pagesCount <= 500) {
          return false;
        }
      }
      return true;
    });
  }

  private async load(reset: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMsg = '';
    if (reset) {
      this.currentPage = 1;
      this.hasMore = false;
    }
    try {
      let vms: ComicViewModel[] = [];
      if (this.kind === 'leaderboard' && this.leaderboardTab === 3) {
        this.knights = await this.apiService.getKnightLeaderboard();
      } else if (this.kind === 'leaderboard') {
        vms = (await this.apiService.getLeaderboard(LEADERBOARD_TABS[this.leaderboardTab]))
          .map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      } else if (this.kind === 'random') {
        vms = (await this.apiService.getRandomComics()).map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      } else {
        let topic = this.kind === 'recent' ? '' : this.label;
        let result = await this.apiService.getComics(topic, this.currentSort, this.currentPage);
        vms = result.comics.map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
        this.hasMore = this.currentPage < result.pages;
      }
      if (this.kind === 'recommend' || this.kind === 'recent' || this.kind === 'topic') {
        vms = this.applyFilters(vms);
      }
      if (reset) {
        this.comics = vms;
      } else {
        this.comics = this.comics.concat(vms);
      }
    } catch (err) {
      let msg = (err as Error).message || '加载失败';
      this.errorMsg = msg;
      console.error('[ChannelListPage] load failed: ' + msg);
    } finally {
      this.isLoading = false;
    }
  }

  private onSortChange(sort: string): void {
    if (this.currentSort === sort) {
      return;
    }
    this.currentSort = sort;
    this.load(true);
  }

  private onLeaderboardTab(index: number): void {
    if (this.leaderboardTab === index) {
      return;
    }
    this.leaderboardTab = index;
    this.load(true);
  }

  @Builder
  filterBar() {
    Row() {
      if (this.kind === 'leaderboard') {
        ForEach(LEADERBOARD_TAB_LABELS, (tab: string, index: number) => {
          Text(tab)
            .fontSize(13)
            .fontColor(this.leaderboardTab === index ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.leaderboardTab === index ? COLOR_PRIMARY : COLOR_CARD)
            .borderRadius(15)
            .margin({ right: 8 })
            .onClick(() => this.onLeaderboardTab(index))
        }, (tab: string) => tab)
      } else if (this.kind === 'recommend' || this.kind === 'recent' || this.kind === 'topic') {
        // 筛选按钮（最左）
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(16)
            .fontColor([this.hasFilter() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
          Text(this.hasFilter() ? '已筛选' : '筛选')
            .fontSize(13)
            .fontColor(this.hasFilter() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(COLOR_CARD)
        .border({ width: 1, color: this.hasFilter() ? COLOR_PRIMARY : COLOR_DIVIDER, radius: 15 })
        .margin({ right: 8 })
        .onClick(() => {
          this.showFilter = true;
        })

        ForEach(SORT_OPTIONS, (item: SortOption) => {
          Text(item.label)
            .fontSize(13)
            .fontColor(this.currentSort === item.key ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.currentSort === item.key ? COLOR_PRIMARY : COLOR_CARD)
            .borderRadius(15)
            .margin({ right: 8 })
            .onClick(() => this.onSortChange(item.key))
        }, (item: SortOption) => item.key)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(COLOR_BG)
  }

  @Builder
  contentArea() {
    if (this.errorMsg.length > 0) {
      Column({ space: 12 }) {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor(COLOR_TEXT_HINT)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
        Button('重新加载', { type: ButtonType.Normal })
          .fontSize(13)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_PRIMARY_TINT)
          .borderRadius(18)
          .height(36)
          .onClick(() => this.load(true))
      }
      .width('100%')
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.kind === 'leaderboard' && this.leaderboardTab === 3) {
      if (this.knights.length === 0 && this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(COLOR_PRIMARY)
        }
        .width('100%')
        .padding({ top: 60 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
        List({ space: 0 }) {
          ForEach(this.knights, (knight: BikaKnightUser, index: number) => {
            ListItem() {
              Row() {
                Text(String(index + 1))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(index < 3 ? COLOR_PRIMARY : COLOR_TEXT_HINT)
                  .width(36)
                  .textAlign(TextAlign.Center)

                if (knight.avatar && knight.avatar.path) {
                  NetImage({
                    src: buildImageUrl(knight.avatar),
                    fit: ImageFit.Cover,
                    radius: 22,
                    fillParent: true
                  })
                    .width(44)
                    .height(44)
                } else {
                  Image($r('app.media.ic_default_avatar'))
                    .width(44)
                    .height(44)
                    .borderRadius(22)
                    .objectFit(ImageFit.Cover)
                }

                Column({ space: 2 }) {
                  Text(knight.name || '匿名')
                    .fontSize(15)
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('LV.' + (knight.level ?? 0) + (knight.title ? ' · ' + knight.title : ''))
                    .fontSize(11)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .layoutWeight(1)

                Text('上传 ' + (knight.comicsUploaded ?? 0))
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            }
            if (index < this.knights.length - 1) {
              ListItem() {
                Divider().height(1).color(COLOR_DIVIDER).margin({ left: 96 })
              }
            }
          }, (knight: BikaKnightUser) => knight._id)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLOR_CARD)
        .borderRadius(18)
        .border({ width: 1, color: COLOR_DIVIDER })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
    } else if (this.comics.length === 0 && this.isLoading) {
      Column() {
        LoadingProgress().width(40).height(40).color(COLOR_PRIMARY)
      }
      .width('100%')
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
    } else {
      Scroll(this.listScroller) {
        Grid() {
          ForEach(this.comics, (comic: ComicViewModel) => {
            GridItem() {
              ComicCard({ comic: comic })
            }
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ComicDetailPage',
                params: { comicId: comic.id, comicTitle: comic.title }
              });
            })
          }, (comic: ComicViewModel) => comic.id + '_' + this.currentSort + '_' + this.leaderboardTab)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(12)
        .padding({ left: 12, right: 12, top: 8, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .onReachEnd(() => {
        if (!this.isFixedChannel() && this.hasMore && !this.isLoading) {
          this.currentPage++;
          this.load(false);
        }
      })
    }
  }

  /** HDS 系统沉浸光感标题栏（官方材质） */
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
        this.filterBar()

        Column() {
          this.contentArea()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.immersiveTitleBar(this.label.length > 0 ? this.label : '列表'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .bindSheet($$this.showFilter, this.filterSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: true,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showFilter = false;
      }
    })
    .width('100%')
    .height('100%')
  }

  /** 筛选面板：主面板（入口行）+ 子面板（标签列表，ArkUI 弹窗列表式） */
  @Builder
  filterSheet() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
      if (this.filterSubPanel.length === 0) {
        Text('筛选')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .width('100%')
        // 主题入口（点击弹子列表）
        this.topicEntry('主题', this.filterTopics.length, () => {
          this.filterSubPanel = 'topics';
        })
        this.topicEntry('排除主题', this.filterExcludeTopics.length, () => {
          this.filterSubPanel = 'excludeTopics';
        })
        this.filterGroup('status', '状态', ['全部', '连载', '完结'])
        this.filterGroup('eps', '话数', ['全部', '单话 (1话)', '短篇 (2-5话)', '中篇 (6-20话)', '长篇 (21-100话)', '超长篇 (100话以上)'])
        this.filterGroup('pages', '页数', ['全部', '少页 (<50页)', '中等 (50-200页)', '多页 (200-500页)', '超多页 (500页以上)'])
        Row().height(12)
      } else {
        // 子面板：标签选择列表
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([COLOR_TEXT_TITLE])
            .padding(4)
            .onClick(() => {
              this.filterSubPanel = '';
            })
          Text(this.filterSubPanel === 'topics' ? '选择主题' : '排除主题')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        List({ space: 0 }) {
          ForEach(this.TOPIC_OPTIONS, (opt: string, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Text(opt)
                    .fontSize(15)
                    .fontColor(this.isTopicSelected(opt) ? COLOR_PRIMARY : COLOR_TEXT_TITLE)
                    .fontWeight(this.isTopicSelected(opt) ? FontWeight.Medium : FontWeight.Normal)
                    .layoutWeight(1)
                  if (this.isTopicSelected(opt)) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(18)
                      .fontColor([COLOR_PRIMARY])
                  }
                }
                .width('100%')
                .height(48)
                .padding({ left: 14, right: 14 })
                .backgroundColor(this.isTopicSelected(opt) ? COLOR_PRIMARY_TINT : Color.Transparent)
                .onClick(() => this.toggleTopic(opt, this.filterSubPanel === 'excludeTopics'))
              }
              .width('100%')
            }
          }, (opt: string) => opt)
        }
        .width('100%')
        .height(320)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .backgroundColor(COLOR_CARD)
        .borderRadius(16)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
    .backgroundColor(COLOR_BG)
  }

  private isTopicSelected(opt: string): boolean {
    let arr = this.filterSubPanel === 'topics' ? this.filterTopics : this.filterExcludeTopics;
    return arr.indexOf(opt) >= 0;
  }

  /** 主题入口行（点击弹子列表） */
  @Builder
  topicEntry(title: string, count: number, onOpen: () => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(COLOR_TEXT_TITLE)
        .layoutWeight(1)
      Text(count > 0 ? '已选 ' + count : '全部')
        .fontSize(13)
        .fontColor(count > 0 ? COLOR_PRIMARY : COLOR_TEXT_HINT)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([COLOR_TEXT_DISABLED])
        .margin({ left: 4 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 4, right: 8 })
    .onClick(() => onOpen())
  }

  /** 单选组（读 this 状态，响应式） */
  @Builder
  filterGroup(kind: string, title: string, options: string[]) {
    Column({ space: 0 }) {
      Text(title)
        .fontSize(13)
        .fontColor(COLOR_TEXT_HINT)
        .width('100%')
        .margin({ bottom: 6 })
      Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
        ForEach(options, (opt: string) => {
          Text(opt)
            .fontSize(13)
            .fontColor(this.currentFilterValue(kind) === opt ? COLOR_WHITE : COLOR_TEXT_TITLE)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.currentFilterValue(kind) === opt ? COLOR_PRIMARY : COLOR_CARD)
            .borderRadius(14)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => this.setFilterValue(kind, opt))
        }, (opt: string) => opt)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private currentFilterValue(kind: string): string {
    if (kind === 'status') {
      return this.filterStatus;
    }
    if (kind === 'eps') {
      return this.filterEps;
    }
    return this.filterPages;
  }

  private setFilterValue(kind: string, value: string): void {
    if (kind === 'status') {
      this.filterStatus = value;
    } else if (kind === 'eps') {
      this.filterEps = value;
    } else {
      this.filterPages = value;
    }
    this.load(true);
  }
}