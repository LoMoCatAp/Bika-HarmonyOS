import { router, display, promptAction, curves, LengthMetrics, ComponentContent } from '@kit.ArkUI';
import { showImmersiveToast, showImmersiveDialog } from '../common/ImmersiveToast';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ApiService, ComicsPageResult } from '../network/ApiService';
import { ComicViewModel, buildImageUrl, BikaComicSummary, BikaNotification, BikaComment, BikaComicDetail } from '../models/Comic';
import { NetImage } from '../components/NetImage';
import { ComicCard } from '../components/ComicCard';
import { CacheManager, HistoryItem } from '../common/CacheManager';
import {
  publishContinuationRoute,
  CONTINUATION_PROFILE_SUBPAGE_KEY,
  ContinuationRouteParams,
  ROUTE_HOME,
  ROUTE_CHANNEL_LIST,
  ROUTE_COMIC_DETAIL,
  ROUTE_READER,
  ROUTE_PROFILE_SUBPAGE,
  ROUTE_SEARCH,
  ROUTE_SEARCH_RESULT
} from '../common/ContinuationState';
import { DownloadManager, DownloadTask } from '../common/DownloadManager';
import { compatibleImmersiveMaterial, compatibleSheetMaterial } from '../common/CompatibleMaterial';
import { ImageLoader } from '../common/ImageLoader';
import { WindowHelper } from '../common/WindowHelper';
import { ApiRouteManager } from '../network/ApiRouteManager';
import { DnsService, DnsIpEntry } from '../network/DnsService';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_PRIMARY_TINT_2,
  COLOR_BG,
  COLOR_TEXT_SECONDARY,
  COLOR_TEXT_HINT,
  COLOR_TEXT_DISABLED,
  COLOR_TEXT_TITLE,
  COLOR_CARD,
  COLOR_INPUT_BG,
  COLOR_PLACEHOLDER,
  COLOR_GLASS_TOP,
  COLOR_DIVIDER,
  COLOR_WHITE,
  COLOR_LOGOUT_TEXT,
  DEFAULT_CHANNELS,
  SORT_OPTIONS,
  SortOption,
  BikaChannel,
  adaptiveChannelColumns,
  adaptiveListColumns
} from '../common/Constants';
import { HdsTabs, HdsTabsController, HdsAnimationMode, DividerMode, hdsMaterial, HdsNavigation, HdsNavDestination, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';

/**
 * 主入口 — HdsTabs 悬浮页签（首页 / 我的）
 * 沉浸光感页签 + 子页面打开时页签收起动画
 */

/** 全部分类标识 */
const CATEGORY_ALL: string = '全部';

// Refresh 只负责手势与回弹；提示在标题栏下方单独绘制，避免进入状态栏。
@Builder
function homeRefreshPlaceholder() {
  Row().width('100%').height(0)
}

// ═══════════════════════════════════════════
// 首页 — 频道网格
@Component
struct HomePage {
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') @Watch('onHomeAuthChanged') isLoggedIn: boolean = false;
  @StorageProp('avatarUrl') avatarUrl: string = '';
  @StorageProp('bika_material_rev') materialRev: number = 0;
  /** 频道自定义：顺序与隐藏 */
  @State channelOrder: string[] = [];
  @State channelHidden: string[] = [];
  @State showChannelEdit: boolean = false;
  @State refreshing: boolean = false;
  @State refreshPullOffset: number = 0;
  /** 频道按压效果 */
  @State pressedChannel: string = '';
  private cache: CacheManager | null = null;
  private homeStack: NavPathStack = new NavPathStack();
  private homeScroller: Scroller = new Scroller();
  private avatarRequest: number = 0;
  private refreshInFlight: boolean = false;
  private refreshContent: ComponentContent<Object> | undefined = undefined;

  /** 跳转个人中心（由 IndexPage 切换 tab） */
  onGotoProfile(): void {
    AppStorage.set('bika_goto_profile', Date.now());
  }

  aboutToAppear(): void {
    this.refreshContent = new ComponentContent(this.getUIContext(), wrapBuilder(homeRefreshPlaceholder));
    this.reloadHomeData().catch(() => {
      // 网络不可用时保留本地频道和默认头像。
    });
  }

  aboutToDisappear(): void {
    this.avatarRequest++;
    this.refreshContent?.dispose();
    this.refreshContent = undefined;
  }

  private onHomeAuthChanged(): void {
    this.avatarRequest++;
    if (this.isLoggedIn) {
      this.loadHomeAvatar().catch(() => {});
    }
  }

  private async loadHomeAvatar(): Promise<void> {
    if (!this.isLoggedIn) {
      return;
    }
    const request = ++this.avatarRequest;
    const user = await ApiService.getInstance().getUserProfile();
    if (request === this.avatarRequest && this.isLoggedIn) {
      AppStorage.setOrCreate('avatarUrl', user.avatar?.path ? buildImageUrl(user.avatar) : '');
    }
  }

  private async reloadHomeData(): Promise<void> {
    const cache = await CacheManager.getInstance();
    this.cache = cache;
    this.channelOrder = cache.loadChannelsOrder();
    this.channelHidden = cache.loadChannelsHidden();
    await this.loadHomeAvatar();
  }

  private async refreshHome(): Promise<void> {
    if (this.refreshInFlight) {
      return;
    }
    this.refreshInFlight = true;
    this.refreshing = true;
    const startedAt = Date.now();
    try {
      await this.reloadHomeData();
    } catch (err) {
      showImmersiveToast({ message: '刷新失败，请稍后重试', duration: 1600 });
    } finally {
      // 本地数据可能立即返回，保留短暂展示时间，避免刚展开就收起。
      const remaining = 400 - (Date.now() - startedAt);
      if (remaining > 0) {
        await new Promise<void>((resolve) => { setTimeout(resolve, remaining); });
      }
      this.refreshInFlight = false;
      this.refreshing = false;
    }
  }

  /** 按自定义顺序与隐藏过滤后的频道 */
  private visibleChannels(): BikaChannel[] {
    let base = DEFAULT_CHANNELS.slice(0);
    if (this.channelOrder.length > 0) {
      base.sort((a: BikaChannel, b: BikaChannel) => {
        let ia = this.channelOrder.indexOf(a.label);
        let ib = this.channelOrder.indexOf(b.label);
        if (ia < 0) {
          ia = 999;
        }
        if (ib < 0) {
          ib = 999;
        }
        return ia - ib;
      });
    }
    return base.filter(c => this.channelHidden.indexOf(c.label) < 0);
  }

  /** 当前编辑顺序列表 */
  private channelEditList(): string[] {
    let labels = this.channelOrder.length > 0
      ? this.channelOrder.slice(0)
      : DEFAULT_CHANNELS.map(c => c.label);
    return labels;
  }

  private persistChannels(): void {
    if (this.cache) {
      this.cache.saveChannelsCustom(this.channelOrder, this.channelHidden);
    }
  }

  private moveChannel(index: number, delta: number): void {
    let list = this.channelEditList();
    let to = index + delta;
    if (to < 0 || to >= list.length) {
      return;
    }
    let tmp = list[index];
    list[index] = list[to];
    list[to] = tmp;
    this.channelOrder = list;
    this.persistChannels();
  }

  private toggleChannelHidden(label: string): void {
    let arr = this.channelHidden.slice(0);
    let idx = arr.indexOf(label);
    if (idx >= 0) {
      arr.splice(idx, 1);
    } else {
      arr.push(label);
    }
    this.channelHidden = arr;
    this.persistChannels();
  }

  private resetChannels(): void {
    this.channelOrder = [];
    this.channelHidden = [];
    this.persistChannels();
  }

  /** 频道编辑弹窗 */
  @Builder
  channelEditSheet() {
    Column({ space: 0 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text('编辑频道')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        Text('恢复默认')
          .fontSize(13)
          .fontColor(COLOR_PRIMARY)
          .onClick(() => this.resetChannels())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.channelEditList(), (label: string, index: number) => {
            Row({ space: 8 }) {
              Image(DEFAULT_CHANNELS.find(c => c.label === label)?.icon ?? $r('app.media.ic_cat_index'))
                .width(30)
                .height(30)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
                .backgroundColor(COLOR_PLACEHOLDER)
              Text(label)
                .fontSize(14)
                .fontColor(this.channelHidden.indexOf(label) >= 0 ? COLOR_TEXT_HINT : COLOR_TEXT_TITLE)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.arrow_up'))
                .fontSize(16)
                .fontColor([index > 0 ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED])
                .padding(6)
                .onClick(() => this.moveChannel(index, -1))
              SymbolGlyph($r('sys.symbol.arrow_down'))
                .fontSize(16)
                .fontColor([index < this.channelEditList().length - 1 ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED])
                .padding(6)
                .onClick(() => this.moveChannel(index, 1))
              Toggle({ type: ToggleType.Switch, isOn: this.channelHidden.indexOf(label) < 0 })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.toggleChannelHidden(label);
                })
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
          }, (label: string) => label)
        }
        .width('100%')
        .padding({ bottom: this.bottomSafeHeight + 12 })
      }
      .width('100%')
      .height(this.channelSheetHeight())
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  /** 频道编辑列表高度（屏幕 55%） */
  private channelSheetHeight(): number {
    return px2vp(display.getDefaultDisplaySync().height) * 0.55;
  }

  /** 频道按压缩放（受全局动画开关控制） */
  private setChannelPressed(label: string, down: boolean): void {
    let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
    if (!animOn) {
      return;
    }
    if (down) {
      animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
        this.pressedChannel = label;
      });
    } else {
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.pressedChannel = '';
      });
    }
  }

  @Builder
  homeHeader() {
    Row({ space: 8 }) {
      Text('Bika')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .layoutWeight(1)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([COLOR_TEXT_TITLE])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .attributeModifier(compatibleImmersiveMaterial('#FF7CA8', false, true))
      .accessibilityText('编辑频道')
      .onClick(() => { this.showChannelEdit = true; })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([COLOR_TEXT_TITLE])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .attributeModifier(compatibleImmersiveMaterial('#FF7CA8', false, true))
      .accessibilityText('搜索')
      .onClick(() => { router.pushUrl({ url: 'pages/SearchPage' }); })
      if (this.isLoggedIn) {
        if (this.avatarUrl.length > 0) {
          NetImage({ src: this.avatarUrl, fit: ImageFit.Cover, radius: 18, fillParent: true })
            .width(36)
            .height(36)
            .accessibilityText('个人中心')
            .onClick(() => { this.onGotoProfile(); })
        } else {
          Image($r('app.media.ic_default_avatar'))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .accessibilityText('个人中心')
            .onClick(() => { this.onGotoProfile(); })
        }
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  guestChannel() {
    Column({ space: 12 }) {
      Stack() {
        Circle().width(172).height(172).fill(COLOR_PRIMARY_TINT)
        Circle().width(18).height(18).fill(COLOR_PRIMARY).opacity(0.35)
          .translate({ x: 78, y: -60 })
        Circle().width(10).height(10).fill(COLOR_PRIMARY).opacity(0.5)
          .translate({ x: -82, y: 42 })
        Column() {}
          .width(118).height(144).backgroundColor(COLOR_PRIMARY).opacity(0.25)
          .borderRadius(18).rotate({ angle: -14 }).translate({ x: -8, y: 2 })
        Column({ space: 12 }) {
          Text('Bika').fontSize(25).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY)
          Row().width(54).height(4).backgroundColor(COLOR_PRIMARY_TINT).borderRadius(2)
          Row().width(38).height(4).backgroundColor(COLOR_PRIMARY_TINT).borderRadius(2)
        }
        .width(118).height(144).justifyContent(FlexAlign.Center)
        .backgroundColor(COLOR_CARD).borderRadius(18)
        .border({ width: 2, color: COLOR_PRIMARY_TINT }).rotate({ angle: 8 })
      }
      .width(208).height(200)
      .accessibilityLevel('no')
      Text('请登录')
        .fontSize(26).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_TITLE)
      Text('登录后可同步收藏与阅读进度')
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
      Row({ space: 8 }) {
        Text('立即登录').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_WHITE)
        SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(16).fontColor([COLOR_WHITE])
      }
      .height(44).padding({ left: 24, right: 24 }).borderRadius(22)
      .backgroundColor(COLOR_PRIMARY).margin({ top: 10 })
    }
    .width('100%')
    .padding({ top: 30, bottom: 32, left: 20, right: 20 })
    .linearGradient({ angle: 160, colors: [[COLOR_PRIMARY_TINT, 0], [COLOR_CARD, 0.7]] })
    .borderRadius(28)
    .scale({ x: this.pressedChannel === '__guest_login__' ? 0.97 : 1,
      y: this.pressedChannel === '__guest_login__' ? 0.97 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setChannelPressed('__guest_login__', true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.type === TouchType.Move) {
        this.setChannelPressed('__guest_login__', false);
      }
    })
    .accessibilityGroup(true)
    .accessibilityText('请登录，点击登录')
    .onClick(() => router.pushUrl({ url: 'pages/LoginPage', params: { from: 'inapp' } }))
  }

  @Builder
  refreshHeader() {
    Row({ space: 8 }) {
      LoadingProgress().width(22).height(22).color(COLOR_PRIMARY)
      Text(this.refreshing ? '正在刷新' : (this.refreshPullOffset >= 64 ? '松开刷新' : '下拉刷新'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .position({ x: 0, y: this.topSafeHeight + 56 + Math.max(0, (this.refreshPullOffset - 48) / 2) })
    .opacity(Math.min(1, Math.max(0, (this.refreshPullOffset - 24) / 24)))
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  homeNavigation() {
    HdsNavigation(this.homeStack) {
      Scroll(this.homeScroller) {
        Column() {
          // 内容从标题下方开始，滚动时进入原生标题栏的模糊采样区域。
          Row().height(this.topSafeHeight + 56)

          if (!this.isLoggedIn) {
            Column() {
              this.guestChannel()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 76 })
          }

          // 频道网格（方形图标 + 名称，按自定义顺序与隐藏过滤）
          if (this.isLoggedIn) {
          Grid() {
            ForEach(this.visibleChannels(), (ch: BikaChannel) => {
              GridItem() {
                Column({ space: 8 }) {
                  Image(ch.icon)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(18)
                    .backgroundColor(COLOR_PLACEHOLDER)
                  Text(ch.label)
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .scale({ x: this.pressedChannel === ch.label ? 0.94 : 1, y: this.pressedChannel === ch.label ? 0.94 : 1 })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.setChannelPressed(ch.label, true);
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.setChannelPressed(ch.label, false);
                  }
                })
                .onClick(() => {
                  if (ch.kind === 'board') {
                    showImmersiveToast({ message: '该功能已下线', duration: 1600 });
                    return;
                  }
                  router.pushUrl({
                    url: 'pages/ChannelListPage',
                    params: { label: ch.label, kind: ch.kind }
                  });
                })
              }
            }, (ch: BikaChannel) => ch.label)
          }
          .columnsTemplate(adaptiveChannelColumns())
          .columnsGap(14)
          .rowsGap(18)
          .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 76 })
          }
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .edgeEffect(EdgeEffect.None, { alwaysEnabled: true })
      .translate({ y: this.refreshPullOffset })
      .backgroundColor(COLOR_BG)

    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar({
      content: { title: { mainTitle: '' }, stackBuilder: () => this.homeHeader() },
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveEndOffset: LengthMetrics.vp(64)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    })
    .bindToScrollable([this.homeScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
    // 自定义刷新节点存在时，固定导航容器，只有内容区跟随下拉。
    .position({ x: 0, y: 0 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({ refreshing: $$this.refreshing, refreshingContent: this.refreshContent }) {
        this.homeNavigation()
      }
      .width('100%')
      .height('100%')
      .refreshOffset(64)
      .maxPullDownDistance(128)
      .onOffsetChange((offset: number) => { this.refreshPullOffset = Math.max(0, offset); })
      .onRefreshing(() => { this.refreshHome(); })
      this.refreshHeader()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showChannelEdit, this.channelEditSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showChannelEdit = false;
      }
    })
  }
}

// ═══════════════════════════════════════════
// 我的 — 个人中心
// ═══════════════════════════════════════════

/** 下载分组（按作品归纳） */
interface DownloadGroup {
  comicId: string;
  title: string;
  coverUrl: string;
  coverLocal: string;
  description: string;
  author: string;
  downloadedCount: number;
  totalCount: number;
  hasDownloading: boolean;
  hasWaiting: boolean;
  hasFailed: boolean;
  failedFirst: DownloadTask | null;
  downloadingTitle: string;
  downloadingProgress: number;
  downloadingTotal: number;
  sizeBytes: number;
}

/**
 * 下载列表单项（按作品）。
 *
 * 为什么单独成组件：进度每页都会变，若把它放进 ForEach 的数据里、或用含进度的键值，
 * 列表项会被销毁重建 —— 封面图跟着重新加载，表现为「图片一直闪」。
 * 这里让列表项自己订阅 DownloadManager，进度只更新本组件内部 @State，
 * 父级 ForEach 键值始终是 comicId（稳定），封面图节点创建一次后不再重建。
 */
@Component
struct DownloadGroupItem {
  /** 作品 id（父组件仅在分组增删时创建 / 销毁本组件） */
  comicId: string = '';
  /** 作品元数据：不会变化，仅创建时赋值一次 */
  title: string = '';
  coverUrl: string = '';
  coverLocal: string = '';
  description: string = '';
  author: string = '';

  // ── 会随下载进度变化的状态（只影响本组件内部节点） ──
  @State downloadedCount: number = 0;
  @State totalCount: number = 0;
  @State hasDownloading: boolean = false;
  @State hasWaiting: boolean = false;
  @State hasFailed: boolean = false;
  @State failedOrder: number = 0;
  @State failedTitle: string = '';
  @State downloadingTitle: string = '';
  @State downloadingProgress: number = 0;
  @State downloadingTotal: number = 0;
  @State sizeBytes: number = 0;

  private cb: (tasks: DownloadTask[]) => void = (tasks: DownloadTask[]) => {
    this.applyTasks(tasks);
  };

  aboutToAppear(): void {
    // 订阅即刻回调一次：进入页面时已经在下（或已完成）的任务立即显示真实进度
    DownloadManager.getInstance().subscribe(this.cb);
  }

  aboutToDisappear(): void {
    DownloadManager.getInstance().unsubscribe(this.cb);
  }

  /** 只统计本作品的任务；进度变化只写本组件 @State，不触碰封面图节点 */
  private applyTasks(tasks: DownloadTask[]): void {
    let downloaded: number = 0;
    let total: number = 0;
    let size: number = 0;
    let downloading: boolean = false;
    let waiting: boolean = false;
    let failed: boolean = false;
    let dlTitle: string = '';
    let dlProgress: number = 0;
    let dlTotal: number = 0;
    let fOrder: number = 0;
    let fTitle: string = '';
    for (let t of tasks) {
      if (t.comicId !== this.comicId) {
        continue;
      }
      total += 1;
      if (t.status === 'completed') {
        downloaded += 1;
        size += t.sizeBytes ?? 0;
      } else if (t.status === 'downloading') {
        downloading = true;
        dlTitle = t.chapterTitle;
        dlProgress = t.progress;
        dlTotal = t.total;
      } else if (t.status === 'waiting') {
        waiting = true;
      } else if (t.status === 'failed') {
        failed = true;
        if (fOrder === 0) {
          fOrder = t.chapterOrder;
          fTitle = t.chapterTitle;
        }
      }
    }
    this.downloadedCount = downloaded;
    this.totalCount = total;
    this.sizeBytes = size;
    this.hasDownloading = downloading;
    this.hasWaiting = waiting;
    this.hasFailed = failed;
    this.downloadingTitle = dlTitle;
    this.downloadingProgress = dlProgress;
    this.downloadingTotal = dlTotal;
    this.failedOrder = fOrder;
    this.failedTitle = fTitle;
  }

  private sizeLabel(bytes: number): string {
    if (bytes <= 0) {
      return '';
    }
    if (bytes >= 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    if (bytes >= 1024) {
      return (bytes / 1024).toFixed(0) + ' KB';
    }
    return bytes + ' B';
  }

  /** 删除整部作品的下载（原生确认框） */
  private confirmDeleteGroup(): void {
    showImmersiveDialog({
      title: '删除下载',
      message: '删除《' + this.title + '》的全部已下载章节？本地文件将一并删除，且不可恢复。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '删除', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        let manager = DownloadManager.getInstance();
        for (let t of manager.getTasks()) {
          if (t.comicId === this.comicId) {
            manager.deleteTask(t.comicId, t.chapterOrder);
          }
        }
        showImmersiveToast({ message: '已删除', duration: 1600 });
      }
    }).catch((err: Error) => {
      console.warn('[DownloadListView] delete dialog failed: ' + JSON.stringify(err));
    });
  }

  build() {
    Row() {
      if (this.coverLocal.length > 0) {
        NetImage({
          src: 'file://' + this.coverLocal,
          fit: ImageFit.Cover,
          radius: 10,
          fillParent: true
        })
          .width(76)
          .height(100)
      } else {
        NetImage({
          src: this.coverUrl,
          fit: ImageFit.Cover,
          radius: 10,
          fillParent: true
        })
          .width(76)
          .height(100)
      }
      Column({ space: 6 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.author.length > 0) {
          Text(this.author)
            .fontSize(12)
            .fontColor(COLOR_TEXT_HINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.description.length > 0) {
          Text(this.description)
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Row() {
          Text('已下载 ' + this.downloadedCount + '/' + this.totalCount + ' 话')
            .fontSize(12)
            .fontColor(this.downloadedCount === this.totalCount ? COLOR_PRIMARY : COLOR_TEXT_HINT)
          if (this.sizeBytes > 0) {
            Text(' · ' + this.sizeLabel(this.sizeBytes))
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .margin({ left: 4 })
          }
          Blank()
          if (this.hasDownloading) {
            Text('下载中')
              .fontSize(11)
              .fontColor(COLOR_PRIMARY)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor(COLOR_PRIMARY_TINT)
              .borderRadius(8)
          } else if (this.hasWaiting) {
            Text('等待中')
              .fontSize(11)
              .fontColor(COLOR_TEXT_SECONDARY)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor(COLOR_INPUT_BG)
              .borderRadius(8)
          }
        }
        .width('100%')
        if (this.hasDownloading) {
          Text('正在下载：' + (this.downloadingTitle.length > 0 ? this.downloadingTitle : ('第' + (this.downloadedCount + 1) + '话')))
            .fontSize(11)
            .fontColor(COLOR_TEXT_HINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row() {
            Progress({
              value: this.downloadingTotal > 0 ? this.downloadingProgress * 100 / this.downloadingTotal : 0,
              type: ProgressType.Linear
            })
              .height(4)
              .layoutWeight(1)
              .color(COLOR_PRIMARY)
              .backgroundColor(COLOR_PRIMARY_TINT)
            Text(this.downloadingTotal > 0 ? Math.round(this.downloadingProgress * 100 / this.downloadingTotal) + '%' : '等待中')
              .fontSize(11)
              .fontColor(COLOR_PRIMARY)
              .margin({ left: 8 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else if (this.hasWaiting) {
          if (DownloadManager.getInstance().getWifiOnly() && !DownloadManager.getInstance().isWifiNow()) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(13)
                .fontColor([COLOR_TEXT_HINT])
              Text('等待 WiFi，连接后自动下载')
                .fontSize(11)
                .fontColor(COLOR_TEXT_HINT)
            }
            .width('100%')
          } else {
            Text('排队中，即将开始…')
              .fontSize(11)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
          }
        }
        if (this.hasFailed) {
          Row() {
            Text('下载失败：' + (this.failedTitle.length > 0 ? this.failedTitle : ('第' + this.failedOrder + '话')))
              .fontSize(11)
              .fontColor('#C62828')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('重试')
              .fontSize(11)
              .fontColor(COLOR_PRIMARY)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(COLOR_PRIMARY_TINT)
              .borderRadius(10)
              .margin({ left: 8 })
              .onClick(() => {
                DownloadManager.getInstance().retryTask(this.comicId, this.failedOrder);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([COLOR_TEXT_HINT])
        .padding(6)
        .alignSelf(ItemAlign.Start)
        .onClick(() => {
          this.confirmDeleteGroup();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .border({ width: 1, color: COLOR_DIVIDER })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/ComicDetailPage',
        params: { comicId: this.comicId, comicTitle: this.title }
      });
    })
  }
}

/** 下载列表（独立组件：订阅 DownloadManager 实时刷新） */
@Component
struct DownloadListView {
  scroller: Scroller = new Scroller();
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @State tasks: DownloadTask[] = [];
  @StorageProp('bika_material_rev') materialRev: number = 0;
  private cb: (tasks: DownloadTask[]) => void = (tasks: DownloadTask[]) => {
    this.tasks = tasks;
  };

  aboutToAppear(): void {
    DownloadManager.getInstance().subscribe(this.cb);
  }

  aboutToDisappear(): void {
    DownloadManager.getInstance().unsubscribe(this.cb);
  }

  /** 分组 */
  private groups(): DownloadGroup[] {
    let map = new Map<string, DownloadGroup>();
    for (let t of this.tasks) {
      let g = map.get(t.comicId);
      if (!g) {
        g = {
          comicId: t.comicId,
          title: t.comicTitle,
          coverUrl: t.coverUrl ?? '',
          coverLocal: t.coverLocal ?? '',
          description: t.description ?? '',
          author: t.author ?? '',
          downloadedCount: 0,
          totalCount: 0,
          hasDownloading: false,
          hasWaiting: false,
          hasFailed: false,
          failedFirst: null,
          downloadingTitle: '',
          downloadingProgress: 0,
          downloadingTotal: 0,
          sizeBytes: 0
        };
        map.set(t.comicId, g);
      }
      g.totalCount++;
      if (t.status === 'completed') {
        g.downloadedCount++;
        g.sizeBytes += t.sizeBytes ?? 0;
      }
      if (t.status === 'downloading') {
        g.hasDownloading = true;
        g.downloadingTitle = t.chapterTitle;
        g.downloadingProgress = t.progress;
        g.downloadingTotal = t.total;
      }
      if (t.status === 'waiting') {
        g.hasWaiting = true;
      }
      if (t.status === 'failed') {
        g.hasFailed = true;
        if (!g.failedFirst) {
          g.failedFirst = t;
        }
      }
    }
    return Array.from(map.values());
  }

  build() {
    List({ space: 12, scroller: this.scroller }) {
    if (this.groups().length === 0) {
      ListItem() {
      Column({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(36)
          .fontColor([COLOR_TEXT_DISABLED])
        Text('暂无下载任务')
          .fontSize(14)
          .fontColor(COLOR_TEXT_HINT)
        Text('在漫画详情页点击下载即可离线阅读')
          .fontSize(12)
          .fontColor(COLOR_TEXT_HINT)
      }
      .width('100%')
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(COLOR_BG)
      }
    } else {
        ForEach(this.groups(), (g: DownloadGroup) => {
          ListItem() {
            // 列表项自己订阅进度：ForEach 键值固定为 comicId（稳定），
            // 进度刷新只重渲染项内文本，封面图节点不被销毁重建（不闪烁）
            DownloadGroupItem({
              comicId: g.comicId,
              title: g.title,
              coverUrl: g.coverUrl,
              coverLocal: g.coverLocal,
              description: g.description,
              author: g.author
            })
          }
        }, (g: DownloadGroup) => g.comicId)
    }
    }
    .width('100%').height('100%')
    .padding({ left: 16, right: 16 })
    .contentStartOffset(this.topSafeHeight + 56 + 12)
    .contentEndOffset(this.bottomSafeHeight + 24)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .cachedCount(3, true)
    .clip(false)
  }
}

/** 沉浸光感档位下拉（原样式；组件级 @StorageLink 保证在设置页内即时刷新） */
@Component
struct MaterialLevelSelect {
  @StorageLink('bika_material_level') level: string = 'EXQUISITE';
  @State popScale: number = 1;

  private label(): string {
    for (let i = 0; i < MATERIAL_OPTIONS.length; i++) {
      if (MATERIAL_OPTIONS[i].value === this.level) {
        return MATERIAL_OPTIONS[i].label;
      }
    }
    return '强';
  }

  build() {
    Row({ space: 4 }) {
      Text(this.label())
        .fontSize(15)
        .fontColor(COLOR_PRIMARY)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([COLOR_PRIMARY])
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .scale({ x: this.popScale, y: this.popScale })
    .bindMenu(MATERIAL_OPTIONS.map((opt: MaterialOption): MenuElement => {
      return {
        value: opt.label,
        action: (): void => {
          // 与显示模式一致的动画过渡：先弹簧弹跳，再渐变应用新档位
          let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
          if (animOn) {
            animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
              this.popScale = 1.12;
            });
            animateTo({ duration: 320, curve: curves.springMotion(0.55, 0.85) }, () => {
              this.popScale = 1;
              this.level = opt.value;
              let r = AppStorage.get<number>('bika_material_rev') ?? 0;
              AppStorage.setOrCreate('bika_material_rev', r + 1);
            });
          } else {
            this.level = opt.value;
            let r = AppStorage.get<number>('bika_material_rev') ?? 0;
            AppStorage.setOrCreate('bika_material_rev', r + 1);
          }
          CacheManager.getInstance().then(c => c.saveSetting('material_level', opt.value));
        }
      };
    }))
  }
}

/** 更新日志条目 */
interface ChangelogEntry {
  version: string;
  date: string;
  items: string[];
}

/** 更新弹窗正文块 */
interface UpdateBlock {
  kind: string;
  text: string;
}

/** 行内富文本段 */
interface MdRun {
  text: string;
  bold: boolean;
}

/** 更新日志（可折叠列表） */
const CHANGELOG_ENTRIES: ChangelogEntry[] = [
  {
    version: '1.4.2',
    date: '2026-10-05',
    items: [
      '新增：应用接续',
      '新增：下载支持后台运行',
      '新增：下载进度通知',
      '修复：下载页进度不实时刷新',
      '修复：开启「仅 WiFi 下载」后任务概率不派发'
    ]
  },
  {
    version: '1.4.1',
    date: '2026-10-04',
    items: [
      '修复：弹窗边框与底色不一致',
      '修复：频道页与评论区的下拉刷新、上拉加载更多缺少加载提示',
      '优化：评论输入弹窗改为自适应高度输入框与紧凑发送按钮'
    ]
  },
  {
    version: '1.4.0',
    date: '2026-10-04',
    items: [
      '修复：冷启动时短暂显示「未登录」；深色模式下「更新日志」与「隐私政策」弹窗底色与应用背景不一致',
      '新增：未登录进入应用时引导登录',
      '主页：新增下拉刷新；未登录首页加入引导',
      '注册页：界面风格与登录页统一，标题栏改为与「我的」子页一致的沉浸光感样式',
      '桌面卡片：修复多卡同时刷新导致刷新超时、封面偶发不显示、退出登录后仍显示上一账号内容等问题',
      '优化：设置页文案更准确、更简洁；DNS 与检查更新提示不再暴露第三方工具与实现细节',
      '隐私：系统日志不再记录作品名等敏感信息；退出登录会一并清理历史与卡片缓存'
    ]
  },
  {
    version: '1.3.8',
    date: '2026-10-04',
    items: [
      '新增：页面标题栏沉浸光感效果 —— 静止时完全透明，上滑时顶部渐显模糊，内容从标题栏下方穿过',
      '覆盖「我的」全部 12 个子页：收藏 / 历史 / 下载 / 通知 / 我的评论 / 设置 / 关于 / 存储与空间 / DNS 优化 / 屏蔽标签 / 资料编辑 / 账号与安全',
      '新增：桌面小组件，共 5 张卡片 —— 继续阅读 / 最近更新 / 排行榜 / 我的收藏 / 为你推荐',
      '卡片支持真实封面与内容，点击卡片可直达阅读器或作品详情页，并跟随系统深浅色',
      '设置新增「桌面卡片」分组，可控制卡片是否显示真实内容与封面'
    ]
  },
  {
    version: '1.3.7',
    date: '2026-10-03',
    items: [
      '目标版本升级至 API 26',
      '优化：Toast 与系统弹窗升级为沉浸光感材质，观感与系统风格保持一致',
      '注：沉浸材质依赖设备能力，需设备系统支持（HarmonyOS 7.0.0 及以上）；未升级系统的设备无需更新此版本'
    ]
  },
  {
    version: '1.3.6',
    date: '2026-10-01',
    items: [
      '国庆节快乐 🎉',
      '优化：调整「退出登录」文字配色，深浅色模式下分别采用更柔和的红色，降低视觉突兀感',
      '官方接口已移除部分组件的沉浸光感材质，本版起页面卡片统一回退为常规列表',
      '如需保留原有沉浸光感卡片效果，可继续使用 v1.3.5',
      '后续功能更新将基于 v1.3.6 持续开发'
    ]
  },
  {
    version: '1.3.5',
    date: '2026-08-31',
    items: [
      '修复：首页「推荐」分区改为全部漫画最新分页流',
      '修复：分类列表接口响应解析错误导致全部分类空白',
      '修复：分类页排序/筛选请求（移除冗余重试导致的频控）'
    ]
  },
  {
    version: '1.3.4',
    date: '2026-08-30',
    items: [
      '修复：分类页（频道列表）内容加载失败时自动重试一次，补充空态与重试按钮',
      '修复：主页/收藏页底部留白不足，频道被底部导航栏遮挡',
      '详情页相关推荐接口未返回时回退「全部最新」列表'
    ]
  },
  {
    version: '1.3.3',
    date: '2026-08-20',
    items: [
      '平板适配：首页频道网格与作品列表按屏幕宽度自适应列数（平板最多 6 列）',
      '阅读器平板适配：内容限宽居中，两侧留黑不再撑满整屏'
    ]
  },
  {
    version: '1.3.2',
    date: '2026-08-19',
    items: [
      '修复：更新日志、隐私政策弹窗无法打开（多个底部弹窗互相冲突）',
      '修复：沉浸光感档位切换不即时生效（档位恢复统一下拉样式，材质强度即时应用）',
      '检查更新弹窗：更新说明适配 Markdown 排版（标题/列表/加粗）'
    ]
  },
  {
    version: '1.3.1',
    date: '2026-08-18',
    items: [
      '动画：全局动画开关（设置→常规），按钮弹簧/卡片按压/图片占位呼吸/阅读器工具栏过渡/页码胶囊/频道按压',
      '沉浸光感档位切换即时生效（底部导航栏）',
      '系统代理：规则模式 VPN 分流（设置→DNS 优化），无需全局模式',
      '下载管理：单作品删除按钮 + 修复本地文件无法删除的问题',
      '关于页新增 GitHub 项目主页链接',
      '修复：音量键偶发需按两次、弹窗打开时音量键仍翻页'
    ]
  },
  {
    version: '1.3.0',
    date: '2026-08-17',
    items: [
      '评论区：排序（最新/最早/最多赞）+ 分页加载',
      '漫画分享：ShareKit 系统分享面板',
      '阅读器：音量键翻页（音量上=下一页，音量下=上一页，设置可关）',
      '图片缓存：新增 200MB 磁盘缓存（三级缓存）',
      '图片拖拽：长按拖到中转站/其他应用（UDMF 系统拖拽）',
      '导出作品：当前章节导出 PDF / 图片压缩包（系统保存对话框，自定义位置与文件名）',
      '修复：下载弹窗与评论弹窗互相冲突失效'
    ]
  },
  {
    version: '1.2.0',
    date: '2026-08-15',
    items: [
      '登录页重写：用户名 + 密码登录（不支持邮箱登录）',
      '注册：用户名 + 昵称 + 密码 + 三道密保题',
      '屏蔽标签：设置中按关键词屏蔽，频道与搜索结果生效',
      '搜索历史：最近搜索记录与一键清空',
      '频道自定义：首页频道排序 / 隐藏 / 恢复默认',
      '资料编辑：个人签名修改',
      '改密码：账号与安全子页，成功后重新登录',
      '检查更新：对接 GitHub Release，可跳转下载',
      '保存图片到相册：SaveButton 安全控件（1.3.0 起由系统拖拽替代）'
    ]
  },
  {
    version: '1.1.0',
    date: '2026-08-13',
    items: [
      '浏览历史增强：封面缩略图、阅读时间显示',
      '浏览历史支持单条删除与一键清空（原生确认框）',
      '浏览历史异步加载修复',
      '全部设置持久化：显示模式/档位/自动签到/防截屏/下载/DNS 重启保留',
      '设置下拉框改为原生菜单，选项即时同步',
      '进入章节自动恢复上次阅读页（页级进度）',
      '阅读器多项修复：翻页手势、页码显示、底部工具栏'
    ]
  },
  {
    version: '1.0.10',
    date: '2026-08-12',
    items: [
      '阅读模式切换保留当前阅读位置',
      '修复上一话/下一话按钮点击无效',
      '本地离线阅读同样保存进度与历史记录',
      '阅读器底部工具栏恢复悬浮毛玻璃（position+offset 定位）',
      '修复进入章节页码错乱与单页模式手势翻页',
      '离线场景翻话按钮按已下载任务计算话数'
    ]
  },
  {
    version: '1.0.9',
    date: '2026-08-11',
    items: [
      '防截屏修复：补声明 ohos.permission.PRIVACY_WINDOW 权限（安装即授予）',
      '防截屏开关提示文案修正',
      '评论弹窗改用系统原生标题（关闭按钮不重叠）',
      '评论失败提示中文化（等级不足说明）',
      '阅读器设置面板改为系统 bindSheet 弹窗样式'
    ]
  },
  {
    version: '1.0.8',
    date: '2026-08-10',
    items: [
      '首页顶部遮罩恢复整层覆盖（状态栏区域也带玻璃遮罩）',
      '退出登录改为紧贴菜单卡下方，与上部卡片平齐'
    ]
  },
  {
    version: '1.0.7',
    date: '2026-08-09',
    items: [
      'DNS 优化全面升级：分流线路拉取 + IP 握手测速 + 应用最低延迟 + 线路点选',
      'DNS 选择实时生效（API 与图片各自直连所选 IP），支持重置默认',
      '防截屏改为启动即应用 + 开关即时生效（主窗口单例）',
      '退出登录位置上移'
    ]
  },
  {
    version: '1.0.6',
    date: '2026-08-08',
    items: [
      '设置页统一规格重建：分区标题、图标、行高与字号全部一致',
      '显示模式改为统一下拉框，沉浸光感/常规/下载卡片规范化',
      '底部导航下移、顶部遮罩收窄、退出登录位置上移',
      '修复设置内嵌套子页返回后导航栏提前出现的问题'
    ]
  },
  {
    version: '1.0.5',
    date: '2026-08-07',
    items: [
      '设置新增常规项：自动签到 / 防截屏 / 清理图片缓存',
      '新增存储与空间管理（下载占用、缓存占用、一键清理）',
      '新增 DNS 优化（直连 IP 池查看、强制刷新、恢复默认）',
      '退出登录移至页面底部，底部导航位置微调'
    ]
  },
  {
    version: '1.0.4',
    date: '2026-08-06',
    items: [
      '修复所有滚动页面内容垂直居中问题',
      '首页/我的/收藏/搜索/频道/详情等页面内容统一从顶部排布'
    ]
  },
  {
    version: '1.0.3',
    date: '2026-08-06',
    items: [
      '设置子页全部改为从顶部排布',
      '底部导航与卡片全面接入沉浸光感材质（档位可调）',
      '关于页：更新日志折叠卡片 + 隐私政策',
      '评论点赞 / 回复 / 发表，子回复展开',
      '阅读器：横竖屏锁定 + 亮度调节',
      '下载：仅 WiFi 下载、并发数设置、失败重试、本地离线阅读'
    ]
  },
  {
    version: '1.0.2',
    date: '2026-08-05',
    items: [
      '频道筛选：主题/排除主题/状态/话数/页数五组筛选',
      '签到状态记忆，防止重复签到',
      '关于弹窗与更新日志（可折叠 + 进场动画）',
      '深浅色模式切换',
      '首页/详情/阅读器沉浸式体验优化'
    ]
  },
  {
    version: '1.0.1',
    date: '2026-08-04',
    items: [
      '首页频道：推荐/排行榜/最近更新/随机本子等 45 个频道',
      '漫画详情：详情/章节/评论三 Tab + 相关推荐 + 收藏点赞',
      '阅读器：五种阅读模式 + 沉浸工具栏 + 设置面板',
      '我的：收藏/历史/通知/我的评论/设置',
      '搜索：关键词推荐 + 高级搜索 + 排序'
    ]
  },
  {
    version: '1.0.0',
    date: '2026-08-04',
    items: [
      '初始版本',
      '账号登录与资料同步（头像/昵称/等级/签名）',
      '图片加载：自有网络栈 + 缓存 + 镜像回退'
    ]
  }
];

/** 菜单项 */
interface MenuItemData {
  icon: Resource;
  label: string;
  page: string;
}

/** 沉浸光感档位选项 */
interface MaterialOption {
  value: string;
  label: string;
}

const MATERIAL_OPTIONS: MaterialOption[] = [
  { value: 'EXQUISITE', label: '强' },
  { value: 'GENTLE', label: '均衡' },
  { value: 'SMOOTH', label: '弱' },
  { value: 'ADAPTIVE', label: '自适应' }
];

/** 显示模式选项 */
const COLOR_MODE_OPTIONS: MaterialOption[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' }
];

@Component
struct ProfilePage {
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  /** 登录态是否已确定：未置位前不渲染「未登录」这类确定性文案（防御性） */
  @StorageProp('auth_resolved') authResolved: boolean = false;
  // 主题强调色：哔咔粉（保留哔咔主题色）
  private accentColor: ResourceColor = $r('app.color.bika_primary');
  /** 强调色 hex（沉浸光感点光用） */
  private accentHex: string = '#FF7CA8';
  @State profileError: string = '';
  @State userName: string = '';
  @State avatarUrl: string = '';
  @State userTitle: string = '';
  @State userLevel: number = 0;
  @State userExp: number = 0;
  @State slogan: string = '';
  @State profileLoaded: boolean = false;
  private apiService: ApiService = ApiService.getInstance();
  private cache: CacheManager | null = null;
  private stack: NavPathStack = new NavPathStack();
  private settingsScroller: Scroller = new Scroller();
  private aboutScroller: Scroller = new Scroller();
  private storageScroller: Scroller = new Scroller();
  private dnsScroller: Scroller = new Scroller();
  private blockedTagsScroller: Scroller = new Scroller();
  private profileEditScroller: Scroller = new Scroller();
  private accountScroller: Scroller = new Scroller();
  private favouritesScroller: Scroller = new Scroller();
  private historyScroller: Scroller = new Scroller();
  private downloadsScroller: Scroller = new Scroller();
  private notificationsScroller: Scroller = new Scroller();
  private commentsScroller: Scroller = new Scroller();
  // 保持全屏，由标题栏主动避让状态栏，使渐变模糊连续覆盖顶部安全区。
  // 留白放在滚动内容内，首屏避开标题，滚动时仍可从标题栏下穿过。
  private subpageContentTop: number = 56 + 8;

  // ── 子页面数据状态 ──
  @State favComics: ComicViewModel[] = [];
  @State favSort: string = 'dd';
  @State favPage: number = 1;
  @State favHasMore: boolean = false;
  @State favLoading: boolean = false;
  @State notifications: BikaNotification[] = [];
  @State notifLoading: boolean = false;
  @State myComments: BikaComment[] = [];
  @State commentsLoading: boolean = false;
  @State historyItems: HistoryItem[] = [];
  @StorageLink('bika_color_mode') colorMode: string = 'system';
  /** 下载设置 */
  @State downloadWifiOnly: boolean = false;
  @State downloadConcurrent: number = 1;
  /** 常规设置 */
  @State autoPunch: boolean = false;
  @State secureScreen: boolean = false;
  /** 桌面卡片设置（与 CacheManager 的 setting_ 前缀约定一致） */
  @State widgetShowRealData: boolean = true;
  @State widgetShowCover: boolean = true;
  /** 存储占用（字节） */
  @State downloadSizeBytes: number = 0;
  @State cacheSizeBytes: number = 0;
  @State storageRefreshing: boolean = false;
  /** 屏蔽标签 */
  @State blockedTags: string[] = [];
  @State keywordTags: string[] = [];
  @State blockedLoading: boolean = false;
  /** 资料编辑 */
  @State editSlogan: string = '';
  @State editBirthday: string = '2000-01-01';
  @State editGender: string = 'm';
  @State editSaving: boolean = false;
  /** 改密码 */
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmNewPassword: string = '';
  @State passwordSaving: boolean = false;
  /** 检查更新 */
  @State checkingUpdate: boolean = false;
  @State updateVersion: string = '';
  @State updateBody: string = '';
  @State updateUrl: string = '';
  /** DNS 分流线路状态 */
  @State dnsLines: Map<string, DnsIpEntry[]> = new Map();
  @State dnsFetching: boolean = false;
  @State dnsTesting: boolean = false;
  @State dnsError: string = '';
  @State dnsApiIps: string[] = [];
  @State dnsImageIps: string[] = [];
  @State punching: boolean = false;
  @StorageLink('download_revision') @Watch('onDownloadChanged') downloadRevision: number = 0;
  /** 桌面卡片深链转交的「打开子页面」信号（IndexPage → 本页 NavPathStack） */
  @StorageLink('bika_open_subpage') @Watch('onSubpageSignalChanged') subpageSignal: string = '';
  /** 已消费的子页面信号时间戳，保证同一信号只打开一次 */
  private lastSubpageSignalTs: number = 0;
  @State downloadList: DownloadTask[] = [];
  @State punched: boolean = false;
  /** 关于弹窗（bindSheet） */
  @State showAboutSheet: boolean = false;
  @State expandedAboutVersion: string = '1.0.0';
  @State aboutEntered: boolean = false;
  /** 弹窗类型：0 关闭 1 更新日志 2 隐私政策 */
  @State aboutSheetKind: number = 0;
  /** 沉浸光感档位（与 IndexPage 页签联动） */
  @StorageLink('bika_material_level') materialLevel: string = 'EXQUISITE';
  /** 动画效果开关 */
  @StorageLink('bika_animations') animationsEnabled: boolean = true;
  /** 使用系统代理（规则模式 VPN） */
  @StorageLink('bika_use_proxy') useProxy: boolean = false;

  /** 菜单（点击进入子页面） */
  private menuItems: MenuItemData[] = [
    { icon: $r('sys.symbol.heart'), label: '我的收藏', page: 'favourites' },
    { icon: $r('sys.symbol.clock'), label: '浏览历史', page: 'history' },
    { icon: $r('sys.symbol.square_and_arrow_down'), label: '我的下载', page: 'downloads' },
    { icon: $r('sys.symbol.bell'), label: '通知', page: 'notifications' },
    { icon: $r('sys.symbol.message'), label: '我的评论', page: 'comments' },
    { icon: $r('sys.symbol.gearshape'), label: '设置', page: 'settings' }
  ];

  aboutToAppear(): void {
    AppStorage.set('isLoggedIn', this.apiService.isLoggedIn());
    this.downloadWifiOnly = DownloadManager.getInstance().getWifiOnly();
    this.downloadConcurrent = DownloadManager.getInstance().getMaxConcurrent();
    this.autoPunch = AppStorage.get<boolean>('bika_auto_punch') === true;
    this.secureScreen = AppStorage.get<boolean>('bika_secure_screen') === true;
    this.applySecureScreen();
    if (this.apiService.isLoggedIn()) {
      this.loadProfile();
    }
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
      // 与卡片侧 WidgetData 保持一致：默认开启。兜底必须是 'true'，
      // 否则新装 / 升级后卡片已经在显示真实内容与封面，设置页却显示关闭，
      // 用户第一次拨动是空操作（写入 true 而本就是 true）却提示已保存。
      this.widgetShowRealData = cache.getSetting('widget_show_real_data', 'true') === 'true';
      this.widgetShowCover = cache.getSetting('widget_show_cover', 'true') === 'true';
    });
    // 冷启动时页面可能晚于信号创建，@Watch 不会补发，这里主动检查一次
    this.consumeSubpageSignal();
  }

  /** 登录态变化：登录成功自动拉取资料 */
  onLoginStateChanged(): void {
    if (this.isLoggedIn) {
      this.loadProfile();
    }
  }

  /** 拉取并展示用户资料 */
  async loadProfile(): Promise<void> {
    this.profileError = '';
    try {
      let user = await this.apiService.getUserProfile();
      this.userName = user.name || '';
      this.userTitle = user.title || '';
      this.userLevel = user.level ?? 0;
      this.userExp = user.exp ?? 0;
      this.slogan = user.slogan || '';
      this.editSlogan = user.slogan || '';
      this.editBirthday = user.birthday || '2000-01-01';
      this.editGender = user.gender || 'm';
      this.punched = !!user.isPunched;
      if (user.avatar && user.avatar.path) {
        this.avatarUrl = buildImageUrl(user.avatar);
        AppStorage.set('avatarUrl', this.avatarUrl);
      }
      this.profileLoaded = true;
      console.info('[ProfilePage] profile loaded: ' + this.userName + ' LV.' + this.userLevel);
      this.maybeAutoPunch();
    } catch (err) {
      this.profileError = (err as Error).message || '加载失败';
      console.warn('[ProfilePage] loadProfile failed: ' + this.profileError);
    }
  }

  /** 自动签到（开启后每天首次打开自动打卡，当天只签一次） */
  private async maybeAutoPunch(): Promise<void> {
    if (!this.autoPunch || this.punched || this.punching) {
      return;
    }
    let today = new Date();
    let day = today.getFullYear() + '-' + (today.getMonth() + 1) + '-' + today.getDate();
    if (AppStorage.get<string>('bika_last_punch_day') === day) {
      return;
    }
    this.punching = true;
    try {
      await this.apiService.punchIn();
      this.punched = true;
      AppStorage.set('bika_last_punch_day', day);
      showImmersiveToast({ message: '自动签到成功', duration: 1600 });
    } catch (err) {
      console.warn('[ProfilePage] auto punch failed: ' + JSON.stringify(err));
    } finally {
      this.punching = false;
    }
  }

  /** 应用防截屏开关（ArkUI 原生窗口 API，主窗口单例） */
  private applySecureScreen(): void {
    WindowHelper.applyPrivacyMode(this.secureScreen).catch((err: Error) => {
      console.warn('[ProfilePage] privacy mode failed: ' + JSON.stringify(err));
    });
  }

  /**
   * 桌面卡片设置变更：动态卡片会在下一次系统刷新或重新添加后生效。
   * 主应用拿不到 formId，这里只提示用户，不盲目调用 updateForm。
   */
  private notifyWidgetRefresh(): void {
    showImmersiveToast({ message: '设置已保存，请重新添加卡片或等待自动刷新', duration: 1800 });
  }

  /** 清理图片缓存（原生确认对话框） */
  private confirmClearImageCache(): void {
    showImmersiveDialog({
      title: '清理图片缓存',
      message: '将清除章节图片列表、列表页与分类缓存，不影响已下载的漫画。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清理', color: '#FF7CA8' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        ImageLoader.clearCache();
        CacheManager.getInstance().then((cache: CacheManager) => {
          let count = cache.clearImageCache();
          showImmersiveToast({ message: '已清除 ' + count + ' 项缓存', duration: 1600 });
        });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] clear cache dialog failed: ' + JSON.stringify(err));
    });
  }

  /** 刷新存储占用统计 */
  private refreshStorage(): void {
    this.storageRefreshing = true;
    this.downloadSizeBytes = DownloadManager.getInstance().getTotalSizeBytes();
    this.cacheSizeBytes = 0;
    try {
      let dir = getContext(this).preferencesDir;
      let files = fs.listFileSync(dir);
      for (let name of files) {
        try {
          this.cacheSizeBytes += fs.statSync(dir + '/' + name).size;
        } catch (err) {
        }
      }
    } catch (err) {
      console.warn('[ProfilePage] cache size calc failed: ' + JSON.stringify(err));
    }
    this.storageRefreshing = false;
  }

  /** 清空全部下载（原生确认对话框） */
  private confirmClearAllDownloads(): void {
    showImmersiveDialog({
      title: '清空全部下载',
      message: '将删除所有已下载漫画的本地文件，且不可恢复。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清空', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        DownloadManager.getInstance().clearAll();
        this.refreshStorage();
        showImmersiveToast({ message: '已清空全部下载', duration: 1600 });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] clear downloads dialog failed: ' + JSON.stringify(err));
    });
  }

  /** 线路显示名 */
  private dnsLineName(key: string): string {
    if (key === 'unicom') {
      return '联通分流线路';
    }
    if (key === 'telecom') {
      return '电信分流线路';
    }
    if (key === 'mobile') {
      return '移动分流线路';
    }
    if (key === 'overseas') {
      return '海外分流线路';
    }
    return key + ' 分流线路';
  }

  /** 按固定顺序返回线路 key */
  private dnsLineKeys(): string[] {
    let keys = Array.from(this.dnsLines.keys());
    let order = ['unicom', 'telecom', 'mobile', 'overseas'];
    keys.sort((a: string, b: string) => {
      let ia = order.indexOf(a);
      let ib = order.indexOf(b);
      if (ia >= 0 && ib >= 0) {
        return ia - ib;
      }
      if (ia >= 0) {
        return -1;
      }
      if (ib >= 0) {
        return 1;
      }
      return a.localeCompare(b);
    });
    return keys;
  }

  /** 读取已保存的 DNS 选择 */
  private loadDnsSelection(): void {
    try {
      let apiRaw = AppStorage.get<string>('bika_dns_api_ips') ?? '';
      let imageRaw = AppStorage.get<string>('bika_dns_image_ips') ?? '';
      this.dnsApiIps = apiRaw.length > 0 ? JSON.parse(apiRaw) as string[] : [];
      this.dnsImageIps = imageRaw.length > 0 ? JSON.parse(imageRaw) as string[] : [];
    } catch (err) {
      this.dnsApiIps = [];
      this.dnsImageIps = [];
    }
  }

  /** 应用并持久化 DNS 选择 */
  private applyDnsSelection(apiIps: string[], imageIps: string[]): void {
    this.dnsApiIps = apiIps.slice(0);
    this.dnsImageIps = imageIps.slice(0);
    AppStorage.setOrCreate('bika_dns_api_ips', JSON.stringify(apiIps));
    AppStorage.setOrCreate('bika_dns_image_ips', JSON.stringify(imageIps));
    CacheManager.getInstance().then(c => {
      c.saveSetting('dns_api_ips', JSON.stringify(apiIps));
      c.saveSetting('dns_image_ips', JSON.stringify(imageIps));
    });
    ApiRouteManager.getInstance().applyCustomDns(apiIps, imageIps);
    // 刷新列表选中态
    let newMap = new Map<string, DnsIpEntry[]>();
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      let newList: DnsIpEntry[] = [];
      if (list) {
        for (let e of list) {
          newList.push({
            ip: e.ip,
            line: e.line,
            domain: e.domain,
            latency: e.latency,
            selected: e.domain === 'picacomic.com' ? imageIps.indexOf(e.ip) >= 0 : apiIps.indexOf(e.ip) >= 0
          });
        }
      }
      newMap.set(k, newList);
    }
    this.dnsLines = newMap;
    showImmersiveToast({ message: 'DNS 选择已生效', duration: 1600 });
  }

  /** 获取线路并测速（双源拉取 + TCP 握手测速） */
  private async fetchAndTestDns(): Promise<void> {
    if (this.dnsFetching || this.dnsTesting) {
      return;
    }
    this.dnsFetching = true;
    this.dnsError = '';
    try {
      let lines = await DnsService.fetchLines(this.dnsApiIps, this.dnsImageIps);
      if (lines.size === 0) {
        this.dnsError = '未能获取到任何 IP，请检查网络连接。';
        this.dnsFetching = false;
        return;
      }
      this.dnsLines = lines;
      this.dnsFetching = false;
      await this.testAllDnsLatencies();
    } catch (err) {
      this.dnsError = (err as Error).message || '拉取 IP 列表失败';
      this.dnsFetching = false;
    }
  }

  /** 并发 6 路测速全部 IP */
  private async testAllDnsLatencies(): Promise<void> {
    this.dnsTesting = true;
    let all: DnsIpEntry[] = [];
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      if (list) {
        all = all.concat(list);
      }
    }
    let idx = 0;
    let worker = async (): Promise<void> => {
      while (idx < all.length) {
        let entry = all[idx];
        idx++;
        let latency = await DnsService.testLatency(entry.ip);
        let updated: DnsIpEntry = {
          ip: entry.ip,
          line: entry.line,
          domain: entry.domain,
          latency: latency,
          selected: entry.selected
        };
        let newMap = new Map<string, DnsIpEntry[]>();
        let mapKeys = Array.from(this.dnsLines.keys());
        for (let k of mapKeys) {
          let list = this.dnsLines.get(k);
          let newList: DnsIpEntry[] = [];
          if (list) {
            for (let e of list) {
              newList.push(e.ip === entry.ip ? updated : e);
            }
          }
          newMap.set(k, newList);
        }
        this.dnsLines = newMap;
      }
    };
    let workers: Promise<void>[] = [];
    for (let i = 0; i < 6; i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    this.dnsTesting = false;
  }

  /** 应用最低延迟 IP（API 与图片各自取最优） */
  private applyLowestLatencyDns(): void {
    let all: DnsIpEntry[] = [];
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      if (list) {
        all = all.concat(list);
      }
    }
    let bestApi = '';
    let bestApiLat = 999999;
    let bestImage = '';
    let bestImageLat = 999999;
    for (let e of all) {
      if (e.latency < 0) {
        continue;
      }
      if (e.domain === 'picaapi.picacomic.com' && e.latency < bestApiLat) {
        bestApi = e.ip;
        bestApiLat = e.latency;
      } else if (e.domain === 'picacomic.com' && e.latency < bestImageLat) {
        bestImage = e.ip;
        bestImageLat = e.latency;
      }
    }
    let apiIps = bestApi.length > 0 ? [bestApi] : this.dnsApiIps;
    let imageIps = bestImage.length > 0 ? [bestImage] : this.dnsImageIps;
    this.applyDnsSelection(apiIps, imageIps);
  }

  /** 选择某条线路 IP（同线路另一域名自动取最优） */
  private selectDnsIp(entry: DnsIpEntry): void {
    let newApi = this.dnsApiIps.slice(0);
    let newImage = this.dnsImageIps.slice(0);
    let lineList = this.dnsLines.get(entry.line);
    if (entry.domain === 'picacomic.com') {
      newImage = [entry.ip];
      if (lineList) {
        let apiList = lineList.filter(e => e.domain === 'picaapi.picacomic.com');
        let best = '';
        let bestLat = 999999;
        for (let e of apiList) {
          if (e.latency >= 0 && e.latency < bestLat) {
            best = e.ip;
            bestLat = e.latency;
          }
        }
        if (best.length === 0 && apiList.length > 0) {
          best = apiList[0].ip;
        }
        if (best.length > 0) {
          newApi = [best];
        }
      }
    } else {
      newApi = [entry.ip];
      if (lineList) {
        let imgList = lineList.filter(e => e.domain === 'picacomic.com');
        let best = '';
        let bestLat = 999999;
        for (let e of imgList) {
          if (e.latency >= 0 && e.latency < bestLat) {
            best = e.ip;
            bestLat = e.latency;
          }
        }
        if (best.length === 0 && imgList.length > 0) {
          best = imgList[0].ip;
        }
        if (best.length > 0) {
          newImage = [best];
        }
      }
    }
    this.applyDnsSelection(newApi, newImage);
  }

  /** 重置默认 DNS */
  private resetDns(): void {
    ApiRouteManager.getInstance().resetToDefault();
    ImageLoader.setCustomImageIps([]);
    this.dnsApiIps = [];
    this.dnsImageIps = [];
    AppStorage.setOrCreate('bika_dns_api_ips', '[]');
    AppStorage.setOrCreate('bika_dns_image_ips', '[]');
    CacheManager.getInstance().then(c => {
      c.saveSetting('dns_api_ips', '[]');
      c.saveSetting('dns_image_ips', '[]');
    });
    // 刷新选中态
    let newMap = new Map<string, DnsIpEntry[]>();
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      let newList: DnsIpEntry[] = [];
      if (list) {
        for (let e of list) {
          newList.push({ ip: e.ip, line: e.line, domain: e.domain, latency: e.latency, selected: false });
        }
      }
      newMap.set(k, newList);
    }
    this.dnsLines = newMap;
    showImmersiveToast({ message: '已恢复默认 DNS', duration: 1600 });
  }

  /** 延迟显示 */
  private dnsLatencyLabel(entry: DnsIpEntry): string {
    if (entry.latency === -2) {
      return '测量中…';
    }
    if (entry.latency < 0) {
      return '超时';
    }
    return entry.latency + ' ms';
  }

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

  onLogin(): void {
    if (!this.isLoggedIn) {
      router.pushUrl({ url: 'pages/LoginPage' });
    }
  }

  onLogout(): void {
    this.apiService.logout();
    this.isLoggedIn = false;
    try {
      showImmersiveToast({ message: '已退出登录', duration: 2000 });
    } catch (e) {
      console.error('[ProfilePage] toast error:', JSON.stringify(e));
    }
  }

  /** 签到 */
  async onPunchIn(): Promise<void> {
    if (this.punching) {
      return;
    }
    this.punching = true;
    try {
      await this.apiService.punchIn();
      this.punched = true;
      showImmersiveToast({ message: '签到成功', duration: 2000 });
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '签到失败', duration: 2000 });
    } finally {
      this.punching = false;
    }
  }

  /** 打开子页面：底部导航动画收缩隐藏 */
  private openSubpage(name: string): void {
    if (!this.isLoggedIn && name !== 'settings' && name !== 'downloads' && name !== 'about' && name !== 'storage' && name !== 'dns' && name !== 'blocked' && name !== 'profile_edit' && name !== 'account') {
      router.pushUrl({ url: 'pages/LoginPage' });
      return;
    }
    AppStorage.set('bika_subpage_open', true);
    this.stack.pushPathByName(name, '');
    // 应用接续：记录并发布「当前在哪个我的子页」
    AppStorage.setOrCreate(CONTINUATION_PROFILE_SUBPAGE_KEY, name);
    publishContinuationRoute(ROUTE_PROFILE_SUBPAGE, { subpage: name });
    if (name === 'favourites') {
      this.loadFavourites(true);
    } else if (name === 'notifications') {
      this.loadNotifications();
    } else if (name === 'comments') {
      this.loadMyComments();
    } else if (name === 'history') {
      this.loadHistory();
    } else if (name === 'downloads') {
      // 强制同步任务列表（单例异步加载完成后刷新）
      this.downloadList = DownloadManager.getInstance().getTasks();
      setTimeout(() => {
        DownloadManager.getInstance().notify();
      }, 60);
    } else if (name === 'blocked') {
      this.loadBlockedTags();
      this.loadKeywordTags();
    } else if (name === 'profile_edit') {
      this.editSlogan = this.slogan;
    }
  }

  /** 读取屏蔽标签与候选关键词 */
  private loadBlockedTags(): void {
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
      this.blockedTags = cache.loadBlockedTags();
    });
  }

  private async loadKeywordTags(): Promise<void> {
    if (this.blockedLoading) {
      return;
    }
    this.blockedLoading = true;
    try {
      this.keywordTags = await this.apiService.getKeywords();
    } catch (err) {
      console.warn('[ProfilePage] keywords failed: ' + JSON.stringify(err));
    } finally {
      this.blockedLoading = false;
    }
  }

  /** 切换屏蔽标签 */
  private toggleBlockedTag(tag: string): void {
    let arr = this.blockedTags.slice(0);
    let idx = arr.indexOf(tag);
    if (idx >= 0) {
      arr.splice(idx, 1);
    } else {
      arr.push(tag);
    }
    this.blockedTags = arr;
    AppStorage.set('bika_blocked_tags', JSON.stringify(arr));
    CacheManager.getInstance().then(c => {
      c.saveBlockedTags(arr);
    });
  }

  private closeSubpage(): void {
    this.stack.pop();
    // 只有完全退出子页面栈才恢复底部导航（设置→存储→返回时仍停留在设置页，导航保持隐藏）
    if (this.stack.size() === 0) {
      AppStorage.set('bika_subpage_open', false);
    }
    // 应用接续：同步「当前我的子页」描述符（退回根页则发布「我的」根页）
    if (this.stack.size() === 0) {
      AppStorage.setOrCreate(CONTINUATION_PROFILE_SUBPAGE_KEY, '');
      publishContinuationRoute(ROUTE_HOME, { tab: 1 });
    } else {
      let names: string[] = this.stack.getAllPathName();
      let top: string = names.length > 0 ? names[names.length - 1] : '';
      AppStorage.setOrCreate(CONTINUATION_PROFILE_SUBPAGE_KEY, top);
      publishContinuationRoute(ROUTE_PROFILE_SUBPAGE, { subpage: top });
    }
  }

  /** IndexPage 转交的子页面信号到达（桌面卡片深链：如 2*2 卡片无作品 id → 浏览历史） */
  onSubpageSignalChanged(): void {
    this.consumeSubpageSignal();
  }

  /** 打开 IndexPage 转交的子页面；同一 timestamp 只消费一次，避免与 aboutToAppear 重复 */
  private consumeSubpageSignal(): void {
    let raw: string = this.subpageSignal;
    if (raw.length === 0) {
      return;
    }
    let name: string = '';
    let ts: number = 0;
    try {
      let signal = JSON.parse(raw) as SubpageOpenSignal;
      name = signal.name ?? '';
      ts = signal.timestamp ?? 0;
    } catch (err) {
      console.error('[ProfilePage] subpage signal parse failed: ' + JSON.stringify(err));
      return;
    }
    if (name.length === 0 || ts <= this.lastSubpageSignalTs) {
      return;
    }
    this.lastSubpageSignalTs = ts;
    // 等页签切换与页面骨架渲染完成后再压栈
    setTimeout((): void => {
      this.openSubpage(name);
    }, 160);
  }

  // ── 子页面数据加载 ──
  private async loadFavourites(reset: boolean): Promise<void> {
    if (this.favLoading) {
      return;
    }
    this.favLoading = true;
    if (reset) {
      this.favPage = 1;
    }
    try {
      let result = await this.apiService.getFavourites(this.favSort, this.favPage);
      let vms = result.comics.map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      this.favComics = reset ? vms : this.favComics.concat(vms);
      this.favHasMore = this.favPage < result.pages;
    } catch (err) {
      console.warn('[ProfilePage] favourites failed: ' + JSON.stringify(err));
    } finally {
      this.favLoading = false;
    }
  }

  private async loadNotifications(): Promise<void> {
    if (this.notifLoading) {
      return;
    }
    this.notifLoading = true;
    try {
      this.notifications = await this.apiService.getNotifications(1);
    } catch (err) {
      console.warn('[ProfilePage] notifications failed: ' + JSON.stringify(err));
    } finally {
      this.notifLoading = false;
    }
  }

  private async loadMyComments(): Promise<void> {
    if (this.commentsLoading) {
      return;
    }
    this.commentsLoading = true;
    try {
      this.myComments = await this.apiService.getMyComments(1);
    } catch (err) {
      console.warn('[ProfilePage] my comments failed: ' + JSON.stringify(err));
    } finally {
      this.commentsLoading = false;
    }
  }

  private loadHistory(): void {
    // 缓存单例可能尚未就绪，异步读取后再刷新列表
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
      this.historyItems = cache.loadHistory();
    });
  }

  /** 历史时间显示 */
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

  /** 删除单条历史（原生确认框） */
  private confirmDeleteHistory(item: HistoryItem): void {
    showImmersiveDialog({
      title: '删除历史记录',
      message: '删除《' + item.title + '》的浏览记录？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        CacheManager.getInstance().then(cache => {
          cache.deleteHistoryItem(item.comicId);
          this.historyItems = cache.loadHistory();
        });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] delete history dialog failed: ' + JSON.stringify(err));
    });
  }

  /** 清空全部历史（原生确认框） */
  private confirmClearHistory(): void {
    showImmersiveDialog({
      title: '清空全部历史',
      message: '将删除所有浏览记录，且不可恢复。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清空', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        CacheManager.getInstance().then(cache => {
          cache.clearHistory();
          this.historyItems = [];
        });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] clear history dialog failed: ' + JSON.stringify(err));
    });
  }

  private onDownloadChanged(): void {
    this.downloadList = DownloadManager.getInstance().getTasks();
  }

  private setColorMode(mode: string): void {
    // StorageLink 赋值即同步 AppStorage，Menu 下拉显示实时刷新
    this.colorMode = mode;
    CacheManager.getInstance().then(c => c.saveSetting('color_mode', mode));
    let ctx = getContext(this).getApplicationContext();
    if (mode === 'dark') {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === 'light') {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  /** 沉浸光感档位（Select 辅助） */
  private labels(options: MaterialOption[]): string[] {
    return options.map((option: MaterialOption): string => option.label);
  }

  private selectOptions(options: MaterialOption[]): SelectOption[] {
    return this.labels(options).map((label: string): SelectOption => ({ value: label }));
  }

  private optionIndex(options: MaterialOption[], value: string): number {
    const index: number = options.findIndex((option: MaterialOption): boolean => option.value === value);
    return index < 0 ? 0 : index;
  }

  /** 应用材质档位（与 setColorMode 同款机制：赋值即同步 AppStorage + 持久化 + 全局修订号驱动重渲染） */
  private applyMaterialLevel(value: string): void {
    this.materialLevel = value;
    CacheManager.getInstance().then(c => c.saveSetting('material_level', value));
    // 修订号 +1：所有监听组件（含 IndexPage 的 HdsTabs key）立即重建应用新档位
    let rev = AppStorage.get<number>('bika_material_rev') ?? 0;
    AppStorage.setOrCreate('bika_material_rev', rev + 1);
  }

  private selectMaterial(index: number): void {
    const option: MaterialOption | undefined = MATERIAL_OPTIONS[index];
    if (option === undefined) {
      return;
    }
    this.applyMaterialLevel(option.value);
  }

  private selectColorModeOption(index: number): void {
    const option: MaterialOption | undefined = COLOR_MODE_OPTIONS[index];
    if (option === undefined) {
      return;
    }
    this.setColorMode(option.value);
  }

  /** 设置页统一下拉（原生 Menu；显示文字直接读 AppStorage，状态变化即时刷新） */
  @Builder
  settingSelect(options: MaterialOption[], storageKey: string, defaultValue: string,
    onSelect: (index: number) => void) {
    Row({ space: 4 }) {
      Text(this.labels(options)[this.optionIndex(options, AppStorage.get<string>(storageKey) ?? defaultValue)])
        .fontSize(15)
        .fontColor(COLOR_PRIMARY)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([COLOR_PRIMARY])
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .bindMenu(options.map((opt: MaterialOption, index: number): MenuElement => {
      return {
        value: opt.label,
        action: (): void => {
          onSelect(index);
        }
      };
    }))
  }

  // ── 用户卡 ──
  @Builder
  userCard() {
    Column({ space: 10 }) {
      Row() {
        if (this.avatarUrl.length > 0) {
          NetImage({ src: this.avatarUrl, fit: ImageFit.Cover, radius: 32, fillParent: true })
            .width(64)
            .height(64)
        } else {
          Image($r('app.media.ic_default_avatar'))
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
            .backgroundColor(COLOR_PLACEHOLDER)
        }

        Column({ space: 4 }) {
          Text(this.profileError.length > 0
            ? '用户信息加载失败'
            : (this.userName.length > 0 ? this.userName : 'Bika 用户'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 8 }) {
            Text('LV.' + this.userLevel)
              .fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY)
            if (this.userTitle.length > 0) {
              Text(this.userTitle)
                .fontSize(10)
                .fontColor(COLOR_PRIMARY)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(COLOR_PRIMARY_TINT)
                .border({ width: 1, color: COLOR_PRIMARY })
                .borderRadius(4)
            }
          }
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 16 })
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([COLOR_PRIMARY])
          .padding(6)
          .onClick(() => {
            this.openSubpage('profile_edit');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('经验 ' + this.userExp)
          .fontSize(11)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(COLOR_PRIMARY_TINT_2)
          .borderRadius(4)
        Text(this.slogan.length > 0 ? this.slogan : '这个人很懒，什么都没写')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 8 })

        Button(this.punched ? '已签到' : '签到', { type: ButtonType.Normal })
          .fontSize(12)
          .fontColor(this.punched ? COLOR_TEXT_SECONDARY : COLOR_WHITE)
          .backgroundColor(this.punched ? COLOR_PRIMARY_TINT : COLOR_PRIMARY)
          .borderRadius(14)
          .height(30)
          .padding({ left: 14, right: 14 })
          .enabled(!this.punching && !this.punched)
          .onClick(() => this.onPunchIn())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 账号与安全（我的页顶部账号区域）
      Divider()
        .margin({ top: 10, bottom: 2 })
      Row() {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(18)
          .fontColor([COLOR_TEXT_SECONDARY])
        Text('账号与安全')
          .fontSize(14)
          .fontColor(COLOR_TEXT_TITLE)
          .margin({ left: 10 })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([COLOR_TEXT_DISABLED])
      }
      .width('100%')
      .height(44)
      .onClick(() => {
        this.openSubpage('account');
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
  }

  /** 菜单列表（点击进入子页面） */
  @Builder
  menuList() {
    Column() {
      ForEach(this.menuItems, (item: MenuItemData, index: number) => {
        Row() {
          SymbolGlyph(item.icon)
            .fontSize(20)
            .fontColor([COLOR_TEXT_SECONDARY])
          Text(item.label)
            .fontSize(15)
            .fontColor(COLOR_TEXT_TITLE)
            .margin({ left: 12 })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([COLOR_TEXT_DISABLED])
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .onClick(() => this.openSubpage(item.page))
        if (index < this.menuItems.length - 1) {
          Divider().height(1).color(COLOR_DIVIDER).margin({ left: 48 })
        }
      }, (item: MenuItemData) => item.label)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    HdsNavigation(this.stack) {
      Column() {
        Scroll() {
          Column({ space: 12 }) {
            if (this.isLoggedIn) {
              this.userCard()
            } else {
              Row() {
                Image($r('app.media.ic_default_avatar'))
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .objectFit(ImageFit.Cover)
                Column({ space: 2 }) {
                  Text(this.authResolved ? '未登录' : '正在确认登录状态')
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text(this.authResolved ? '登录后同步收藏与评论' : ' ')
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 14 })
                .layoutWeight(1)

                if (this.authResolved) {
                  Button('登录', { type: ButtonType.Normal })
                    .fontSize(14)
                    .fontColor(COLOR_WHITE)
                    .backgroundColor(COLOR_PRIMARY)
                    .borderRadius(18)
                    .height(36)
                    .padding({ left: 20, right: 20 })
                    .onClick(() => this.onLogin())
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            }

            this.menuList()

            // 退出登录：紧跟菜单卡下方，与上部平齐
            if (this.isLoggedIn) {
              Row() {
                SymbolGlyph($r('sys.symbol.rectangle_portrait_on_rectangle_portrait'))
                  .fontSize(20)
                  .fontColor([COLOR_TEXT_SECONDARY])
                Text('退出登录')
                  .fontSize(15)
                  .fontColor(COLOR_LOGOUT_TEXT)
                  .margin({ left: 12 })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
              .onClick(() => this.onLogout())
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topSafeHeight + 16, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .backgroundColor(COLOR_BG)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAboutSheet, this.profileBottomSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: true,
      dragBar: false,
      // 仅更新提示统一系统表面；更新日志与隐私政策保留原有配置。
      backgroundColor: this.aboutSheetKind === 0 ? COLOR_BG : undefined,
      blurStyle: this.aboutSheetKind === 0 ? BlurStyle.NONE : undefined,
      borderWidth: this.aboutSheetKind === 0 ? 0 : undefined,
      systemMaterial: this.aboutSheetKind === 0 ? undefined : compatibleSheetMaterial(this.materialLevel),
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showAboutSheet = false;
        this.aboutEntered = false;
        this.aboutSheetKind = 0;
      }
    })
  }

  /** 底部弹窗统一分发（单 bindSheet 避免多实例互顶）：aboutSheetKind 0=更新 1=更新日志 2=隐私政策 */
  @Builder
  profileBottomSheet() {
    if (this.aboutSheetKind === 0) {
      this.updateSheet()
    } else {
      this.aboutSheet()
    }
  }

  /** 子页面注册 */
  @Builder
  pageMap(name: string) {
    if (name === 'favourites') {
      this.favouritesDestination()
    } else if (name === 'history') {
      this.historyDestination()
    } else if (name === 'downloads') {
      this.downloadsDestination()
    } else if (name === 'notifications') {
      this.notificationsDestination()
    } else if (name === 'comments') {
      this.commentsDestination()
    } else if (name === 'settings') {
      this.settingsDestination()
    } else if (name === 'about') {
      this.aboutDestination()
    } else if (name === 'storage') {
      this.storageDestination()
    } else if (name === 'dns') {
      this.dnsDestination()
    } else if (name === 'blocked') {
      this.blockedTagsDestination()
    } else if (name === 'profile_edit') {
      this.profileEditDestination()
    } else if (name === 'account') {
      this.accountDestination()
    }
  }

  /** 我的收藏 */
  @Builder
  favouritesDestination() {
    HdsNavDestination() {
      Scroll(this.favouritesScroller) {
        Column() {
        Row() {
          ForEach(SORT_OPTIONS, (item: SortOption) => {
            Text(item.label)
              .fontSize(13)
              .fontColor(this.favSort === item.key ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.favSort === item.key ? COLOR_PRIMARY : COLOR_CARD)
              .borderRadius(15)
              .margin({ right: 8 })
              .onClick(() => {
                if (this.favSort !== item.key) {
                  this.favSort = item.key;
                  this.loadFavourites(true);
                }
              })
          }, (item: SortOption) => item.key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

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
          .columnsGap(10)
          .rowsGap(12)
          .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafeHeight + 76 })
        }
        .width('100%')
        .padding({ top: this.topSafeHeight + this.subpageContentTop - 8 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onReachEnd(() => {
        if (this.favHasMore && !this.favLoading) {
          this.favPage++;
          this.loadFavourites(false);
        }
      })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '我的收藏' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.favouritesScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 浏览历史 */
  @Builder
  historyDestination() {
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
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '浏览历史' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.historyScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 我的下载（独立组件订阅实时刷新） */
  @Builder
  downloadsDestination() {
    HdsNavDestination() {
      DownloadListView({ scroller: this.downloadsScroller })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '我的下载' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.downloadsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 通知 */
  @Builder
  notificationsDestination() {
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
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '通知' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.notificationsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 我的评论 */
  @Builder
  commentsDestination() {
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
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '我的评论' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.commentsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 设置 */
  @Builder
  settingsDestination() {
    HdsNavDestination() {
      Scroll(this.settingsScroller) {
        Column({ space: 14 }) {
          Text('外观')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('显示模式')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('跟随系统、浅色或深色')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              this.settingSelect(COLOR_MODE_OPTIONS, 'bika_color_mode', 'system', (index: number): void => {
                this.selectColorModeOption(index);
              })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('沉浸光感')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.paintbrush'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('档位')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('底部导航栏的材质强度')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              MaterialLevelSelect()
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('常规')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.wand_and_stars'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('动画效果')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('按钮动效、卡片按压、阅读器过渡等')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.animationsEnabled })
                .selectedColor(COLOR_PRIMARY)
                .onChange((checked: boolean) => {
                  this.animationsEnabled = checked;
                  AppStorage.setOrCreate('bika_animations', checked);
                  CacheManager.getInstance().then(c => c.saveSetting('animations', checked ? 'true' : 'false'));
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('自动签到')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('每天首次打开自动签到')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoPunch })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.autoPunch = isOn;
                  AppStorage.setOrCreate('bika_auto_punch', isOn);
                  CacheManager.getInstance().then(c => c.saveSetting('auto_punch', isOn ? 'true' : 'false'));
                  if (isOn) {
                    this.maybeAutoPunch();
                  }
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.eye_slash'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('防截屏')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('截屏与录屏时隐藏内容')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.secureScreen })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.secureScreen = isOn;
                  AppStorage.setOrCreate('bika_secure_screen', isOn);
                  CacheManager.getInstance().then(c => c.saveSetting('secure_screen', isOn ? 'true' : 'false'));
                  this.applySecureScreen();
                  showImmersiveToast({
                    message: isOn ? '已开启防截屏，将禁止截屏/录屏功能' : '已关闭防截屏，恢复截屏/录屏功能',
                    duration: 1600
                  });
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('清理图片缓存')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('清理章节图片、列表与分类缓存')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.confirmClearImageCache())

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.externaldrive'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('存储与空间')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('下载、缓存占用与清理')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('storage'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('DNS 优化')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('直连与分流线路优化')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('dns'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.nosign'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('屏蔽标签')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('隐藏含指定标签的漫画')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('blocked'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('账号与安全')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('修改后需要重新登录')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('account'))
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('下载')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('仅 WiFi 下载')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('非 WiFi 时任务自动排队')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.downloadWifiOnly })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.downloadWifiOnly = isOn;
                  DownloadManager.getInstance().setWifiOnly(isOn);
                  if (isOn && !DownloadManager.getInstance().isWifiNow()) {
                    showImmersiveToast({ message: '当前非 WiFi 网络，任务将等待 WiFi', duration: 2000 });
                  }
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('最大并发数')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('同时下载的章节数')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              ForEach([1, 2, 3, 5], (n: number) => {
                Text('' + n)
                  .fontSize(13)
                  .fontColor(this.downloadConcurrent === n ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
                  .textAlign(TextAlign.Center)
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor(this.downloadConcurrent === n ? COLOR_PRIMARY : COLOR_PRIMARY_TINT)
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.downloadConcurrent = n;
                    DownloadManager.getInstance().setMaxConcurrent(n);
                  })
              }, (n: number) => '' + n)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('桌面卡片')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.rectangle_portrait_on_rectangle_portrait'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('显示真实内容')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('卡片展示作品名与阅读进度')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.widgetShowRealData })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.widgetShowRealData = isOn;
                  CacheManager.getInstance().then(c => c.saveSetting('widget_show_real_data', isOn ? 'true' : 'false'));
                  this.notifyWidgetRefresh();
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('显示封面')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('卡片展示作品封面')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.widgetShowCover })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.widgetShowCover = isOn;
                  CacheManager.getInstance().then(c => c.saveSetting('widget_show_cover', isOn ? 'true' : 'false'));
                  this.notifyWidgetRefresh();
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('应用')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('检查更新')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text(this.checkingUpdate ? '正在检查…' : '检查是否有新版本')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.checkUpdate())

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.questionmark_circle'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('关于')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('应用信息、更新日志与隐私政策')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.openSubpage('about');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .backgroundColor(COLOR_BG)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '设置' } },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .backgroundColor(COLOR_BG)
    .bindToScrollable([this.settingsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 关于子页 */
  @Builder
  aboutDestination() {
    HdsNavDestination() {
      Scroll(this.aboutScroller) {
        Column({ space: 14 }) {
          Text('应用信息')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
          Column({ space: 6 }) {
            Text('Bika')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('HarmonyOS 原生客户端')
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
            Text('版本 ' + CHANGELOG_ENTRIES[0].version)
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('文档')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('更新日志')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('查看版本功能变化')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
          .onClick(() => {
            this.openChangelog();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('隐私政策')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('账户、资料、文件与网络说明')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
          .onClick(() => {
            this.openPrivacyPolicy();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })

          Text('开源')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.link'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('GitHub 项目主页')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('github.com/LoMoCatAp/Bika-HarmonyOS')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
          .onClick(() => {
            this.openExternalLink('https://github.com/LoMoCatAp/Bika-HarmonyOS');
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '关于' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.aboutScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 存储与空间子页 */
  @Builder
  storageDestination() {
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
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '存储与空间' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
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

  /** DNS 直连与分流优化子页 */
  @Builder
  dnsDestination() {
    HdsNavDestination() {
      Scroll(this.dnsScroller) {
        Column({ space: 12 }) {
        if (this.dnsFetching) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(COLOR_PRIMARY)
            Text('正在获取分流线路…')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .height(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_PRIMARY_TINT)
        } else if (this.dnsTesting) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(COLOR_PRIMARY)
            Text('正在测量 IP 握手延迟…')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .height(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_PRIMARY_TINT)
        }
            // 系统代理开关
            Column({ space: 0 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.dot_radiowaves'))
                  .fontSize(20)
                  .fontColor([this.accentColor])
                Column({ space: 3 }) {
                  Text('使用系统代理')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text('规则模式 VPN（常见代理客户端）')
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.useProxy })
                  .selectedColor(COLOR_PRIMARY)
                  .onChange((checked: boolean) => {
                    this.useProxy = checked;
                    ApiService.setUseSystemProxy(checked);
                    CacheManager.getInstance().then(c => c.saveSetting('use_system_proxy', checked ? 'true' : 'false'));
                    showImmersiveToast({
                      message: checked ? '已切换系统代理：请求由代理按域名分流' : '已切回应用内 DNS 直连',
                      duration: 2000
                    });
                  })
              }
              .width('100%')
              .height(58)
              .padding({ left: 16, right: 16 })
              Text('在代理工具的"设置"中打开"允许来自局域网的连接/系统代理"，本开关开启后所有请求改为域名直发，由代理按规则分流，无需全局模式。')
                .fontSize(12)
                .fontColor(COLOR_TEXT_HINT)
                .lineHeight(18)
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 10 })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

            // 当前生效 IP
            Column({ space: 8 }) {
              Text('当前生效的直连 IP')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT_TITLE)
                .width('100%')
              Row() {
                Column({ space: 2 }) {
                  Text('API 线路')
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_SECONDARY)
                  Text(this.dnsApiIps.length > 0 ? this.dnsApiIps.join(', ') : '默认系统解析')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Column({ space: 2 }) {
                  Text('图片存储')
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_SECONDARY)
                  Text(this.dnsImageIps.length > 0 ? this.dnsImageIps.join(', ') : '默认系统解析')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 16 })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(16)
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

            // 操作按钮
            Row({ space: 12 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(16)
                    .fontColor([COLOR_WHITE])
                  Text('获取并测速')
                    .fontSize(14)
                    .fontColor(COLOR_WHITE)
                }
              }
              .layoutWeight(1)
              .height(42)
              .backgroundColor(COLOR_PRIMARY)
              .borderRadius(21)
              .enabled(!this.dnsFetching && !this.dnsTesting)
              .onClick(() => {
                this.fetchAndTestDns();
              })

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.bolt'))
                    .fontSize(16)
                    .fontColor([COLOR_PRIMARY])
                  Text('应用最低延迟')
                    .fontSize(14)
                    .fontColor(COLOR_PRIMARY)
                }
              }
              .layoutWeight(1)
              .height(42)
              .backgroundColor(COLOR_PRIMARY_TINT)
              .borderRadius(21)
              .enabled(!this.dnsFetching && !this.dnsTesting && this.dnsLines.size > 0)
              .onClick(() => {
                this.applyLowestLatencyDns();
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            // 错误提示
            if (this.dnsError.length > 0) {
              Text(this.dnsError)
                .fontSize(13)
                .fontColor('#C62828')
                .width('100%')
                .padding(12)
                .backgroundColor('#FDECEC')
                .borderRadius(12)
            }

            // 分流线路列表
            ForEach(this.dnsLineKeys(), (lineKey: string) => {
              Column({ space: 8 }) {
                Text(this.dnsLineName(lineKey))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                  .width('100%')
                ForEach(this.dnsLines.get(lineKey) as DnsIpEntry[], (entry: DnsIpEntry) => {
                  Row({ space: 8 }) {
                    Text(entry.ip)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontFamily('monospace')
                      .fontColor(COLOR_TEXT_TITLE)
                    Text(entry.domain === 'picacomic.com' ? '图片' : 'API')
                      .fontSize(10)
                      .fontColor(entry.domain === 'picacomic.com' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(entry.domain === 'picacomic.com' ? COLOR_PRIMARY_TINT : COLOR_INPUT_BG)
                      .borderRadius(4)
                    Blank()
                    Text(this.dnsLatencyLabel(entry))
                      .fontSize(12)
                      .fontColor(entry.latency < 0 ? '#C62828' : COLOR_TEXT_SECONDARY)
                    if (entry.selected) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle'))
                        .fontSize(18)
                        .fontColor([COLOR_PRIMARY])
                    }
                  }
                  .width('100%')
                  .padding(14)
                  .backgroundColor(entry.selected ? COLOR_PRIMARY_TINT : Color.Transparent)
                  .borderRadius(12)
                  .border({ width: entry.selected ? 2 : 1, color: entry.selected ? COLOR_PRIMARY : COLOR_DIVIDER })
                  .onClick(() => this.selectDnsIp(entry))
                }, (entry: DnsIpEntry) => entry.domain + '_' + entry.ip)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .margin({ top: 4 })
            }, (lineKey: string) => lineKey)

            if (this.dnsLines.size === 0 && !this.dnsFetching) {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(36)
                  .fontColor([COLOR_TEXT_DISABLED])
                Text('尚未获取分流线路')
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_HINT)
                Text('点击「获取并测速」拉取可用的直连 IP')
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_HINT)
              }
              .width('100%')
              .padding({ top: 40, bottom: 20 })
              .alignItems(HorizontalAlign.Center)
            }

            // 重置默认
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(20)
                .fontColor([COLOR_TEXT_SECONDARY])
              Text('重置默认')
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .margin({ left: 12 })
                .layoutWeight(1)
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => this.resetDns())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: 'DNS 直连与分流优化' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.dnsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
    .onShown(() => {
      this.loadDnsSelection();
    })
  }

  /** 屏蔽标签子页 */
  @Builder
  blockedTagsDestination() {
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
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '屏蔽标签' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.blockedTagsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 资料编辑子页 */
  @Builder
  profileEditDestination() {
    HdsNavDestination() {
      Scroll(this.profileEditScroller) {
          Column({ space: 12 }) {
            Column() {
              Text('签名')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '写点什么介绍自己…', text: this.editSlogan })
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_PLACEHOLDER)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.editSlogan = v;
                })

              Button(this.editSaving ? '保存中…' : '保存', { type: ButtonType.Normal })
                .fontSize(15)
                .fontColor(COLOR_WHITE)
                .backgroundColor(this.editSaving ? COLOR_TEXT_HINT : COLOR_PRIMARY)
                .borderRadius(22)
                .height(44)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 20 })
                .enabled(!this.editSaving)
                .onClick(() => {
                  this.saveProfileEdit();
                })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .padding({ bottom: 16 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '编辑资料' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.profileEditScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 账号与安全子页（改密码） */
  @Builder
  accountDestination() {
    HdsNavDestination() {
      Scroll(this.accountScroller) {
          Column({ space: 12 }) {
            Column() {
              Text('当前密码')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '请输入当前密码', text: this.oldPassword })
                .type(InputType.Password)
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_TEXT_SECONDARY)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.oldPassword = v;
                })
              Text('新密码')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '5-20 位，需包含数字、字母与符号', text: this.newPassword })
                .type(InputType.Password)
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_TEXT_SECONDARY)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.newPassword = v;
                })
              Text('确认新密码')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '再次输入新密码', text: this.confirmNewPassword })
                .type(InputType.Password)
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_TEXT_SECONDARY)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.confirmNewPassword = v;
                })
              Button(this.passwordSaving ? '提交中…' : '修改密码', { type: ButtonType.Normal })
                .fontSize(15)
                .fontColor(COLOR_WHITE)
                .backgroundColor(this.passwordSaving ? COLOR_TEXT_HINT : COLOR_PRIMARY)
                .borderRadius(22)
                .height(44)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 20 })
                .enabled(!this.passwordSaving)
                .onClick(() => {
                  this.submitPasswordChange();
                })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .padding({ bottom: 16 })

            Text('修改成功后需要重新登录。')
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(false)
    .titleBar({
      content: { title: { mainTitle: '账号与安全' } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.accountScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 保存资料编辑 */
  private async saveProfileEdit(): Promise<void> {
    if (this.editSaving) {
      return;
    }
    this.editSaving = true;
    try {
      await this.apiService.updateProfile(this.editSlogan);
      this.slogan = this.editSlogan;
      showImmersiveToast({ message: '资料已更新', duration: 1600 });
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '保存失败', duration: 2000 });
    } finally {
      this.editSaving = false;
    }
  }

  /** 提交修改密码 */
  private async submitPasswordChange(): Promise<void> {
    if (this.oldPassword.length === 0) {
      showImmersiveToast({ message: '请输入当前密码', duration: 1600 });
      return;
    }
    if (this.newPassword.length < 5 || this.newPassword.length > 20) {
      showImmersiveToast({ message: '新密码需 5-20 位', duration: 1600 });
      return;
    }
    if (!/[0-9]/.test(this.newPassword) || !/[a-zA-Z]/.test(this.newPassword) || !/[^0-9a-zA-Z]/.test(this.newPassword)) {
      showImmersiveToast({ message: '新密码需包含数字、字母与符号', duration: 2000 });
      return;
    }
    if (this.newPassword !== this.confirmNewPassword) {
      showImmersiveToast({ message: '两次输入的新密码不一致', duration: 1600 });
      return;
    }
    if (this.passwordSaving) {
      return;
    }
    this.passwordSaving = true;
    try {
      await this.apiService.changePassword(this.oldPassword, this.newPassword);
      showImmersiveToast({ message: '密码已修改，请重新登录', duration: 2000 });
      this.apiService.logout();
      this.isLoggedIn = false;
      router.pushUrl({ url: 'pages/LoginPage' });
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '修改失败', duration: 2000 });
    } finally {
      this.passwordSaving = false;
    }
  }

  /** 检查更新（GitHub Release） */
  private async checkUpdate(): Promise<void> {
    if (this.checkingUpdate) {
      return;
    }
    this.checkingUpdate = true;
    let request = http.createHttp();
    try {
      let response = await request.request(
        'https://api.github.com/repos/LoMoCatAp/Bika-HarmonyOS/releases/latest', {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      if (response.responseCode !== 200) {
        showImmersiveToast({ message: '检查更新失败 (HTTP ' + response.responseCode + ')', duration: 2000 });
        return;
      }
      let data = JSON.parse(response.result as string) as Record<string, Object>;
      let tag = String(data['tag_name'] ?? '');
      let version = tag.startsWith('v') ? tag.substring(1) : tag;
      let current = AppStorage.get<string>('bika_current_version') ?? '1.1.0';
      if (version.length > 0 && version !== current) {
        this.updateVersion = version;
        this.updateBody = String(data['body'] ?? '');
        this.updateUrl = String(data['html_url'] ?? '');
        this.aboutSheetKind = 0;
        this.showAboutSheet = true;
      } else {
        showImmersiveToast({ message: '当前已是最新版本 v' + current, duration: 2000 });
      }
    } catch (err) {
      showImmersiveToast({ message: '检查更新失败：' + (err as Error).message, duration: 2000 });
    } finally {
      this.checkingUpdate = false;
    }
  }

  /** Markdown 正文 → 纯文本块（原生无 Markdown 组件，做轻量转换） */
  private markdownLines(): UpdateBlock[] {
    let blocks: UpdateBlock[] = [];
    let raw = this.updateBody.length > 0 ? this.updateBody : '点击「去下载」前往下载页面';
    let lines = raw.split('\n');
    for (let line of lines) {
      let t = line.trim();
      if (t.length === 0 || t === '---') {
        continue;
      }
      if (t.startsWith('###')) {
        blocks.push({ kind: 'h3', text: t.substring(3).trim() });
      } else if (t.startsWith('##')) {
        blocks.push({ kind: 'h2', text: t.substring(2).trim() });
      } else if (t.startsWith('# ')) {
        blocks.push({ kind: 'h1', text: t.substring(2).trim() });
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        blocks.push({ kind: 'bullet', text: t.substring(2).trim() });
      } else {
        blocks.push({ kind: 'text', text: t });
      }
    }
    return blocks;
  }

  /** 行内 **加粗** 拆段 */
  private boldRuns(text: string): MdRun[] {
    let runs: MdRun[] = [];
    let rest = text;
    let bold = false;
    while (rest.length > 0) {
      let idx = rest.indexOf('**');
      if (idx < 0) {
        runs.push({ text: rest, bold: bold });
        break;
      }
      if (idx > 0) {
        runs.push({ text: rest.substring(0, idx), bold: bold });
      }
      rest = rest.substring(idx + 2);
      bold = !bold;
    }
    return runs;
  }

  /** 更新弹窗（Markdown 适配渲染） */
  @Builder
  updateSheet() {
    Column({ space: 0 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6, bottom: 4 })
      Text('发现新版本 v' + this.updateVersion)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 10 })
      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.markdownLines(), (block: UpdateBlock) => {
            if (block.kind === 'h2') {
              Text() {
                ForEach(this.boldRuns(block.text), (run: MdRun) => {
                  Span(run.text)
                    .fontSize(15)
                    .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Bold)
                    .fontColor(COLOR_TEXT_TITLE)
                }, (run: MdRun) => run.text + '_' + (run.bold ? '1' : '0'))
              }
              .width('100%')
              .margin({ top: 10, bottom: 2 })
            } else if (block.kind === 'h3') {
              Text(block.text)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
                .width('100%')
                .margin({ top: 8, bottom: 2 })
            } else if (block.kind === 'bullet') {
              Row({ space: 6 }) {
                Text('•')
                  .fontSize(14)
                  .fontColor(COLOR_PRIMARY)
                Text() {
                  ForEach(this.boldRuns(block.text), (run: MdRun) => {
                    Span(run.text)
                      .fontSize(14)
                      .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(COLOR_TEXT_TITLE)
                  }, (run: MdRun) => run.text + '_' + (run.bold ? '1' : '0'))
                }
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .margin({ top: 2, bottom: 2 })
            } else {
              Text() {
                ForEach(this.boldRuns(block.text), (run: MdRun) => {
                  Span(run.text)
                    .fontSize(14)
                    .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }, (run: MdRun) => run.text + '_' + (run.bold ? '1' : '0'))
              }
              .width('100%')
              .lineHeight(21)
            }
          }, (block: UpdateBlock, index: number) => index + '_' + block.kind + '_' + block.text)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Normal })
          .fontSize(15)
          .fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(COLOR_INPUT_BG)
          .borderRadius(22)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showAboutSheet = false;
            this.aboutSheetKind = 0;
          })
        Button('去下载', { type: ButtonType.Normal })
          .fontSize(15)
          .fontColor(COLOR_WHITE)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showAboutSheet = false;
            this.aboutSheetKind = 0;
            if (this.updateUrl.length > 0) {
              this.openExternalLink(this.updateUrl);
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 12 })
    }
    .width('100%')
  }

  /** 打开外部链接 */
  private openExternalLink(url: string): void {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      context.openLink(url);
    } catch (err) {
      showImmersiveToast({ message: '无法打开链接', duration: 1600 });
    }
  }

  /** 打开更新日志弹窗 */
  private openChangelog(): void {
    this.expandedAboutVersion = CHANGELOG_ENTRIES[0].version;
    this.aboutEntered = false;
    this.aboutSheetKind = 1;
    this.showAboutSheet = true;
    setTimeout((): void => {
      this.aboutEntered = true;
    }, 80);
  }

  /** 打开隐私政策弹窗 */
  private openPrivacyPolicy(): void {
    this.aboutEntered = false;
    this.aboutSheetKind = 2;
    this.showAboutSheet = true;
    setTimeout((): void => {
      this.aboutEntered = true;
    }, 80);
  }

  /** 关于弹窗（按类型分发） */
  @Builder
  aboutSheet() {
    if (this.aboutSheetKind === 1) {
      this.changelogSheet()
    } else {
      this.privacySheet()
    }
  }

  /** 更新日志弹窗 */
  @Builder
  changelogSheet() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
      Row({ space: 12 }) {
        Image($r('app.media.bika'))
          .width(52)
          .height(52)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
          .backgroundColor(COLOR_PRIMARY_TINT)
        Column({ space: 4 }) {
          Text('Bika')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
          Text('当前版本 v' + CHANGELOG_ENTRIES[0].version)
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 48 })
      .padding(14)
      .backgroundColor(Color.Transparent)
      .borderRadius(20)
      .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

      Column({ space: 12 }) {
        Text('更新日志')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_TITLE)
          .width('100%')
        Scroll() {
          Column({ space: 10 }) {
            ForEach(CHANGELOG_ENTRIES, (entry: ChangelogEntry): void => {
              Column({ space: 0 }) {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text('v' + entry.version)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(COLOR_TEXT_TITLE)
                    Text(entry.date)
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_SECONDARY)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(20)
                    .fontColor([COLOR_TEXT_SECONDARY])
                    .rotate({ angle: this.expandedAboutVersion === entry.version ? 180 : 0 })
                    .animation({ duration: 180, curve: Curve.EaseOut })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick((): void => {
                  this.expandedAboutVersion = this.expandedAboutVersion === entry.version ? '' : entry.version;
                })
                .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.97 })

                if (this.expandedAboutVersion === entry.version) {
                  Column({ space: 8 }) {
                    Divider().margin({ bottom: 12 })
                    ForEach(entry.items, (item: string): void => {
                      Text('• ' + item)
                        .fontSize(14)
                        .lineHeight(21)
                        .fontColor(COLOR_TEXT_SECONDARY)
                        .width('100%')
                    }, (item: string): string => item)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 16 })
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
                  .animation({ duration: 180, curve: Curve.EaseOut })
                }
              }
              .width('100%')
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            }, (entry: ChangelogEntry): string => entry.version)
          }
          .width('100%')
        }
        .width('100%')
        .height(350)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .opacity(this.aboutEntered ? 1 : 0)
      .translate({ y: this.aboutEntered ? 0 : 24 })
      .scale({ x: this.aboutEntered ? 1 : 0.97, y: this.aboutEntered ? 1 : 0.97 })
      .animation({ duration: 420, curve: Curve.Friction })
    }
    .width('100%')
    // 弹窗根容器补与页面一致的底色：内部卡片均为 COLOR_CARD，根用 COLOR_BG 才不撞色，深浅两模式都与页面同色
    // 顶部圆角取值≥系统 sheet 圆角（实测约 24vp），避免底色把弹窗顶角填成直角
    .backgroundColor(COLOR_BG)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }

  /** 隐私政策弹窗 */
  @Builder
  privacySheet() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 6 }) {
            Text('隐私政策')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('生效日期：2026 年 8 月 16 日')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 6 }) {
            Text('账号与资料')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('登录凭据仅保存在本机应用私有目录，用于访问哔咔 API。头像、昵称、等级等资料由哔咔服务器提供，本应用不作额外收集与上传。')
              .fontSize(14)
              .lineHeight(21)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 6 }) {
            Text('本地文件')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('下载的漫画与图片缓存储存在应用沙箱内，不包含任何跟踪标识。卸载应用后随沙箱一并清除。')
              .fontSize(14)
              .lineHeight(21)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 6 }) {
            Text('网络请求')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('网络请求仅发往哔咔官方接口（含国内镜像线路），用于登录、拉取漫画与图片。请求签名与官方客户端一致，不包含任何第三方统计。')
              .fontSize(14)
              .lineHeight(21)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .width('100%')
        .padding({ top: 8 })
      }
      .width('100%')
      .height(420)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    // 隐私政策弹窗与更新日志同底色，保证两类弹窗观感一致
    .backgroundColor(COLOR_BG)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }
}

