import { router, promptAction } from '@kit.ArkUI';
import { showImmersiveToast, showImmersiveDialog } from '../../common/ImmersiveToast';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ApiService } from '../../network/ApiService';
import { AppUpdateService } from '../../network/AppUpdateService';
import { ComicViewModel, buildImageUrl, BikaComicSummary, BikaNotification, BikaComment } from '../../models/Comic';
import { NetImage } from '../../components/NetImage';
import { GlassNavigationHeader } from '../../components/GlassNavigationHeader';
import { ChannelControlCapsule } from '../../components/ChannelControlCapsule';
import { CacheManager, HistoryItem } from '../../common/CacheManager';
import { FollowUpdateManager } from '../../common/FollowUpdateManager';
import { publishContinuationRoute, CONTINUATION_PROFILE_SUBPAGE_KEY, ROUTE_HOME, ROUTE_PROFILE_SUBPAGE } from '../../common/ContinuationState';
import { DownloadManager, DownloadTask } from '../../common/DownloadManager';
import { compatibleSheetMaterial } from '../../common/CompatibleMaterial';
import { ImageLoader } from '../../common/ImageLoader';
import { WindowHelper } from '../../common/WindowHelper';
import { ApiRouteManager } from '../../network/ApiRouteManager';
import { DnsService, DnsIpEntry } from '../../network/DnsService';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_PRIMARY_TINT_2, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_HINT, COLOR_TEXT_DISABLED, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_PLACEHOLDER, COLOR_DIVIDER, COLOR_WHITE, COLOR_LOGOUT_TEXT, SORT_OPTIONS, SortOption } from '../../common/Constants';
import { HdsTabs, HdsNavigation } from '@kit.UIDesignKit';
import { ProfileFavouritesPage, ProfileHistoryPage, ProfileDownloadsPage, ProfileNotificationsPage, ProfileCommentsPage } from './ProfileLibraryPages';
import { ProfileSettingsPage } from './ProfileSettingsPage';
import { ProfileAboutPage } from './ProfileAboutPage';
import { ProfileStoragePage } from './ProfileStoragePage';
import { ProfileDnsPage } from './ProfileDnsPage';
import { ProfileBlockedTagsPage } from './ProfileBlockedTagsPage';
import { ProfileEditPage, ProfileAccountPage } from './ProfileAccountPages';
import { ProfileUpdateSheet, ProfileChangelogSheet, ProfilePrivacySheet } from './ProfileSheets';
import { MaterialOption, MATERIAL_OPTIONS, COLOR_MODE_OPTIONS } from './ProfileOptions';
import { SubpageOpenSignal } from '../../models/IndexNavigation';
import { CHANGELOG_ENTRIES } from '../../common/Changelog';

interface MenuItemData {
  icon: Resource;
  label: string;
  page: string;
}

