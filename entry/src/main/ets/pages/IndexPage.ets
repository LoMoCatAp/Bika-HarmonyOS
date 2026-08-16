import { router, display, promptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ApiService, ComicsPageResult } from '../network/ApiService';
import { ComicViewModel, buildImageUrl, BikaComicSummary, BikaNotification, BikaComment } from '../models/Comic';
import { NetImage } from '../components/NetImage';
import { ComicCard } from '../components/ComicCard';
import { CacheManager, HistoryItem } from '../common/CacheManager';
import { DownloadManager, DownloadTask } from '../common/DownloadManager';
import { compatibleImmersiveMaterial } from '../common/CompatibleMaterial';
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
  DEFAULT_CHANNELS,
  SORT_OPTIONS,
  SortOption,
  BikaChannel
} from '../common/Constants';
import { HdsTabs, HdsTabsController, HdsAnimationMode, DividerMode, hdsMaterial, HdsNavigation, HdsNavDestination } from '@kit.UIDesignKit';

/**
 * 主入口 — HdsTabs 悬浮页签（首页 / 我的）
 * 沉浸光感页签 + 子页面打开时页签收起动画
 */

/** 全部分类标识 */
const CATEGORY_ALL: string = '全部';

// ═══════════════════════════════════════════
// 首页 — 频道网格
@Component
struct HomePage {
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  @StorageProp('avatarUrl') avatarUrl: string = '';