/** 桌面卡片 FormLink 回传的动作参数（EntryAbility 解析后经 AppStorage 转入） */
interface WidgetActionParams {
  action?: string;
  comicId?: string;
  comicTitle?: string;
  timestamp?: number;
  /** 应用接续专用：源端话数 / 页码 / 封面（仅 continuation_reading 时有值） */
  order?: number;
  page?: number;
  coverUrl?: string;
  /** 通用页面接续（action = continuation_navigate）：目标 route 与参数 JSON */
  route?: string;
  paramsJson?: string;
}

/** 打开「我的」内子页面的信号（IndexPage → ProfilePage 转交） */
interface SubpageOpenSignal {
  name: string;
  timestamp: number;
}

/**
 * 根容器 — HdsTabs 悬浮页签（首页 / 我的）
 * 沉浸光感页签 + 子页面打开时页签收起动画
 */
@Entry
@Component
struct IndexPage {
  /** 桌面卡片点击深链：EntryAbility 每次写入都带新的 timestamp，用 @Watch 感知新事件 */
  @StorageLink('bika_widget_action') @Watch('onWidgetActionChanged') widgetAction: string = '';
  @StorageLink('bika_subpage_open') @Watch('onSubpageChanged') subpageOpen: boolean = false;
  @StorageLink('bika_goto_profile') @Watch('onGotoProfile') gotoProfile: number = 0;
  @StorageLink('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_material_rev') materialRev: number = 0;
  @StorageLink('bika_animations') animationsEnabled: boolean = true;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @State currentTab: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  private apiService: ApiService = ApiService.getInstance();

