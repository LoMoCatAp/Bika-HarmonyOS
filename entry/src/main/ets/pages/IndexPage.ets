import { router } from '@kit.ArkUI';
import { showImmersiveToast } from '../common/ImmersiveToast';
import { ApiService } from '../network/ApiService';
import { BikaComicDetail } from '../models/Comic';
import { CacheManager, HistoryItem } from '../common/CacheManager';
import { FollowUpdateManager } from '../common/FollowUpdateManager';
import { publishContinuationRoute, CONTINUATION_PROFILE_SUBPAGE_KEY, ContinuationRouteParams, ROUTE_HOME, ROUTE_CHANNEL_LIST, ROUTE_COMIC_DETAIL, ROUTE_READER, ROUTE_PROFILE_SUBPAGE, ROUTE_SEARCH, ROUTE_SEARCH_RESULT } from '../common/ContinuationState';
import { COLOR_PRIMARY, COLOR_BG, COLOR_TEXT_SECONDARY } from '../common/Constants';
import { HdsTabs, HdsTabsController, HdsAnimationMode, DividerMode, hdsMaterial } from '@kit.UIDesignKit';
import { HomePage } from '../features/home/HomePage';
import { ProfilePage } from '../features/profile/ProfilePage';
import { WidgetActionParams, SubpageOpenSignal } from '../models/IndexNavigation';

/** 主入口：页签、导航栏显隐、桌面卡片与接续路由。 */
@Entry
@Component
struct IndexPage {
  /** 桌面卡片点击深链：EntryAbility 每次写入都带新的 timestamp，用 @Watch 感知新事件 */
  @StorageLink('bika_widget_action') @Watch('onWidgetActionChanged') widgetAction: string = '';
  @StorageLink('bika_subpage_open') @Watch('onSubpageChanged') subpageOpen: boolean = false;
  @StorageLink('bika_goto_profile') @Watch('onGotoProfile') gotoProfile: number = 0;
  @StorageLink('bika_material_level') @Watch('onTabsMaterialChanged') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_material_rev') @Watch('onTabsMaterialChanged') materialRev: number = 0;
  @StorageLink('bika_animations') animationsEnabled: boolean = true;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @State currentTab: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  /** 只有安全回到根页才应用材质变更；进出子页不切换 HdsTabs 的 key。 */
  @State appliedTabsMaterial: string = 'EXQUISITE';
  @State appliedTabsRevision: number = 0;
  private tabsPageVisible: boolean = false;
  private tabsNodeReady: boolean = false;
  private tabsSyncGeneration: number = 0;
  private lastTabBarVisible: boolean | undefined = undefined;
  private channelOpening: boolean = false;
  private channelNavigationGeneration: number = 0;
  private apiService: ApiService = ApiService.getInstance();