  /** 跳转个人中心（由 IndexPage 切换 tab） */
  onGotoProfile(): void {
    AppStorage.set('bika_goto_profile', Date.now());
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // 顶部占位（浮层标题栏）
          Row().height(this.topSafeHeight + 56)

          // 频道网格（方形图标 + 名称）
          Grid() {
            ForEach(DEFAULT_CHANNELS, (ch: BikaChannel) => {
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
                .onClick(() => {
                  if (ch.kind === 'board') {
                    promptAction.showToast({ message: '该功能已下线', duration: 1600 });
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
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(14)
          .rowsGap(18)
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .backgroundColor(COLOR_BG)

      // 浮层标题栏（纯色融入背景）
      Row() {
        Text('Bika')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([COLOR_TEXT_TITLE])
          .padding(6)
          .onClick(() => {
            router.pushUrl({ url: 'pages/SearchPage' });
          })
        if (this.isLoggedIn) {
          if (this.avatarUrl.length > 0) {
            NetImage({
              src: this.avatarUrl,
              fit: ImageFit.Cover,
              radius: 18,
              fillParent: true
            })
              .width(36)
              .height(36)
              .margin({ left: 8 })
              .onClick(() => {
                this.onGotoProfile();
              })
          } else {
            Image($r('app.media.ic_default_avatar'))
              .width(36)
              .height(36)
              .borderRadius(18)
              .objectFit(ImageFit.Cover)
              .margin({ left: 8 })
              .onClick(() => {
                this.onGotoProfile();
              })
          }
        } else {
          Button({ type: ButtonType.Normal }) {
            Text('登录')
              .fontSize(14)
              .fontColor(COLOR_WHITE)
          }
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(18)
          .width(64)
          .height(34)
          .margin({ left: 8 })
          .onClick(() => router.pushUrl({ url: 'pages/LoginPage' }))
        }
      }
      .position({ x: 0, y: 0 })
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topSafeHeight + 10, bottom: 10 })
      .backgroundColor(COLOR_GLASS_TOP)
      .backdropBlur(20)
      .zIndex(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
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

/** 下载列表（独立组件：订阅 DownloadManager 实时刷新） */
@Component
struct DownloadListView {
  @State tasks: DownloadTask[] = [];
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

  build() {
    if (this.groups().length === 0) {
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
      .layoutWeight(1)
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(COLOR_BG)
    } else {
      List({ space: 12 }) {
        ForEach(this.groups(), (g: DownloadGroup) => {
          ListItem() {
            Row() {
              if (g.coverLocal.length > 0) {
                NetImage({
                  src: 'file://' + g.coverLocal,
                  fit: ImageFit.Cover,
                  radius: 10,
                  fillParent: true
                })
                  .width(76)
                  .height(100)
              } else {
                NetImage({
                  src: g.coverUrl,
                  fit: ImageFit.Cover,
                  radius: 10,
                  fillParent: true
                })
                  .width(76)
                  .height(100)
              }
              Column({ space: 6 }) {
                Text(g.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (g.author.length > 0) {
                  Text(g.author)
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_HINT)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (g.description.length > 0) {
                  Text(g.description)
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_SECONDARY)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Row() {
                  Text('已下载 ' + g.downloadedCount + '/' + g.totalCount + ' 话')
                    .fontSize(12)
                    .fontColor(g.downloadedCount === g.totalCount ? COLOR_PRIMARY : COLOR_TEXT_HINT)
                  if (g.sizeBytes > 0) {
                    Text(' · ' + this.sizeLabel(g.sizeBytes))
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_HINT)
                      .margin({ left: 4 })
                  }
                  Blank()
                  if (g.hasDownloading) {
                    Text('下载中')
                      .fontSize(11)
                      .fontColor(COLOR_PRIMARY)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor(COLOR_PRIMARY_TINT)
                      .borderRadius(8)
                  } else if (g.hasWaiting) {
                    Text('等待中')
                      .fontSize(11)
                      .fontColor(COLOR_TEXT_SECONDARY)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor(COLOR_INPUT_BG)
                      .borderRadius(8)
                  }
                }
                .width('100%')
                if (g.hasDownloading) {
                  Text('正在下载：' + (g.downloadingTitle.length > 0 ? g.downloadingTitle : ('第' + (g.downloadedCount + 1) + '话')))
                    .fontSize(11)
                    .fontColor(COLOR_TEXT_HINT)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row() {
                    Progress({
                      value: g.downloadingTotal > 0 ? g.downloadingProgress * 100 / g.downloadingTotal : 0,
                      type: ProgressType.Linear
                    })
                      .height(4)
                      .layoutWeight(1)
                      .color(COLOR_PRIMARY)
                      .backgroundColor(COLOR_PRIMARY_TINT)
                    Text(g.downloadingTotal > 0 ? Math.round(g.downloadingProgress * 100 / g.downloadingTotal) + '%' : '等待中')
                      .fontSize(11)
                      .fontColor(COLOR_PRIMARY)
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                } else if (g.hasWaiting) {
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
                if (g.hasFailed && g.failedFirst) {
                  Row() {
                    Text('下载失败：' + (g.failedFirst.chapterTitle.length > 0 ? g.failedFirst.chapterTitle : ('第' + g.failedFirst.chapterOrder + '话')))
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
                        DownloadManager.getInstance().retryTask(g.failedFirst!.comicId, g.failedFirst!.chapterOrder);
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(COLOR_CARD)
            .borderRadius(16)
            .border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ComicDetailPage',
                params: { comicId: g.comicId, comicTitle: g.title }
              });
            })
          }
        }, (g: DownloadGroup) => g.comicId)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
  }
}

/** 更新日志条目 */
interface ChangelogEntry {
  version: string;
  date: string;
  items: string[];
}

/** 更新日志（PezMax 同款可折叠列表） */
const CHANGELOG_ENTRIES: ChangelogEntry[] = [
  {
    version: '1.0.3',
    date: '2026-08-16',
    items: [
      '设置子页全部改为从顶部排布（PezMax 同款自绘返回头）',
      '底部导航与卡片全面接入沉浸光感材质（档位可调）',
      '关于页：更新日志折叠卡片 + 隐私政策',
      '评论点赞 / 回复 / 发表，子回复展开',
      '阅读器：横竖屏锁定 + 亮度调节',
      '下载：仅 WiFi 下载、并发数设置、失败重试、本地离线阅读'
    ]
  },
  {
    version: '1.0.2',
    date: '2026-08-16',
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
    date: '2026-08-16',
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
    date: '2026-08-15',
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

/** 沉浸光感档位选项（PezMax 同款） */
interface MaterialOption {
  value: string;
  label: string;
}

const MATERIAL_OPTIONS: MaterialOption[] = [
  { value: 'EXQUISITE', label: '强' },
  { value: 'GENTLE', label: '均衡（默认）' },
  { value: 'SMOOTH', label: '弱' },
  { value: 'ADAPTIVE', label: '系统自适应' }
];

@Component
struct ProfilePage {
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  // 主题强调色：哔咔粉（保留哔咔主题色）
  private accentColor: ResourceColor = $r('app.color.bika_primary');
  /** 强调色 hex（沉浸光感点光用，PezMax 同款） */
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
  @State colorMode: string = 'system';
  /** 下载设置 */
  @State downloadWifiOnly: boolean = false;
  @State downloadConcurrent: number = 1;
  @State punching: boolean = false;
  @StorageLink('download_revision') @Watch('onDownloadChanged') downloadRevision: number = 0;
  @State downloadList: DownloadTask[] = [];
  @State punched: boolean = false;
  /** 关于弹窗（PezMax 同款 bindSheet） */
  @State showAboutSheet: boolean = false;
  @State expandedAboutVersion: string = '1.0.0';
  @State aboutEntered: boolean = false;
  /** 弹窗类型：0 关闭 1 更新日志 2 隐私政策 */
  @State aboutSheetKind: number = 0;
  /** 沉浸光感档位（与 IndexPage 页签联动） */
  @StorageLink('bika_material_level') materialLevel: string = 'EXQUISITE';

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
    this.colorMode = AppStorage.get('bika_color_mode') as string ?? 'system';
    this.downloadWifiOnly = DownloadManager.getInstance().getWifiOnly();
    this.downloadConcurrent = DownloadManager.getInstance().getMaxConcurrent();
    if (this.apiService.isLoggedIn()) {
      this.loadProfile();
    }
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
    });
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
      this.punched = !!user.isPunched;
      if (user.avatar && user.avatar.path) {
        this.avatarUrl = buildImageUrl(user.avatar);
        AppStorage.set('avatarUrl', this.avatarUrl);
      }
      this.profileLoaded = true;
      console.info('[ProfilePage] profile loaded: ' + this.userName + ' LV.' + this.userLevel);
    } catch (err) {
      this.profileError = (err as Error).message || '加载失败';
      console.warn('[ProfilePage] loadProfile failed: ' + this.profileError);
    }
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
      promptAction.showToast({ message: '已退出登录', duration: 2000 });
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
      promptAction.showToast({ message: '签到成功', duration: 2000 });
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '签到失败', duration: 2000 });
    } finally {
      this.punching = false;
    }
  }

  /** 打开子页面（PezMax 同款：底部导航动画收缩隐藏） */
  private openSubpage(name: string): void {
    if (!this.isLoggedIn && name !== 'settings' && name !== 'downloads' && name !== 'about') {
      router.pushUrl({ url: 'pages/LoginPage' });
      return;
    }
    AppStorage.set('bika_subpage_open', true);
    this.stack.pushPathByName(name, '');
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
    }
  }

  private closeSubpage(): void {
    this.stack.pop();
    AppStorage.set('bika_subpage_open', false);
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
    this.historyItems = this.cache ? this.cache.loadHistory() : [];
  }

  private onDownloadChanged(): void {
    this.downloadList = DownloadManager.getInstance().getTasks();
  }

  private setColorMode(mode: string): void {
    this.colorMode = mode;
    AppStorage.set('bika_color_mode', mode);
    let ctx = getContext(this).getApplicationContext();
    if (mode === 'dark') {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === 'light') {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  /** 沉浸光感档位（PezMax 同款 Select 辅助） */
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

  private selectMaterial(index: number): void {
    const option: MaterialOption | undefined = MATERIAL_OPTIONS[index];
    if (option === undefined) {
      return;
    }
    this.materialLevel = option.value;
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
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
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
    .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    HdsNavigation(this.stack) {
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
                Text('未登录')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('登录后同步收藏与评论')
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_HINT)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 14 })
              .layoutWeight(1)

              Button('登录', { type: ButtonType.Normal })
                .fontSize(14)
                .fontColor(COLOR_WHITE)
                .backgroundColor(COLOR_PRIMARY)
                .borderRadius(18)
                .height(36)
                .padding({ left: 20, right: 20 })
                .onClick(() => this.onLogin())
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          }

          this.menuList()

          if (this.isLoggedIn) {
            Row() {
              Text('退出登录')
                .fontSize(15)
                .fontColor('#C62828')
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            .onClick(() => this.onLogout())
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topSafeHeight + 16, bottom: 40 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAboutSheet, this.aboutSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: true,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showAboutSheet = false;
        this.aboutEntered = false;
        this.aboutSheetKind = 0;
      }
    })
  }

  /** 子页返回头（PezMax subpageHeader 同款：自绘返回键 + 大标题，内容从上往下排布） */
  @Builder
  subpageHeader(title: string) {
    Column() {
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([this.accentColor])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(compatibleImmersiveMaterial(this.accentHex, false, true))
        .onClick(() => this.closeSubpage())
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        Text(title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .padding({ top: this.topSafeHeight })
  }

  /** 子页面注册（PezMax 同款） */
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
    }
  }

  /** 我的收藏 */
  @Builder
  favouritesDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('我的收藏')
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

        Scroll() {
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
          if (this.favHasMore && !this.favLoading) {
            this.favPage++;
            this.loadFavourites(false);
          }
        })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 浏览历史 */
  @Builder
  historyDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('浏览历史')
        if (this.historyItems.length === 0) {
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
        } else {
          List({ space: 0 }) {
            ForEach(this.historyItems, (item: HistoryItem, index: number) => {
              ListItem() {
                Row() {
                  Column({ space: 4 }) {
                    Text(item.title)
                      .fontSize(15)
                      .fontColor(COLOR_TEXT_TITLE)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('看到第 ' + item.order + ' 话')
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_HINT)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([COLOR_TEXT_DISABLED])
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/ComicDetailPage',
                    params: { comicId: item.comicId, comicTitle: item.title }
                  });
                })
              }
              if (index < this.historyItems.length - 1) {
                ListItem() {
                  Divider().height(1).color(COLOR_DIVIDER).margin({ left: 16 })
                }
              }
            }, (item: HistoryItem) => item.comicId)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 我的下载（独立组件订阅实时刷新） */
  @Builder
  downloadsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('我的下载')
        DownloadListView()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 通知 */
  @Builder
  notificationsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('通知')
        if (this.notifications.length === 0) {
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
        } else {
        List({ space: 0 }) {
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
          .layoutWeight(1)
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 我的评论 */
  @Builder
  commentsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('我的评论')
        if (this.myComments.length === 0) {
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
        } else {
        List({ space: 0 }) {
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
          .layoutWeight(1)
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 设置 */
  @Builder
  settingsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('设置')
        Scroll() {
        Column({ space: 12 }) {
          Column() {
            Text('外观')
              .fontSize(13)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 6 })
            this.colorModeRow('system', '跟随系统')
            this.colorModeRow('light', '浅色')
            this.colorModeRow('dark', '深色')
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          .padding({ bottom: 8 })

          Text('沉浸光感')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 2 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.paintbrush'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Text('档位')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .layoutWeight(1)
            Select(this.selectOptions(MATERIAL_OPTIONS))
              .selected(this.optionIndex(MATERIAL_OPTIONS, this.materialLevel))
              .value(this.labels(MATERIAL_OPTIONS)[this.optionIndex(MATERIAL_OPTIONS, this.materialLevel)])
              .font({ size: 15 })
              .fontColor(COLOR_PRIMARY)
              .selectedOptionFont({ size: 15, weight: FontWeight.Medium })
              .selectedOptionFontColor(COLOR_PRIMARY)
              .optionFont({ size: 15 })
              .optionFontColor(COLOR_TEXT_TITLE)
              .optionBgColor(COLOR_CARD)
              .onSelect((index: number): void => {
                this.selectMaterial(index);
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

          Column() {
            Text('下载')
              .fontSize(13)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 6 })
            Row() {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(20)
                .fontColor([COLOR_TEXT_SECONDARY])
              Text('仅 WiFi 下载')
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .margin({ left: 12 })
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.downloadWifiOnly })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.downloadWifiOnly = isOn;
                  DownloadManager.getInstance().setWifiOnly(isOn);
                  if (isOn && !DownloadManager.getInstance().isWifiNow()) {
                    promptAction.showToast({ message: '当前非 WiFi 网络，任务将等待 WiFi', duration: 2000 });
                  }
                })
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                .fontSize(20)
                .fontColor([COLOR_TEXT_SECONDARY])
              Text('最大并发数')
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
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
            .height(52)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          .padding({ bottom: 8 })

          Column() {
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
            .padding(16)
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            .onClick(() => {
              this.openSubpage('about');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 关于子页（PezMax aboutContent 同款） */
  @Builder
  aboutDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('关于')
        Scroll() {
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
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

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
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
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
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          .onClick(() => {
            this.openPrivacyPolicy();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
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

  /** 关于弹窗（按类型分发，PezMax aboutSheet 同款） */
  @Builder
  aboutSheet() {
    if (this.aboutSheetKind === 1) {
      this.changelogSheet()
    } else {
      this.privacySheet()
    }
  }

  /** 更新日志弹窗（PezMax changelogSheet 同款） */
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
      .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

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
              .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            }, (entry: ChangelogEntry): string => entry.version)
          }
          .width('100%')
        }
        .width('100%')
        .height(350)
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
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }

  /** 隐私政策弹窗（PezMax privacySheet 同款） */
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
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }

  /** 外观模式单选行 */
  @Builder
  colorModeRow(mode: string, label: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(15)
        .fontColor(COLOR_TEXT_TITLE)
        .layoutWeight(1)
      if (this.colorMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(17)
          .fontColor([COLOR_PRIMARY])
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.setColorMode(mode);
    })
  }
}

/**
 * 根容器 — HdsTabs 悬浮页签（首页 / 我的）
 * 沉浸光感页签 + 子页面打开时页签收起动画
 */
@Entry
@Component
struct IndexPage {
  @StorageLink('bika_subpage_open') @Watch('onSubpageChanged') subpageOpen: boolean = false;
  @StorageLink('bika_goto_profile') @Watch('onGotoProfile') gotoProfile: number = 0;
  @StorageLink('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @State currentTab: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
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

  /** 子页面开合 → 页签收起/恢复动画（PezMax MainShellView 同款） */
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

  onPageShow(): void {
    AppStorage.set('isLoggedIn', ApiService.getInstance().isLoggedIn());
  }

  /** 沉浸光感档位映射（PezMax MainShellView 同款） */
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
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.tabLabel(0, '首页', $r('sys.symbol.house')))

      TabContent() {
        ProfilePage()
      }
      .tabBar(this.tabLabel(1, '我的', $r('sys.symbol.person')))
    }
    .barOverlap(true)
    .animationDuration(0)
    .vertical(false)
    .barPosition(BarPosition.End)
    .divider({ mode: DividerMode.NONE })
    .barFloatingStyle({
      // 全屏窗口下抬起至手势条上方（PezMax 非全屏窗口时同为 4）
      barBottomMargin: 4 + this.bottomSafeHeight,
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
    })
    .backgroundColor(COLOR_BG)
    .width('100%')
    .height('100%')
  }
}