  aboutToAppear(): void {
    // 首帧打点：用于证明 EntryAbility.onCreate 的同步置位发生在此之前（不打印敏感内容）
    console.info('[BikaAuth] IndexPage first frame: isLoggedIn='
      + (AppStorage.get<boolean>('isLoggedIn') === true ? 'true' : 'false')
      + ', auth_resolved=' + (AppStorage.get<boolean>('auth_resolved') === true ? 'true' : 'false'));
    AppStorage.setOrCreate('bika_material_level', this.materialLevel);
    let saved: number | undefined = AppStorage.get<number>('bika_active_tab') as number | undefined;
    if (saved === 0 || saved === 1) {
      this.currentTab = saved;
    }
    if (this.currentTab !== 0) {
      let controller: HdsTabsController = this.tabsController;
      setTimeout((): void => {
        controller.changeIndex(this.currentTab);
      }, 0);
    }
  }

  /** 子页面开合 → 页签收起/恢复动画 */
  onSubpageChanged(): void {
    if (this.subpageOpen) {
      this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    } else {
      this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    }
  }

  /** 首页头像 → 切到「我的」 */
  onGotoProfile(): void {
    if (this.gotoProfile > 0) {
      this.tabsController.changeIndex(1);
      this.currentTab = 1;
    }
  }