  aboutToAppear(): void {
    // 首帧打点：用于证明 EntryAbility.onCreate 的同步置位发生在此之前（不打印敏感内容）
    console.info('[BikaAuth] IndexPage first frame: isLoggedIn='
      + (AppStorage.get<boolean>('isLoggedIn') === true ? 'true' : 'false')
      + ', auth_resolved=' + (AppStorage.get<boolean>('auth_resolved') === true ? 'true' : 'false'));
    AppStorage.setOrCreate('bika_material_level', this.materialLevel);
    this.appliedTabsMaterial = this.materialLevel;
    this.appliedTabsRevision = this.materialRev;
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

  /** 页面路由、内部子页和 HDS 节点重建共用同一个显隐判断。 */
  private shouldShowTabBar(): boolean {
    return this.tabsPageVisible && this.canSwipeRootTabs() && !this.channelOpening;
  }

  /** 子页内横滑交给导航返回；主页不受后台「我的」导航栈影响。 */
  private canSwipeRootTabs(): boolean {
    return this.currentTab === 0 || !this.subpageOpen;
  }

  private onRootTabChanged(index: number): void {
    this.currentTab = index;
    AppStorage.set('bika_active_tab', index);
    this.syncTabBarVisibility(true);
    this.publishCurrentRoute();
  }

  private applyTabBarVisibility(force: boolean = false): void {
    if (!this.tabsNodeReady) {
      return;
    }
    const visible = this.shouldShowTabBar();
    if (!force && visible === this.lastTabBarVisible) {
      return;
    }
    try {
      if (visible) {
        this.tabsController.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
      } else {
        this.tabsController.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
      }
      this.lastTabBarVisible = visible;
    } catch (_err) {
      this.lastTabBarVisible = undefined;
      console.warn('[IndexPage] tab bar is not ready; retry on the next frame');
    }
  }

  /** 隐藏先执行；恢复等下一帧控制器重新绑定，过期帧不再改变新页面的状态。 */
  private syncTabBarVisibility(force: boolean = false): void {
    const generation = ++this.tabsSyncGeneration;
    if (!this.shouldShowTabBar()) {
      this.applyTabBarVisibility();
    }
    if (!this.tabsPageVisible) {
      return;
    }
    this.getUIContext().postFrameCallback({
      onFrame: (_time: number): void => {
        if (generation === this.tabsSyncGeneration && this.tabsPageVisible) {
          this.applyTabBarVisibility(force);
        }
      },
      onIdle: (_time: number): void => {}
    });
  }

  private applyPendingTabsMaterial(): boolean {
    if (!this.tabsPageVisible || this.subpageOpen || this.channelOpening) {
      return false;
    }
    if (this.appliedTabsMaterial === this.materialLevel && this.appliedTabsRevision === this.materialRev) {
      return false;
    }
    this.appliedTabsMaterial = this.materialLevel;
    this.appliedTabsRevision = this.materialRev;
    this.lastTabBarVisible = undefined;
    return true;
  }

  onTabsMaterialChanged(): void {
    if (this.applyPendingTabsMaterial()) {
      this.syncTabBarVisibility(true);
    }
  }

  private onTabsAppear(): void {
    this.tabsNodeReady = true;
    this.lastTabBarVisible = undefined;
    this.syncTabBarVisibility(true);
  }

  /** 子页仍在栈中时保持收起；仅回到根页才恢复并应用待处理的材质档位。 */
  onSubpageChanged(): void {
    const changed = this.applyPendingTabsMaterial();
    this.syncTabBarVisibility(changed);
  }

  private openChannel(label: string, kind: string): void {
    if (!this.tabsPageVisible || this.channelOpening) {
      return;
    }
    this.channelOpening = true;
    const generation = ++this.channelNavigationGeneration;
    this.syncTabBarVisibility();
    const navigate = (): void => {
      if (generation !== this.channelNavigationGeneration || !this.tabsPageVisible) {
        return;
      }
      const failed = (): void => {
        if (generation !== this.channelNavigationGeneration) {
          return;
        }
        this.channelOpening = false;
        this.syncTabBarVisibility(true);
        if (this.tabsPageVisible) {
          showImmersiveToast({ message: '频道打开失败，请重试', duration: 1600 });
        }
      };
      try {
        router.pushUrl({ url: 'pages/ChannelListPage', params: { label: label, kind: kind } }).catch(failed);
      } catch (_err) {
        failed();
      }
    };
    if (this.animationsEnabled) {
      // 先让底栏收起命令提交到一帧，再启动系统页面过渡，不添加固定毫秒延迟。
      this.getUIContext().postFrameCallback({
        onFrame: (_time: number): void => navigate(),
        onIdle: (_time: number): void => {}
      });
    } else {
      navigate();
    }
  }

  onPageHide(): void {
    this.tabsPageVisible = false;
    this.syncTabBarVisibility();
  }

  aboutToDisappear(): void {
    this.tabsPageVisible = false;
    this.tabsNodeReady = false;
    this.tabsSyncGeneration++;
    this.channelNavigationGeneration++;
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
        this.openChannel('推荐', 'recommend');
      } else if (action === 'open_leaderboard') {
        // 排行榜卡片顶部 → 榜单频道页
        this.openChannel('排行榜', 'leaderboard');
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
          this.openChannel('最近更新', 'recent');
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
      this.openChannel(p.label ?? '', p.kind ?? 'topic');
    } else if (route === ROUTE_PROFILE_SUBPAGE && (p.subpage ?? '').length > 0) {
      this.openProfileSubpage(p.subpage ?? '');
    } else if (route === ROUTE_SEARCH) {
      router.pushUrl({ url: 'pages/SearchPage' });
    } else if (route === ROUTE_SEARCH_RESULT && (p.keyword ?? '').length > 0) {
      router.pushUrl({
        url: 'pages/SearchResultPage',
        params: { keyword: p.keyword ?? '', searchKind: p.searchKind ?? 'keyword' }
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
    if (this.currentTab === 1 && subpage.length > 0) {
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
    this.tabsPageVisible = true;
    this.channelOpening = false;
    this.channelNavigationGeneration++;
    this.applyPendingTabsMaterial();
    this.syncTabBarVisibility(true);
    AppStorage.set('isLoggedIn', ApiService.getInstance().isLoggedIn());
    FollowUpdateManager.getInstance().checkForUpdates();
    // 冷启动时 onCreate 写入的卡片事件在此消费（此时页面与路由已就绪）
    this.consumeWidgetAction();
    // 应用接续：本页可见即发布「当前页面」（从子页返回时也会重新发布）
    this.publishCurrentRoute();
  }

  /** 沉浸光感档位映射 */
  private hdsMaterialLevel(): hdsMaterial.MaterialLevel {
    if (this.appliedTabsMaterial === 'EXQUISITE') {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (this.appliedTabsMaterial === 'SMOOTH') {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    if (this.appliedTabsMaterial === 'ADAPTIVE') {
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
        HomePage({ onOpenChannel: (label: string, kind: string): void => this.openChannel(label, kind) })
      }
      .tabBar(this.tabLabel(0, '首页', $r('sys.symbol.house')))

      TabContent() {
        ProfilePage()
      }
      .tabBar(this.tabLabel(1, '我的', $r('sys.symbol.person')))
    }
    // 显隐不改变组件身份；仅安全回到根页后，因真实材质变更重建。
    .key('hds_tabs_' + this.appliedTabsMaterial + '_' + this.appliedTabsRevision)
    .onAppear((): void => this.onTabsAppear())
    .barOverlap(true)
    .animationDuration(0)
    .scrollable(this.canSwipeRootTabs())
    .vertical(false)
    .barPosition(BarPosition.End)
    .divider({ mode: DividerMode.NONE })
    .barFloatingStyle({
      // 全屏窗口下抬起至手势条上方，再向下 10vp
      barBottomMargin: Math.max(0, this.bottomSafeHeight - 6),
      // 只移除颜色渐隐蒙版，保留原生模糊及默认采样范围。
      gradientMask: { maskColor: Color.Transparent },
      adaptToHandedness: true,
      lightColor: '#FF7CA8',
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: this.hdsMaterialLevel()
      }
    })
    .onChange((index: number): void => this.onRootTabChanged(index))
    .backgroundColor(COLOR_BG)
    .width('100%')
    .height('100%')
  }
}