@Component
export struct ProfilePage {
  @StorageProp(CONTINUATION_PROFILE_SUBPAGE_KEY) visibleSubpage: string = '';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  /** 登录态是否已确定：未置位前不渲染「未登录」这类确定性文案 */
  @StorageProp('auth_resolved') authResolved: boolean = false;
  // 主题强调色：哔咔粉
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
  private favRequestId: number = 0;
  private readonly favouritesControlsHeight: number = 52;
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
  @State followUpdates: boolean = false;
  @State followUpdatesBusy: boolean = false;
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
    this.stack.setInterception({ didShow: (): void => this.syncSubpageState() });
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
      this.followUpdates = cache.getSetting('follow_updates', 'false') === 'true';
      this.widgetShowCover = cache.getSetting('widget_show_cover', 'true') === 'true';
    });
    // 冷启动时页面可能晚于信号创建，@Watch 不会补发，这里主动检查一次
    this.consumeSubpageSignal();
  }

  /** 登录态变化：登录成功自动拉取资料 */
  onLoginStateChanged(): void {
    if (this.isLoggedIn) {
      this.loadProfile();
    } else {
      this.favRequestId++;
      this.favComics = [];
      this.favPage = 1;
      this.favHasMore = false;
      this.favLoading = false;
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

  private async changeFollowUpdates(enabled: boolean): Promise<void> {
    if (this.followUpdatesBusy || this.followUpdates === enabled) {
      return;
    }
    this.followUpdatesBusy = true;
    this.followUpdates = enabled;
    try {
      this.followUpdates = await FollowUpdateManager.getInstance().setEnabled(enabled);
      showImmersiveToast({ message: enabled
        ? this.followUpdates ? '已开启追更通知'
          : this.apiService.isLoggedIn() ? '请允许系统通知后重试' : '请先登录后开启追更通知'
        : '已关闭追更通知', duration: 2000 });
    } catch (_err) {
      this.followUpdates = false;
      showImmersiveToast({ message: '追更通知设置失败，请重试', duration: 1600 });
    } finally {
      this.followUpdatesBusy = false;
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

  onLogin(): void {
    if (!this.isLoggedIn) {
      router.pushUrl({ url: 'pages/LoginPage' });
    }
  }

  onLogout(): void {
    this.apiService.logout().then((): void => {
      this.isLoggedIn = false;
      showImmersiveToast({ message: '已退出登录', duration: 2000 });
    }).catch((_err: Error): void => {
      showImmersiveToast({ message: '退出登录未完成，请稍后重试', duration: 2000 });
    });
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
    this.syncSubpageState();
  }

  /** 原生侧滑返回也以真实导航栈同步状态，不能只依赖自绘返回按钮。 */
  private syncSubpageState(): void {
    const names = this.stack.getAllPathName();
    const top = names.length > 0 ? names[names.length - 1] : '';
    AppStorage.setOrCreate('bika_subpage_open', names.length > 0);
    AppStorage.setOrCreate(CONTINUATION_PROFILE_SUBPAGE_KEY, top);
    if (AppStorage.get<number>('bika_active_tab') !== 1) {
      return;
    }
    if (top.length === 0) {
      publishContinuationRoute(ROUTE_HOME, { tab: 1 });
    } else {
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
    if (this.favLoading && !reset) {
      return;
    }
    const requestId = ++this.favRequestId;
    const sort = this.favSort;
    const account = (this.cache ?? CacheManager.getInstanceIfReady())?.getEmail() ?? '';
    const page = reset ? 1 : this.favPage + 1;
    this.favLoading = true;
    if (reset) {
      this.favComics = [];
      this.favHasMore = false;
    }
    try {
      const result = await this.apiService.getFavourites(sort, page);
      if (requestId !== this.favRequestId || sort !== this.favSort || !this.isLoggedIn
        || (CacheManager.getInstanceIfReady()?.getEmail() ?? '') !== account) {
        return;
      }
      const known = new Set<string>(reset ? [] : this.favComics.map((comic: ComicViewModel): string => comic.id));
      const vms = result.comics.filter((comic: BikaComicSummary): boolean => {
        if (known.has(comic._id)) {
          return false;
        }
        known.add(comic._id);
        return true;
      }).map((comic: BikaComicSummary): ComicViewModel => ComicViewModel.fromSummary(comic));
      this.favComics = reset ? vms : this.favComics.concat(vms);
      this.favPage = page;
      this.favHasMore = page < result.pages;
    } catch (err) {
      if (requestId === this.favRequestId && this.isLoggedIn
        && (CacheManager.getInstanceIfReady()?.getEmail() ?? '') === account) {
        console.warn('[ProfilePage] favourites failed: ' + JSON.stringify(err));
        if (this.visibleSubpage === 'favourites') {
          showImmersiveToast({ message: '收藏加载失败，请重试', duration: 1600 });
        }
      }
    } finally {
      if (requestId === this.favRequestId) {
        this.favLoading = false;
      }
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
    // 修订号 +1：胶囊立即更新，HdsTabs 在安全回到根页时应用新档位
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
            ? 'Bika用户'
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

  private subpageHeaderTitle(): string {
    switch (this.visibleSubpage) {
      case 'favourites': return '我的收藏';
      case 'history': return '浏览历史';
      case 'downloads': return '我的下载';
      case 'notifications': return '通知';
      case 'comments': return '我的评论';
      case 'settings': return '设置';
      case 'about': return '关于';
      case 'storage': return '存储与空间';
      case 'dns': return 'DNS 直连与分流优化';
      case 'blocked': return '屏蔽标签';
      case 'profile_edit': return '编辑资料';
      case 'account': return '账号与安全';
      default: return '';
    }
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
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
        systemMaterial: compatibleSheetMaterial(),
        scrollSizeMode: ScrollSizeMode.CONTINUOUS,
        onWillDismiss: (): void => {
          this.showAboutSheet = false;
          this.aboutEntered = false;
          this.aboutSheetKind = 0;
        }
      })

      if (this.subpageHeaderTitle().length > 0) {
        GlassNavigationHeader({
          title: this.subpageHeaderTitle(), onBack: (): void => this.closeSubpage()
        })
          .position({ x: 0, y: this.topSafeHeight })
          .zIndex(2)
          .transition(TransitionEffect.OPACITY)
          .animation({ duration: this.animationsEnabled ? 180 : 0, curve: Curve.EaseOut })
      }
      if (this.visibleSubpage === 'favourites') {
        this.favouritesSortControls()
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLOR_BG)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
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

  /** 与频道页一致，排序胶囊独立位于 HDS 模糊层上方。 */
  @Builder
  favouritesSortControls() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(SORT_OPTIONS, (item: SortOption): void => {
          ChannelControlCapsule({
            label: item.label,
            selected: this.favSort === item.key,
            onActivate: (): void => {
              if (this.favSort !== item.key) {
                this.favSort = item.key;
                this.favouritesScroller.scrollTo({ xOffset: 0, yOffset: 0 });
                this.loadFavourites(true);
              } else if (!this.favLoading && this.favComics.length === 0) {
                this.loadFavourites(true);
              }
            }
          })
        }, (item: SortOption): string => item.key)
      }
      .height(36)
    }
    .width('100%').height(this.favouritesControlsHeight)
    .align(Alignment.Start)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .position({ x: 0, y: this.topSafeHeight + 56 })
    .zIndex(2)
    .transition(TransitionEffect.OPACITY)
    .animation({ duration: this.animationsEnabled ? 180 : 0, curve: Curve.EaseOut })
  }

  /** 我的收藏 */
  @Builder
  favouritesDestination() {
    ProfileFavouritesPage({
      favouritesScroller: this.favouritesScroller,
      favLoading: $favLoading,
      favComics: $favComics,
      favSort: $favSort,
      favouritesControlsHeight: this.favouritesControlsHeight,
      favHasMore: $favHasMore,
      loadFavourites: (reset: boolean): Promise<void> => this.loadFavourites(reset),
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 浏览历史 */
  @Builder
  historyDestination() {
    ProfileHistoryPage({
      historyScroller: this.historyScroller,
      historyItems: $historyItems,
      confirmDeleteHistory: (item: HistoryItem): void => this.confirmDeleteHistory(item),
      confirmClearHistory: (): void => this.confirmClearHistory(),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 我的下载（独立组件订阅实时刷新） */
  @Builder
  downloadsDestination() {
    ProfileDownloadsPage({
      downloadsScroller: this.downloadsScroller,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 通知 */
  @Builder
  notificationsDestination() {
    ProfileNotificationsPage({
      notificationsScroller: this.notificationsScroller,
      notifications: $notifications,
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 我的评论 */
  @Builder
  commentsDestination() {
    ProfileCommentsPage({
      commentsScroller: this.commentsScroller,
      myComments: $myComments,
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 设置 */
  @Builder
  settingsDestination() {
    ProfileSettingsPage({
      settingsScroller: this.settingsScroller,
      accentColor: this.accentColor,
      selectColorModeOption: (index: number): void => this.selectColorModeOption(index),
      autoPunch: $autoPunch,
      maybeAutoPunch: (): Promise<void> => this.maybeAutoPunch(),
      followUpdates: $followUpdates,
      followUpdatesBusy: $followUpdatesBusy,
      changeFollowUpdates: (enabled: boolean): Promise<void> => this.changeFollowUpdates(enabled),
      secureScreen: $secureScreen,
      applySecureScreen: (): void => this.applySecureScreen(),
      confirmClearImageCache: (): void => this.confirmClearImageCache(),
      openSubpage: (name: string): void => this.openSubpage(name),
      downloadWifiOnly: $downloadWifiOnly,
      downloadConcurrent: $downloadConcurrent,
      widgetShowRealData: $widgetShowRealData,
      notifyWidgetRefresh: (): void => this.notifyWidgetRefresh(),
      widgetShowCover: $widgetShowCover,
      checkingUpdate: $checkingUpdate,
      checkUpdate: (): Promise<void> => this.checkUpdate(),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 关于子页 */
  @Builder
  aboutDestination() {
    ProfileAboutPage({
      aboutScroller: this.aboutScroller,
      accentColor: this.accentColor,
      openChangelog: (): void => this.openChangelog(),
      openPrivacyPolicy: (): void => this.openPrivacyPolicy(),
      openExternalLink: (url: string): void => this.openExternalLink(url),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 存储与空间子页 */
  @Builder
  storageDestination() {
    ProfileStoragePage({
      storageScroller: this.storageScroller,
      storageRefreshing: $storageRefreshing,
      downloadSizeBytes: $downloadSizeBytes,
      confirmClearAllDownloads: (): void => this.confirmClearAllDownloads(),
      cacheSizeBytes: $cacheSizeBytes,
      confirmClearImageCache: (): void => this.confirmClearImageCache(),
      refreshStorage: (): void => this.refreshStorage(),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** DNS 直连与分流优化子页 */
  @Builder
  dnsDestination() {
    ProfileDnsPage({
      dnsScroller: this.dnsScroller,
      dnsFetching: $dnsFetching,
      dnsTesting: $dnsTesting,
      accentColor: this.accentColor,
      dnsApiIps: $dnsApiIps,
      dnsImageIps: $dnsImageIps,
      fetchAndTestDns: (): Promise<void> => this.fetchAndTestDns(),
      dnsLines: $dnsLines,
      applyLowestLatencyDns: (): void => this.applyLowestLatencyDns(),
      dnsError: $dnsError,
      selectDnsIp: (entry: DnsIpEntry): void => this.selectDnsIp(entry),
      resetDns: (): void => this.resetDns(),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage(),
      loadDnsSelection: (): void => this.loadDnsSelection()
    })
  }

  /** 屏蔽标签子页 */
  @Builder
  blockedTagsDestination() {
    ProfileBlockedTagsPage({
      blockedTagsScroller: this.blockedTagsScroller,
      blockedTags: $blockedTags,
      toggleBlockedTag: (tag: string): void => this.toggleBlockedTag(tag),
      blockedLoading: $blockedLoading,
      keywordTags: $keywordTags,
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 资料编辑子页 */
  @Builder
  profileEditDestination() {
    ProfileEditPage({
      profileEditScroller: this.profileEditScroller,
      editSlogan: $editSlogan,
      editSaving: $editSaving,
      saveProfileEdit: (): Promise<void> => this.saveProfileEdit(),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
    })
  }

  /** 账号与安全子页（改密码） */
  @Builder
  accountDestination() {
    ProfileAccountPage({
      accountScroller: this.accountScroller,
      oldPassword: $oldPassword,
      newPassword: $newPassword,
      confirmNewPassword: $confirmNewPassword,
      passwordSaving: $passwordSaving,
      submitPasswordChange: (): Promise<void> => this.submitPasswordChange(),
      subpageContentTop: this.subpageContentTop,
      closeSubpage: (): void => this.closeSubpage()
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
      await this.apiService.logout();
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
    try {
      const current = AppStorage.get<string>('bika_current_version') ?? '';
      // 当前版本未知时不能拿历史兜底版本参与比较，否则可能提示错误的更新。
      AppUpdateService.isNewer(current, current);
      const release = await AppUpdateService.latest(ApiService.isProxyMode());
      if (this.visibleSubpage !== 'settings') {
        return;
      }
      if (AppUpdateService.isNewer(release.version, current)) {
        this.updateVersion = release.version;
        this.updateBody = release.body;
        this.updateUrl = release.url;
        this.aboutSheetKind = 0;
        this.showAboutSheet = true;
      } else {
        showImmersiveToast({ message: '暂无更新，当前版本 v' + current, duration: 2000 });
      }
    } catch (err) {
      if (this.visibleSubpage === 'settings') {
        showImmersiveToast({ message: (err as Error).message || '检查更新失败，请稍后重试', duration: 2500 });
      }
    } finally {
      this.checkingUpdate = false;
    }
  }

  /** 更新弹窗（Markdown 适配渲染） */
  @Builder
  updateSheet() {
    ProfileUpdateSheet({
      updateVersion: $updateVersion,
      showAboutSheet: $showAboutSheet,
      aboutSheetKind: $aboutSheetKind,
      updateUrl: $updateUrl,
      openExternalLink: (url: string): void => this.openExternalLink(url),
      updateBody: $updateBody
    })
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
    ProfileChangelogSheet({
      expandedAboutVersion: $expandedAboutVersion,
      aboutEntered: $aboutEntered
    })
  }

  /** 隐私政策弹窗 */
  @Builder
  privacySheet() {
    ProfilePrivacySheet()
  }
}