  // ══════════════ 桌面卡片点击深链 ══════════════
  // 卡片的 FormLink 会带 params 拉起 EntryAbility，EntryAbility 解析后写入
  // AppStorage('bika_widget_action')（JSON 字符串 + 自增 timestamp），本页消费并跳转。

  /** 卡片事件到达（应用在前台/后台点击卡片时由 @Watch 触发） */
  onWidgetActionChanged(): void {
    // 稍等窗口回到前台，避免在后台 push 路由被丢弃
    setTimeout((): void => {
      this.consumeWidgetAction();
    }, 150);
  }

  /**
   * 消费桌面卡片事件并跳转。
   * 两个入口：@Watch（onNewWant 热启动）与 onPageShow（onCreate 冷启动兜底）；
   * 先把 AppStorage 里的值清空再跳转，保证同一事件只处理一次。
   */
  private consumeWidgetAction(): void {
    let raw: string = this.widgetAction;
    if (raw.length === 0) {
      return;
    }
    // @StorageLink 赋值即写回 AppStorage：先消费掉，避免从子页返回首页时重复触发
    this.widgetAction = '';
    let action: string = '';
    let comicId: string = '';
    let comicTitle: string = '';
    // 应用接续专用字段（普通卡片动作下为默认值，不影响既有行为）
    let order: number = 0;
    let page: number = 0;
    let coverUrl: string = '';
    let route: string = '';
    let paramsJson: string = '';
    try {
      let payload = JSON.parse(raw) as WidgetActionParams;
      action = payload.action ?? '';
      comicId = payload.comicId ?? '';
      comicTitle = payload.comicTitle ?? '';
      order = payload.order ?? 0;
      page = payload.page ?? 0;
      coverUrl = payload.coverUrl ?? '';
      route = payload.route ?? '';
      paramsJson = payload.paramsJson ?? '';
    } catch (err) {
      console.error('[IndexPage] widget action parse failed: ' + JSON.stringify(err));
      return;
    }
    console.info('[IndexPage] widget action = ' + action + ', comicId = ' + comicId);
    // 延后一帧，等页签/页面骨架就绪后再跳转
    setTimeout((): void => {
      if (action === 'continue_reading') {
        if (comicId.length > 0) {
          this.openWidgetReader(comicId, comicTitle);
        } else {
          // 无作品 id（卡片还没拿到历史数据）→ 打开「我的 → 浏览历史」
          this.openProfileSubpage('history');
        }
      } else if (action === 'open_favourites') {
        // 收藏卡片顶部 / 快捷入口「收藏」→ 我的 → 我的收藏
        this.openProfileSubpage('favourites');
      } else if (action === 'open_history') {
        // 快捷入口「历史」→ 我的 → 浏览历史
        this.openProfileSubpage('history');
      } else if (action === 'open_recommend') {
        // 快捷入口「推荐」→ 首页「推荐」频道页
        router.pushUrl({
          url: 'pages/ChannelListPage',
          params: { label: '推荐', kind: 'recommend' }
        });
      } else if (action === 'open_leaderboard') {
        // 排行榜卡片顶部 → 榜单频道页
        router.pushUrl({
          url: 'pages/ChannelListPage',
          params: { label: '排行榜', kind: 'leaderboard' }
        });
      } else if (action === 'open_search') {
        // 快捷入口「搜索」→ 搜索页
        router.pushUrl({ url: 'pages/SearchPage' });
      } else if (action === 'open_comic' || action === 'recent') {
        if (comicId.length > 0) {
          router.pushUrl({
            url: 'pages/ComicDetailPage',
            params: { comicId: comicId, comicTitle: comicTitle }
          });
        } else {
          // 无作品 id → 打开「最近更新」频道页
          router.pushUrl({
            url: 'pages/ChannelListPage',
            params: { label: '最近更新', kind: 'recent' }
          });
        }
      } else if (action === 'continuation_reading') {
        // 应用接续（手机 ↔ 平板）：定位到源端的同一话、同一页；
        // 数据缺失（无 comicId）→ 留在首页，安全降级
        if (comicId.length > 0) {
          this.openContinuationReader(comicId, comicTitle, order, page, coverUrl);
        }
      } else if (action === 'continuation_navigate') {
        // 应用接续（通用）：按源端 route + params 落到同一个页面
        this.handleContinuationNavigate(route, paramsJson);
      }
    }, 80);
  }

  /**
   * 「继续阅读」：直接打开阅读器并定位到本地记录的上次阅读话数。
   * epsCount 只用于阅读器内的「上一话 / 下一话」按钮，异步尽力获取，
   * 超时或失败一律回退 1，绝不阻塞卡片跳转。
   */
  private async openWidgetReader(comicId: string, comicTitle: string): Promise<void> {
    let order: number = 1;
    let coverUrl: string = '';
    try {
      let cache = await CacheManager.getInstance();
      let saved: number = cache.getReadProgress(comicId);
      if (saved > 0) {
        order = saved;
      }
      let items: HistoryItem[] = cache.loadHistory();
      for (let item of items) {
        if (item.comicId === comicId) {
          coverUrl = item.coverUrl;
          break;
        }
      }
    } catch (err) {
      console.warn('[IndexPage] widget reader cache failed: ' + JSON.stringify(err));
    }
    let epsCount: number = await this.fetchEpsCount(comicId);
    if (epsCount <= 0) {
      epsCount = 1;
    }
    console.info('[IndexPage] open reader from widget: order = ' + order + ', epsCount = ' + epsCount);
    router.pushUrl({
      url: 'pages/ReaderPage',
      params: {
        comicId: comicId,
        comicTitle: comicTitle,
        epsCount: epsCount,
        currentOrder: order,
        coverUrl: coverUrl
      }
    });
  }

  /**
   * 应用接续（通用）：按源端 route + params 在目标端落到同一个页面。
   * 覆盖：home / ChannelListPage / ComicDetailPage / ReaderPage / profile_subpage / SearchPage /
   * SearchResultPage；未知 route 一律回到首页，不崩溃。
   */
  private handleContinuationNavigate(route: string, paramsJson: string): void {
    let p: ContinuationRouteParams = {};
    try {
      if (paramsJson.length > 0) {
        p = JSON.parse(paramsJson) as ContinuationRouteParams;
      }
    } catch (err) {
      console.warn('[IndexPage] continuation params parse failed: ' + JSON.stringify(err));
      p = {};
    }
    // 只打 route：不打印作品名 / comicId
    console.info('[IndexPage] continuation navigate: route = ' + route);
    if (route === ROUTE_READER && (p.comicId ?? '').length > 0) {
      this.openContinuationReader(p.comicId ?? '', p.comicTitle ?? '', p.order ?? 0, p.page ?? 0, p.coverUrl ?? '');
    } else if (route === ROUTE_COMIC_DETAIL && (p.comicId ?? '').length > 0) {
      router.pushUrl({
        url: 'pages/ComicDetailPage',
        params: { comicId: p.comicId ?? '', comicTitle: p.comicTitle ?? '' }
      });
    } else if (route === ROUTE_CHANNEL_LIST) {
      router.pushUrl({
        url: 'pages/ChannelListPage',
        params: { label: p.label ?? '', kind: p.kind ?? 'topic' }
      });
    } else if (route === ROUTE_PROFILE_SUBPAGE && (p.subpage ?? '').length > 0) {
      this.openProfileSubpage(p.subpage ?? '');
    } else if (route === ROUTE_SEARCH) {
      router.pushUrl({ url: 'pages/SearchPage' });
    } else if (route === ROUTE_SEARCH_RESULT && (p.keyword ?? '').length > 0) {
      router.pushUrl({
        url: 'pages/SearchResultPage',
        params: { keyword: p.keyword ?? '' }
      });
    } else {
      // home 或未知 route：回到首页并切到对应页签（安全降级）
      let tab: number = p.tab ?? 0;
      if (tab !== 0 && tab !== 1) {
        tab = 0;
      }
      this.currentTab = tab;
      AppStorage.setOrCreate('bika_active_tab', tab);
      this.tabsController.changeIndex(tab);
    }
  }

  /**
   * 发布「当前页面」（应用接续源端）：首页 / 「我的」根页。
   * 「我的」子页由 ProfilePage 发布；被 push 的页面由各自页面发布。
   */
  private publishCurrentRoute(): void {
    let subpage: string = AppStorage.get<string>(CONTINUATION_PROFILE_SUBPAGE_KEY) ?? '';
    if (subpage.length > 0) {
      publishContinuationRoute(ROUTE_PROFILE_SUBPAGE, { subpage: subpage });
      return;
    }
    publishContinuationRoute(ROUTE_HOME, { tab: this.currentTab });
  }

  /**
   * 应用接续（手机 ↔ 平板）：打开阅读器并定位到源端的话数与页码。
   *
   * 话数 / 页码 / 封面一律使用源端传来的实时值，**不做本地历史回落**
   *（避免又跳回上一次的旧位置）。页码复用阅读器现有的本地恢复逻辑
   *（ReaderPage.restoreLastPage 读 page_<comicId>_<order>），所以先把页码落到本地
   * 再 push 阅读器即可定位到同一页，无需改动 ReaderPage。
   * 并发/耗时与「卡片继续阅读」一致：epsCount 异步尽力获取，失败回退 1，绝不阻塞跳转。
   * 降级：话数无效按第 1 话打开；作品不可用由阅读器自身错误态兜底（不崩溃、不白屏）。
   */
  private async openContinuationReader(comicId: string, comicTitle: string,
    order: number, page: number, coverUrl: string): Promise<void> {
    let targetOrder: number = order > 0 ? order : 1;
    try {
      let cache = await CacheManager.getInstance();
      if (page > 0) {
        cache.savePageProgress(comicId, targetOrder, page);
      }
    } catch (err) {
      console.warn('[IndexPage] continuation cache failed: ' + JSON.stringify(err));
    }
    let epsCount: number = await this.fetchEpsCount(comicId);
    if (epsCount <= 0) {
      epsCount = 1;
    }
    console.info('[IndexPage] open reader from continuation: order = ' + targetOrder
      + ', page = ' + page + ', epsCount = ' + epsCount);
    router.pushUrl({
      url: 'pages/ReaderPage',
      params: {
        comicId: comicId,
        comicTitle: comicTitle,
        epsCount: epsCount,
        currentOrder: targetOrder,
        coverUrl: coverUrl
      }
    });
  }

  /**
   * 取作品总话数，超时（2.5s）或失败返回 0。
   * 用单次详情请求（含 epsCount）而不是 getAllEps 翻页，减少请求数与频控风险。
   */
  private async fetchEpsCount(comicId: string): Promise<number> {
    let timeout: Promise<number> = new Promise<number>((resolve: (value: number) => void) => {
      setTimeout((): void => {
        resolve(0);
      }, 2500);
    });
    let request: Promise<number> = this.apiService.getComicDetail(comicId)
      .then((detail: BikaComicDetail): number => {
        let n = Number(detail.epsCount);
        console.info('[IndexPage] widget epsCount = ' + n);
        return isNaN(n) ? 0 : n;
      })
      .catch((err: Error): number => {
        console.warn('[IndexPage] widget epsCount failed: ' + JSON.stringify(err));
        return 0;
      });
    return Promise.race([request, timeout]);
  }

  /**
   * 打开「我的」页内的子页面（如浏览历史）。
   * NavPathStack 由 ProfilePage 持有，这里切到「我的」页签，再用 AppStorage 信号转交。
   */
  private openProfileSubpage(name: string): void {
    this.tabsController.changeIndex(1);
    this.currentTab = 1;
    AppStorage.setOrCreate('bika_active_tab', 1);
    let signal: SubpageOpenSignal = {
      name: name,
      timestamp: Date.now()
    };
    AppStorage.setOrCreate('bika_open_subpage', JSON.stringify(signal));
  }

  onPageShow(): void {
    AppStorage.set('isLoggedIn', ApiService.getInstance().isLoggedIn());
    // 冷启动时 onCreate 写入的卡片事件在此消费（此时页面与路由已就绪）
    this.consumeWidgetAction();
    // 应用接续：本页可见即发布「当前页面」（从子页返回时也会重新发布）
    this.publishCurrentRoute();
  }

  /** 沉浸光感档位映射 */
  private hdsMaterialLevel(): hdsMaterial.MaterialLevel {
    if (this.materialLevel === 'EXQUISITE') {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (this.materialLevel === 'SMOOTH') {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    if (this.materialLevel === 'ADAPTIVE') {
      return hdsMaterial.MaterialLevel.ADAPTIVE;
    }
    return hdsMaterial.MaterialLevel.GENTLE;
  }

  @Builder
  tabLabel(index: number, label: string, symbol: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([this.currentTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
      Text(label)
        .fontSize(12)
        .fontColor(this.currentTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height(52)
    .backgroundColor('#00000000')
  }

  build() {
    HdsTabs({ index: this.currentTab, controller: this.tabsController }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.tabLabel(0, '首页', $r('sys.symbol.house')))

      TabContent() {
        ProfilePage()
      }
      .tabBar(this.tabLabel(1, '我的', $r('sys.symbol.person')))
    }
    // 子页打开期间冻结 key：避免重建销毁当前页（设置页会被踢回），关闭子页后再应用新档位
    .key(this.subpageOpen ? 'hds_tabs_stable' : ('hds_tabs_' + this.materialLevel + '_' + this.materialRev))
    .barOverlap(true)
    .animationDuration(0)
    .vertical(false)
    .barPosition(BarPosition.End)
    .divider({ mode: DividerMode.NONE })
    .barFloatingStyle({
      // 全屏窗口下抬起至手势条上方，再向下 10vp
      barBottomMargin: Math.max(0, this.bottomSafeHeight - 6),
      adaptToHandedness: true,
      lightColor: '#FF7CA8',
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: this.hdsMaterialLevel()
      }
    })
    .onChange((index: number): void => {
      this.currentTab = index;
      AppStorage.set('bika_active_tab', index);
      // 应用接续：页签切换同步「当前页面」
      this.publishCurrentRoute();
    })
    .backgroundColor(COLOR_BG)
    .width('100%')
    .height('100%')
  }
}
