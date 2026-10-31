import { router, promptAction, curves, window, ComponentContent } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { navigationBlurTitleBar } from '../common/NavigationBlur';
import { systemShare } from '@kit.ShareKit';
import { showImmersiveToast } from '../common/ImmersiveToast';
import { ApiService } from '../network/ApiService';
import { ComicDetailViewModel, EpViewModel, ComicViewModel, ComicSearchKind, BikaComicSummary, BikaComment, buildImageUrl } from '../models/Comic';
import { CacheManager } from '../common/CacheManager';
import { ChapterUpdateBadge } from '../components/ChapterUpdateBadge';
import { DownloadManager } from '../common/DownloadManager';
import { publishContinuationRoute, ROUTE_COMIC_DETAIL } from '../common/ContinuationState';
import { NetImage } from '../components/NetImage';
import { ComicCard } from '../components/ComicCard';
import { ChapterDownloadSheet } from '../components/ChapterDownloadSheet';
import { ChannelControlCapsule } from '../components/ChannelControlCapsule';
import { compatibleSheetMaterial } from '../common/CompatibleMaterial';
import { DetailGlassCapsule, DetailBarBackground } from '../components/DetailGlassCapsule';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_TEXT_HINT,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_SECONDARY,
  COLOR_TEXT_DISABLED,
  COLOR_BG,
  COLOR_CARD,
  COLOR_INPUT_BG,
  COLOR_DIVIDER,
  COLOR_WHITE
} from '../common/Constants';

/**
 * 漫画详情页：固定顶部切换胶囊，三个独立内容区，底部阅读/下载操作。
 * 封面与氛围背景只属于详情页，章节和评论保留独立滚动位置。
 */

interface DetailRouterParams {
  comicId: string;
  comicTitle: string;
}

/** 阅读器路由参数 */
interface ReaderRouteParams {
  comicId: string;
  comicTitle: string;
  epsCount: number;
  currentOrder: number;
  localDir?: string;
  localCount?: number;
  coverUrl?: string;
}

@Builder
function detailCommentRefreshPlaceholder() {
  Row().width('100%').height(0)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
}

@Entry
@Component
struct ComicDetailPage {
  @State comic: ComicDetailViewModel | null = null;
  @State chapters: EpViewModel[] = [];
  @State recommendations: ComicViewModel[] = [];
  @State comments: BikaComment[] = [];
  @State commentPage: number = 1;
  @State commentHasMore: boolean = false;
  @State commentSort: string = 'dd';
  @State commentsLoading: boolean = false;
  /** 评论列表下拉刷新中 */
  @State commentsRefreshing: boolean = false;
  @State commentsPullOffset: number = 0;
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State comicTitle: string = '详情';
  @State isFavourited: boolean = false;
  @State isLiked: boolean = false;
  @State favLoading: boolean = false;
  @State currentTab: number = 0;
  /** 内容索引在原生过渡结束后同步，按钮选中态提前响应。 */
  @State contentTabIndex: number = 0;
  /** 底栏保留相同组件，用连续属性动画切换阅读/评论形态。 */
  @State bottomCommentProgress: number = 0;
  @State bottomControlsWidth: number = 0;
  /** 收藏/点赞弹簧 */
  @State favScale: number = 1;
  @State likeScale: number = 1;
  /** 下载弹窗与勾选 */
  @State showDownloadSheet: boolean = false;
  @State downloadSelected: number[] = [];
  /** 单例弹窗类型（download/comment），避免多个 bindSheet 互顶 */
  @State detailSheetKind: string = '';
  @State showDetailSheet: boolean = false;
  /** 评论交互 */
  @State showCommentSheet: boolean = false;
  @State commentInput: string = '';
  @State commentSending: boolean = false;
  @State replyTarget: BikaComment | null = null;
  @State expandedReplies: string[] = [];
  @State repliesMap: Record<string, BikaComment[]> = {};
  @State repliesLoadingId: string = '';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('bika_animations') animationsOn: boolean = true;
  @StorageProp('bika_color_mode') colorMode: string = 'system';
  @StorageProp('system_color_mode') systemColorMode: string = 'light';
  @State lastReadOrder: number = 0;
  @State readChapterOrders: number[] = [];
  @State updatedChapterOrders: number[] = [];
  @State detailTitleVisible: boolean = false;
  @State detailWidth: number = 360;
  @State detailTopInset: number = 0;
  @State detailBottomInset: number = 0;
  @State detailLeftInset: number = 0;
  @State detailRightInset: number = 0;
  private tabsController: TabsController = new TabsController();
  private readonly detailBarBackground: DetailBarBackground = new DetailBarBackground();
  private detailWindow: window.Window | undefined = undefined;
  private observingWindow: boolean = false;
  private detailWindowSizeListener = (_size: window.Size): void => this.updateDetailInsets();
  private detailAvoidAreaListener = (_options: window.AvoidAreaOptions): void => this.updateDetailInsets();
  private comicId: string = '';
  private detailRequestId: number = 0;
  private openingMetadataSearch: boolean = false;
  private apiService: ApiService = ApiService.getInstance();
  private cacheManager: CacheManager | null = null;
  private detailScroller: Scroller = new Scroller();
  private chapterScroller: Scroller = new Scroller();
  private commentScroller: Scroller = new Scroller();
  private commentRefreshContent: ComponentContent<Object> | undefined = undefined;

  /** 应用接续：本页可见即发布「当前页面」（从阅读器返回时也会重新发布） */
  onPageShow(): void {
    this.openingMetadataSearch = false;
    this.loadReadStatus();
    this.updateDetailInsets();
    publishContinuationRoute(ROUTE_COMIC_DETAIL, { comicId: this.comicId, comicTitle: this.comicTitle });
  }

  async aboutToAppear(): Promise<void> {
    this.commentRefreshContent = new ComponentContent(this.getUIContext(), wrapBuilder(detailCommentRefreshPlaceholder));
    this.observeDetailWindow();
    let params = router.getParams() as DetailRouterParams;
    if (params) {
      this.comicId = params.comicId;
      this.comicTitle = params.comicTitle || '详情';
    }
    this.cacheManager = await CacheManager.getInstance();
    this.loadDetail();
    this.loadComments();
  }

  aboutToDisappear(): void {
    this.detailRequestId++;
    this.commentRefreshContent?.dispose();
    this.commentRefreshContent = undefined;
    this.observingWindow = false;
    const win = this.detailWindow;
    this.detailWindow = undefined;
    if (win !== undefined) {
      try {
        win.off('windowSizeChange', this.detailWindowSizeListener);
        win.off('avoidAreaChange', this.detailAvoidAreaListener);
      } catch (err) {
        console.warn('[ComicDetailPage] remove window listeners failed: ' + JSON.stringify(err));
      }
    }
  }

  private observeDetailWindow(): void {
    this.detailTopInset = this.topSafeHeight;
    this.detailBottomInset = this.bottomSafeHeight;
    this.observingWindow = true;
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      if (!this.observingWindow) {
        return;
      }
      this.detailWindow = win;
      this.updateDetailInsets();
      win.on('windowSizeChange', this.detailWindowSizeListener);
      win.on('avoidAreaChange', this.detailAvoidAreaListener);
    }).catch((err: Error): void => {
      console.warn('[ComicDetailPage] window metrics unavailable: ' + JSON.stringify(err));
    });
  }

  private updateDetailInsets(): void {
    const win = this.detailWindow;
    if (win === undefined) {
      return;
    }
    const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const cutoutArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    const navigationArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.detailTopInset = this.getUIContext().px2vp(Math.max(systemArea.topRect.height, cutoutArea.topRect.height));
    this.detailBottomInset = this.getUIContext().px2vp(Math.max(
      systemArea.bottomRect.height, cutoutArea.bottomRect.height, navigationArea.bottomRect.height));
    this.detailLeftInset = this.getUIContext().px2vp(Math.max(
      systemArea.leftRect.width, cutoutArea.leftRect.width, navigationArea.leftRect.width));
    this.detailRightInset = this.getUIContext().px2vp(Math.max(
      systemArea.rightRect.width, cutoutArea.rightRect.width, navigationArea.rightRect.width));
  }

  private darkMode(): boolean {
    return this.colorMode === 'dark' || (this.colorMode === 'system' && this.systemColorMode === 'dark');
  }

  private topControlsHeight(): number {
    return this.detailTopInset + 112;
  }

  private detailTabCapsuleWidth(): number {
    // 在胶囊自己的 Navigation 上限宽，避免外层 maxWidth 与内部 100% 使用不同的百分比参照。
    return Math.max(0, Math.min(360, this.detailWidth - this.detailLeftInset - this.detailRightInset - 32));
  }

  private bottomControlsHeight(): number {
    return this.detailBottomInset + 68;
  }

  private setDetailTab(index: number): void {
    this.currentTab = index;
    const target: number = index === 2 ? 1 : 0;
    if (this.bottomCommentProgress === target) {
      return;
    }
    if (this.animationsOn) {
      animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
        this.bottomCommentProgress = target;
      });
    } else {
      this.bottomCommentProgress = target;
    }
  }

  private bottomControlsInnerWidth(): number {
    const width = this.bottomControlsWidth > 0 ? this.bottomControlsWidth : Math.min(this.detailWidth * 0.9, 480);
    return Math.max(0, width - this.detailLeftInset - this.detailRightInset - 32);
  }

  private bottomDownloadSpan(): number {
    return Math.min(64, this.bottomControlsInnerWidth()) * (1 - this.bottomCommentProgress);
  }

  private recommendationColumns(): string {
    const width = Math.min(840, this.detailWidth - this.detailLeftInset - this.detailRightInset);
    return width >= 760 ? '1fr 1fr 1fr 1fr' : width >= 560 ? '1fr 1fr 1fr' : '1fr 1fr';
  }

  private startReading(): void {
    if (this.chapters.length === 0) {
      showImmersiveToast({ message: this.isLoading ? '章节加载中' : '暂无章节', duration: 1600 });
      return;
    }
    const target = this.lastReadOrder > 0 ? this.lastReadOrder : this.chapters[0].order;
    const ep = this.chapters.find((chapter: EpViewModel): boolean => chapter.order === target);
    this.onChapterClick(ep ?? this.chapters[0]);
  }

  async loadDetail(): Promise<void> {
    const requestId = ++this.detailRequestId;
    const comicId = this.comicId;
    const account = this.cacheManager?.getEmail() ?? '';
    this.isLoading = true;
    this.errorMsg = '';
    try {
      let results = await Promise.all([
        this.apiService.getComicDetail(comicId),
        this.apiService.getAllEps(comicId)
      ]);
      if (!this.isCurrentDetailRequest(requestId, comicId, account)) {
        return;
      }
      this.comic = ComicDetailViewModel.fromDetail(results[0]);
      this.comicTitle = this.comic.title;
      this.isFavourited = !!results[0].isFavourite;
      this.isLiked = !!results[0].isLiked;
      let eps: EpViewModel[] = [];
      for (let doc of results[1]) {
        eps.push(EpViewModel.fromDoc(doc));
      }
      eps.sort((a: EpViewModel, b: EpViewModel) => a.order - b.order);
      this.chapters = eps;
      this.loadReadStatus();
      try {
        let recs = await this.apiService.getRecommendationsFor(comicId);
        if (recs.length === 0) {
          // 推荐接口未返回时回退到「全部最新」列表，保证详情页始终有相关作品
          let fallback = await this.apiService.getComics('', 'dd', 1);
          recs = fallback.comics.slice(0, 10);
        }
        if (this.isCurrentDetailRequest(requestId, comicId, account)) {
          this.recommendations = recs.map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
        }
      } catch (recErr) {
        console.warn('[ComicDetailPage] recommendations failed: ' + JSON.stringify(recErr));
      }
    } catch (err) {
      if (this.isCurrentDetailRequest(requestId, comicId, account)) {
        this.errorMsg = (err as Error).message || '加载失败';
        console.error('[ComicDetailPage] loadDetail error: ' + this.errorMsg);
      }
    } finally {
      if (this.isCurrentDetailRequest(requestId, comicId, account)) {
        this.isLoading = false;
      }
    }
  }

  private isCurrentDetailRequest(requestId: number, comicId: string, account: string): boolean {
    return requestId === this.detailRequestId && comicId === this.comicId
      && (this.cacheManager?.getEmail() ?? '') === account;
  }

  private openMetadataSearch(value: string, kind: ComicSearchKind): void {
    const keyword = value.trim();
    if (this.openingMetadataSearch || keyword.length === 0 || (kind === 'author' && keyword === '未知作者')) {
      return;
    }
    this.openingMetadataSearch = true;
    router.pushUrl({ url: 'pages/SearchResultPage', params: { keyword: keyword, searchKind: kind } })
      .catch((_err: Error): void => {
        this.openingMetadataSearch = false;
        showImmersiveToast({ message: '打开搜索失败，请重试', duration: 1600 });
      });
  }

  async loadComments(reset: boolean = true): Promise<void> {
    if (this.commentsLoading) {
      return;
    }
    this.commentsLoading = true;
    try {
      if (reset) {
        this.commentPage = 1;
      }
      let result = await this.apiService.getComicComments(this.comicId, this.commentPage);
      this.comments = reset ? result.docs : this.comments.concat(result.docs);
      this.commentHasMore = this.commentPage < result.pages;
      if (reset) {
        this.commentPage = 1;
      }
    } catch (err) {
      console.warn('[ComicDetailPage] comments failed: ' + JSON.stringify(err));
    } finally {
      this.commentsLoading = false;
    }
  }

  /**
   * 评论列表下拉刷新：重置到第一页重新拉取（与首屏加载共用 loadComments）。
   * 注意：进入 onRefreshing 时 Refresh 组件已通过 $$ 把 commentsRefreshing 置为 true，
   * 这里不能用它做自守卫（否则直接 return 且永不复位，指示器会一直悬停）。
   */
  private async refreshComments(): Promise<void> {
    try {
      this.commentPage = 1;
      await this.loadComments(true);
    } finally {
      this.commentsRefreshing = false;
    }
  }

  /** 按排序方式返回评论列表（客户端排序：最新/最早/最多赞） */
  sortedComments(): BikaComment[] {
    let list = this.comments.slice(0);
    if (this.commentSort === 'da') {
      list.sort((a: BikaComment, b: BikaComment) =>
        (a.created_at ?? '').localeCompare(b.created_at ?? ''));
    } else if (this.commentSort === 'ld') {
      list.sort((a: BikaComment, b: BikaComment) => (b.likesCount ?? 0) - (a.likesCount ?? 0));
    } else {
      list.sort((a: BikaComment, b: BikaComment) =>
        (b.created_at ?? '').localeCompare(a.created_at ?? ''));
    }
    return list;
  }

  // ── 评论交互 ──

  /** 点赞/取消点赞一条评论（主评论或子回复） */
  async onToggleCommentLike(commentId: string, isChild: boolean): Promise<void> {
    try {
      await this.apiService.toggleCommentLike(commentId);
      if (isChild) {
        let parentId = this.findParentId(commentId);
        if (parentId.length === 0) {
          return;
        }
        let replies = this.repliesMap[parentId] ? this.repliesMap[parentId] : [];
        for (let i = 0; i < replies.length; i++) {
          if (replies[i]._id === commentId) {
            let updated: BikaComment = {
              _id: replies[i]._id,
              content: replies[i].content,
              likesCount: replies[i].isLiked ? (replies[i].likesCount ?? 1) - 1 : (replies[i].likesCount ?? 0) + 1,
              totalComments: replies[i].totalComments,
              created_at: replies[i].created_at,
              isLiked: !replies[i].isLiked,
              _user: replies[i]._user
            };
            replies[i] = updated;
            let newMap: Record<string, BikaComment[]> = {};
            let keys = Object.keys(this.repliesMap);
            for (let k of keys) {
              newMap[k] = this.repliesMap[k];
            }
            newMap[parentId] = replies.slice();
            this.repliesMap = newMap;
            break;
          }
        }
      } else {
        for (let i = 0; i < this.comments.length; i++) {
          if (this.comments[i]._id === commentId) {
            let updated: BikaComment = {
              _id: this.comments[i]._id,
              content: this.comments[i].content,
              likesCount: this.comments[i].isLiked ? (this.comments[i].likesCount ?? 1) - 1 : (this.comments[i].likesCount ?? 0) + 1,
              totalComments: this.comments[i].totalComments,
              created_at: this.comments[i].created_at,
              isLiked: !this.comments[i].isLiked,
              _user: this.comments[i]._user
            };
            this.comments[i] = updated;
            break;
          }
        }
      }
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '操作失败', duration: 2000 });
    }
  }

  /** 找到某条子回复所属的主评论 id */
  private findParentId(childId: string): string {
    let keys = Object.keys(this.repliesMap);
    for (let k of keys) {
      let list = this.repliesMap[k];
      for (let r of list) {
        if (r._id === childId) {
          return k;
        }
      }
    }
    return '';
  }

  /** 展开/收起评论的子回复 */
  async toggleReplies(commentId: string): Promise<void> {
    let idx = this.expandedReplies.indexOf(commentId);
    if (idx >= 0) {
      this.expandedReplies.splice(idx, 1);
      return;
    }
    this.expandedReplies.push(commentId);
    if (!this.repliesMap[commentId]) {
      this.repliesLoadingId = commentId;
      try {
        let children = await this.apiService.getCommentChildren(commentId, 1);
        let newMap: Record<string, BikaComment[]> = {};
        let keys = Object.keys(this.repliesMap);
        for (let k of keys) {
          newMap[k] = this.repliesMap[k];
        }
        newMap[commentId] = children;
        this.repliesMap = newMap;
      } catch (err) {
        console.warn('[ComicDetailPage] replies failed: ' + JSON.stringify(err));
      } finally {
        this.repliesLoadingId = '';
      }
    }
  }

  /** 打开评论输入弹窗（replyTarget 为 null 时发表新评论） */
  openCommentSheet(replyTarget: BikaComment | null): void {
    if (!this.apiService.isLoggedIn()) {
      router.pushUrl({ url: 'pages/LoginPage' });
      return;
    }
    this.replyTarget = replyTarget;
    this.commentInput = '';
    this.showCommentSheet = true;
    this.detailSheetKind = 'comment';
    this.showDetailSheet = true;
  }

  /** 发送评论/回复 */
  async sendComment(): Promise<void> {
    let content = this.commentInput.trim();
    if (content.length === 0) {
      showImmersiveToast({ message: '内容不能为空', duration: 1600 });
      return;
    }
    if (this.commentSending) {
      return;
    }
    this.commentSending = true;
    try {
      if (this.replyTarget) {
        await this.apiService.replyToComment(this.replyTarget._id, content);
        showImmersiveToast({ message: '回复成功', duration: 1600 });
        // 若该评论已展开子回复，刷新
        let parentId = this.replyTarget._id;
        if (this.expandedReplies.indexOf(parentId) >= 0) {
          let newMap: Record<string, BikaComment[]> = {};
          let keys = Object.keys(this.repliesMap);
          for (let k of keys) {
            if (k !== parentId) {
              newMap[k] = this.repliesMap[k];
            }
          }
          let children = await this.apiService.getCommentChildren(parentId, 1);
          newMap[parentId] = children;
          this.repliesMap = newMap;
          for (let i = 0; i < this.comments.length; i++) {
            if (this.comments[i]._id === parentId) {
              let updated: BikaComment = {
                _id: this.comments[i]._id,
                content: this.comments[i].content,
                likesCount: this.comments[i].likesCount,
                totalComments: (this.comments[i].totalComments ?? 0) + 1,
                created_at: this.comments[i].created_at,
                isLiked: this.comments[i].isLiked,
                _user: this.comments[i]._user
              };
              this.comments[i] = updated;
              break;
            }
          }
        }
      } else {
        await this.apiService.postComicComment(this.comicId, content);
        showImmersiveToast({ message: '评论成功', duration: 1600 });
        await this.loadComments();
      }
      this.showCommentSheet = false;
      this.showDetailSheet = false;
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '发送失败', duration: 2000 });
    } finally {
      this.commentSending = false;
    }
  }

  loadReadStatus(): void {
    if (!this.cacheManager) {
      return;
    }
    this.lastReadOrder = this.cacheManager.getReadProgress(this.comicId);
    this.readChapterOrders = this.cacheManager.getReadChapters(this.comicId);
    this.updatedChapterOrders = this.comic === null ? []
      : this.cacheManager.getUpdatedChapterOrders(this.comicId, this.chapters, this.comic.epsCount);
  }

  onChapterClick(ep: EpViewModel): void {
    // 已下载的话走本地离线阅读
    let task = DownloadManager.getInstance().hasTask(this.comicId, ep.order);
    let eps = this.chapters.length;
    if (eps === 0) {
      // 章节列表未加载（离线/失败）时，按已下载任务数估算总话数，保证翻话按钮可用
      let tasks = DownloadManager.getInstance().getTasks();
      let maxOrder = 0;
      for (let t of tasks) {
        if (t.comicId === this.comicId && t.chapterOrder > maxOrder) {
          maxOrder = t.chapterOrder;
        }
      }
      eps = maxOrder;
    }
    let params: ReaderRouteParams = {
      comicId: this.comicId,
      comicTitle: this.comicTitle,
      epsCount: eps,
      currentOrder: ep.order,
      coverUrl: this.comic !== null ? this.comic.coverUrl : ''
    };
    if (task !== undefined && task.status === 'completed') {
      params.localDir = task.dir;
      params.localCount = task.total;
    }
    router.pushUrl({
      url: 'pages/ReaderPage',
      params: params
    });
  }

  /** 收藏/点赞弹簧（动画开关关闭时直接复位） */
  private springPop(which: number): void {
    let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
    if (!animOn) {
      if (which === 0) {
        this.favScale = 1;
      } else {
        this.likeScale = 1;
      }
      return;
    }
    if (which === 0) {
      this.favScale = 1.35;
    } else {
      this.likeScale = 1.35;
    }
    animateTo({ curve: curves.springMotion(0.6, 0.9), duration: 600 }, () => {
      if (which === 0) {
        this.favScale = 1;
      } else {
        this.likeScale = 1;
      }
    });
  }

  async onToggleFavourite(): Promise<void> {
    if (this.favLoading) {
      return;
    }
    this.favLoading = true;
    try {
      await this.apiService.toggleFavourite(this.comicId, this.isFavourited);
      this.isFavourited = !this.isFavourited;
      this.springPop(0);
      showImmersiveToast({
        message: this.isFavourited ? '已收藏' : '已取消收藏',
        duration: 2000
      });
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '操作失败', duration: 2000 });
    } finally {
      this.favLoading = false;
    }
  }

  async onToggleLike(): Promise<void> {
    if (this.favLoading) {
      return;
    }
    this.favLoading = true;
    try {
      await this.apiService.toggleLike(this.comicId);
      this.isLiked = !this.isLiked;
      this.springPop(1);
      showImmersiveToast({ message: this.isLiked ? '已点赞' : '已取消点赞', duration: 2000 });
    } catch (err) {
      showImmersiveToast({ message: (err as Error).message || '操作失败', duration: 2000 });
    } finally {
      this.favLoading = false;
    }
  }

  /** 分享漫画：ShareKit systemShare 系统分享面板 */
  private async shareComic(): Promise<void> {
    let author = this.comic !== null && this.comic.author.length > 0 ? this.comic.author : '佚名';
    let text = '【Bika】《' + this.comicTitle + '》（ID：' + this.comicId + '）作者：' + author +
      ' https://www.picacomic.com';
    let record: systemShare.SharedRecord = {
      utd: 'general.text',
      content: text,
      title: '分享漫画《' + this.comicTitle + '》',
      label: 'TEXT',
      description: '哔咔漫画分享'
    };
    try {
      let sharedData = new systemShare.SharedData(record);
      let controller = new systemShare.ShareController(sharedData);
      await controller.show(getContext(this) as common.UIAbilityContext, {
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (err) {
      console.warn('[ComicDetailPage] share panel failed: ' + JSON.stringify(err));
      showImmersiveToast({ message: '无法拉起分享面板', duration: 1600 });
    }
  }

  /** 封面背景在详情自己的滚动容器里，与章节/评论完全隔离。 */
  @Builder
  detailBackdrop() {
    if (this.comic !== null) {
      ForEach([this.comic.coverUrl], (url: string): void => {
        NetImage({ src: url, fit: ImageFit.Cover, fillParent: true })
          .width('100%')
          .height(this.topControlsHeight() + 264)
          .blur(40)
          .opacity(this.darkMode() ? 0.24 : 0.28)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no-hide-descendants')
      }, (url: string): string => url)
      Row()
        .width('100%')
        .height(this.topControlsHeight() + 280)
        .linearGradient({ angle: 180, colors: [[Color.Transparent, 0.25], [COLOR_BG, 1]] })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  detailHero() {
    if (this.comic !== null) {
      Row({ space: 18 }) {
        ForEach([this.comic.coverUrl], (url: string): void => {
          NetImage({ src: url, fit: ImageFit.Cover, radius: 14, fillParent: true })
            .width(112)
            .height(156)
        }, (url: string): string => url)
        Column({ space: 8 }) {
          Text(this.comic.title)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(29)
          Text(this.comic.author)
            .fontSize(13)
            .fontColor(this.comic.author === '未知作者' ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY)
            .maxLines(2)
            .decoration({ type: this.comic.author === '未知作者' ? TextDecorationType.None : TextDecorationType.Underline })
            .enabled(this.comic.author !== '未知作者')
            .accessibilityText('搜索作者：' + this.comic.author)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.97 : 1 })
            .onClick((): void => { this.openMetadataSearch(this.comic?.author ?? '', 'author'); })
          Text((this.comic.finished ? '已完结' : '连载中') + ' · 共 ' + this.chapters.length + ' 话')
            .fontSize(12)
            .fontColor(this.comic.finished ? COLOR_TEXT_HINT : COLOR_PRIMARY)
          Text('观看 ' + this.comic.totalViews + ' · 收藏 ' + this.comic.totalLikes)
            .fontSize(12)
            .fontColor(COLOR_TEXT_HINT)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 20, right: 20, top: 12, bottom: 20 })
    }
  }

  @Builder
  metadataSearchTag(value: string, kind: ComicSearchKind) {
    Text(value)
      .fontSize(12)
      .fontColor(COLOR_PRIMARY)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(COLOR_PRIMARY_TINT)
      .borderRadius(10)
      .margin({ right: 8, bottom: 8 })
      .constraintSize({ maxWidth: '100%' })
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .accessibilityText((kind === 'category' ? '搜索分类：' : '搜索标签：') + value)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.96 : 1 })
      .onClick((): void => { this.openMetadataSearch(value, kind); })
  }

  @Builder
  detailTab() {
    Scroll(this.detailScroller) {
      Stack({ alignContent: Alignment.Top }) {
        this.detailBackdrop()
        Column() {
          if (this.errorMsg.length > 0 && this.comic === null) {
            Column({ space: 12 }) {
              Text(this.errorMsg).fontSize(14).fontColor(COLOR_TEXT_HINT)
              Button('重新加载', { type: ButtonType.Normal })
                .fontSize(13)
                .fontColor(COLOR_PRIMARY)
                .backgroundColor(COLOR_PRIMARY_TINT)
                .borderRadius(18)
                .height(36)
                .onClick((): void => { this.loadDetail(); })
            }
            .width('100%')
            .padding({ top: 80, bottom: 80 })
          } else if (this.comic !== null) {
            this.detailHero()
            Column({ space: 12 }) {
              Row() {
                Text('作品简介')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                  .layoutWeight(1)
                Button({ type: ButtonType.Capsule }) {
                  Row({ space: 5 }) {
                    SymbolGlyph($r('sys.symbol.heart'))
                      .fontSize(17)
                      .fontColor([this.isLiked ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
                    Text(this.isLiked ? '已点赞' : '点赞')
                      .fontSize(13)
                      .fontColor(this.isLiked ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
                  }
                }
                .height(36)
                .padding({ left: 10, right: 10 })
                .backgroundColor(Color.Transparent)
                .scale({ x: this.likeScale, y: this.likeScale })
                .enabled(!this.favLoading)
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.96 : 1 })
                .onClick((): void => { this.onToggleLike(); })
              }
              .width('100%')
              if (this.comic.description.length > 0) {
                Text(this.comic.description)
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_SECONDARY)
                  .lineHeight(23)
                  .width('100%')
              }
              if (this.comic.categories.length > 0) {
                Text('分类').fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
                Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                  ForEach(this.comic.categories, (cat: string): void => {
                    this.metadataSearchTag(cat, 'category')
                  }, (cat: string): string => cat)
                }
                .width('100%')
              }
              if (this.comic.tags.length > 0) {
                Text('标签').fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
                Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                  ForEach(this.comic.tags, (tag: string): void => {
                    this.metadataSearchTag(tag, 'tag')
                  }, (tag: string): string => tag)
                }
                .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 20, right: 20, top: 4 })
            if (this.recommendations.length > 0) {
              Column() {
                Text('推荐')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                  .margin({ bottom: 12 })
                Grid() {
                  ForEach(this.recommendations, (rec: ComicViewModel): void => {
                    GridItem() { ComicCard({ comic: rec }) }
                      .onClick((): void => {
                        this.comicId = rec.id;
                        this.comicTitle = rec.title;
                        this.comic = null;
                        this.chapters = [];
                        this.recommendations = [];
                        this.comments = [];
                        this.lastReadOrder = 0;
                        this.readChapterOrders = [];
                        this.updatedChapterOrders = [];
                        this.detailTitleVisible = false;
                        this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0 });
                        this.loadDetail();
                        this.loadComments();
                      })
                  }, (rec: ComicViewModel): string => rec.id)
                }
                .columnsTemplate(this.recommendationColumns())
                .columnsGap(10)
                .rowsGap(12)
                .enableScrollInteraction(false)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 20, right: 20, top: 20 })
            }
          } else {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(COLOR_PRIMARY)
              .margin({ top: 100, bottom: 100 })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 840 })
        .padding({ top: this.topControlsHeight() + 8, bottom: this.bottomControlsHeight() + 16,
          left: this.detailLeftInset, right: this.detailRightInset })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .clip(false)
      .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor(Color.Transparent)
    .onDidScroll((): void => {
      const visible = this.detailScroller.currentOffset().yOffset > 100;
      if (this.detailTitleVisible !== visible) {
        this.detailTitleVisible = visible;
      }
    })
  }

  private epDownloaded(order: number): boolean {
    let t = DownloadManager.getInstance().hasTask(this.comicId, order);
    return t !== undefined && t.status === 'completed';
  }

  private epDownloadIcon(order: number): Resource {
    let t = DownloadManager.getInstance().hasTask(this.comicId, order);
    if (t !== undefined) {
      if (t.status === 'completed') {
        return $r('sys.symbol.checkmark_circle');
      }
      return $r('sys.symbol.arrow_down_circle');
    }
    return $r('sys.symbol.square_and_arrow_down');
  }

  private async onDownloadEp(ep: EpViewModel): Promise<void> {
    if (!this.comic) {
      return;
    }
    let existing = DownloadManager.getInstance().hasTask(this.comicId, ep.order);
    if (existing && existing.status === 'completed') {
      showImmersiveToast({ message: '该话已下载', duration: 1600 });
      return;
    }
    if (existing && (existing.status === 'waiting' || existing.status === 'downloading')) {
      showImmersiveToast({ message: '该话已在下载队列', duration: 1600 });
      return;
    }
    DownloadManager.getInstance().addTask(
      this.comicId, this.comic.title, this.comic.coverUrl,
      this.comic.description, this.comic.author, ep.order, ep.title);
    showImmersiveToast({ message: '已加入下载队列', duration: 1600 });
  }

  /** 打开下载选择弹窗 */
  private openDownloadSheet(): void {
    this.downloadSelected = [];
    this.showDownloadSheet = true;
    this.detailSheetKind = 'download';
    this.showDetailSheet = true;
  }

  /** 开始下载所选章节（同步入队，不阻塞 UI） */
  private startDownloadSelected(): void {
    if (!this.comic || this.downloadSelected.length === 0) {
      return;
    }
    let count = 0;
    for (let order of this.downloadSelected) {
      let ep = this.chapters.find((e: EpViewModel) => e.order === order);
      if (!ep) {
        continue;
      }
      let existing = DownloadManager.getInstance().hasTask(this.comicId, order);
      if (!existing) {
        DownloadManager.getInstance().addTask(
          this.comicId, this.comic.title, this.comic.coverUrl,
          this.comic.description, this.comic.author, order, ep.title);
        count++;
      }
    }
    this.showDownloadSheet = false;
    this.showDetailSheet = false;
    showImmersiveToast({ message: count > 0 ? '已加入 ' + count + ' 话到下载队列' : '所选章节已在队列中', duration: 2000 });
  }



  /** 章节 Tab：独立列表，不包含封面与作品信息。 */
  @Builder
  chapterTab() {
    List({ scroller: this.chapterScroller, space: 0 }) {
      ListItem() {
        Text('共 ' + this.chapters.length + ' 话')
          .fontSize(13)
          .fontColor(COLOR_TEXT_HINT)
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 14 })
      }
      if (this.chapters.length === 0) {
        ListItem() {
          Column({ space: 10 }) {
            if (this.isLoading) {
              LoadingProgress().width(28).height(28).color(COLOR_PRIMARY)
            }
            Text(this.isLoading ? '章节加载中…' : (this.errorMsg.length > 0 ? this.errorMsg : '暂无章节'))
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60, bottom: 60 })
        }
      }
      ForEach(this.chapters, (ep: EpViewModel, index: number) => {
        ListItem() {
          Row() {
            Text(String(index + 1))
              .fontSize(13)
              .fontColor(COLOR_TEXT_HINT)
              .width(32)
              .textAlign(TextAlign.Center)
            Column({ space: 2 }) {
              Text(ep.title)
                .fontSize(15)
                .fontColor(this.readChapterOrders.indexOf(ep.order) >= 0 ? COLOR_TEXT_SECONDARY : COLOR_TEXT_TITLE)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.updatedChapterOrders.indexOf(ep.order) >= 0) {
              ChapterUpdateBadge()
            } else if (this.readChapterOrders.indexOf(ep.order) >= 0) {
              Text('已读')
                .fontSize(11)
                .fontColor(COLOR_PRIMARY)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(COLOR_PRIMARY_TINT)
                .borderRadius(8)
            }
            if (this.epDownloaded(ep.order)) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(16)
                .fontColor([COLOR_PRIMARY])
                .margin({ left: 8, right: 8 })
            }
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([COLOR_TEXT_DISABLED])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => this.onChapterClick(ep))
        }
        if (index < this.chapters.length - 1) {
          ListItem() {
            Divider().height(1).color(COLOR_DIVIDER).margin({ left: 48 })
          }
        }
      }, (ep: EpViewModel) => ep.id)
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.detailLeftInset + 16, right: this.detailRightInset + 16 })
    .contentStartOffset(this.topControlsHeight() + 8)
    .contentEndOffset(this.bottomControlsHeight() + 12)
    .scrollBar(BarState.Off)
    .backgroundColor(Color.Transparent)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .cachedCount(3, true)
    .clip(false)
  }

  /** 评论列表下拉刷新指示器：下拉/刷新中均显示主色 loading，深浅两模式都清晰 */
  @Builder
  commentsRefreshIndicator() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(COLOR_PRIMARY)
      Text(this.commentsRefreshing ? '正在刷新' : '下拉刷新')
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
    }
    .width('100%')
    .height(60)
    .padding({ top: 16 })
    .opacity(this.commentsRefreshing ? 1 : Math.min(1, Math.max(0, (this.commentsPullOffset - 24) / 24)))
    .position({ x: 0, y: this.topControlsHeight() + 56 + Math.max(0, (this.commentsPullOffset - 44) / 2) })
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
    .justifyContent(FlexAlign.Center)
  }

  /** 评论 Tab */
  @Builder
  commentTab() {
    Column() {
      Refresh({ refreshing: $$this.commentsRefreshing, refreshingContent: this.commentRefreshContent }) {
        List({ scroller: this.commentScroller, space: 0 }) {
          if (this.comments.length === 0) {
            ListItem() {
              if (this.commentsLoading) {
                // 首次加载：先显示加载指示器，加载结束后再决定展示空态还是列表
                Column({ space: 10 }) {
                  LoadingProgress()
                    .width(28)
                    .height(28)
                    .color(COLOR_PRIMARY)
                  Text('评论加载中…')
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .width('100%')
                .padding({ top: 80, bottom: 80 })
                .justifyContent(FlexAlign.Center)
              } else {
                Column({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.message'))
                    .fontSize(36)
                    .fontColor([COLOR_TEXT_DISABLED])
                  Text('暂无评论，来抢沙发')
                    .fontSize(14)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .width('100%')
                .padding({ top: 80, bottom: 80 })
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          ForEach(this.sortedComments(), (comment: BikaComment, index: number) => {
            ListItem() {
              this.commentItem(comment)
            }
            if (index < this.sortedComments().length - 1) {
              ListItem() {
                Divider().height(1).color(COLOR_DIVIDER).margin({ left: 64 })
              }
            }
          }, (comment: BikaComment) => comment._id)
          // 上拉加载更多：只有真正在加载时才显示指示器（加载完成/失败都会隐藏）
          if (this.commentsLoading && this.comments.length > 0) {
            ListItem() {
              Row({ space: 6 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(COLOR_PRIMARY)
                Text('加载中…')
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_HINT)
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(this.topControlsHeight() + 56)
        .contentEndOffset(this.bottomControlsHeight() + 12)
        .scrollBar(BarState.Off)
        .cachedCount(3, true)
        .clip(false)
        .backgroundColor(Color.Transparent)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onReachEnd(() => {
          if (this.commentHasMore && !this.commentsLoading) {
            this.commentPage++;
            this.loadComments(false);
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
      .refreshOffset(72)
      .clip(false)
      .onOffsetChange((offset: number): void => {
        this.commentsPullOffset = Number.isFinite(offset) ? Math.max(0, offset) : 0;
      })
      .onRefreshing(() => { this.refreshComments(); })

    }
    .width('100%')
    .height('100%')
    .padding({ left: this.detailLeftInset + 16, right: this.detailRightInset + 16 })
  }

  /** 排序胶囊与标题控件同为 HDS 模糊层上方的前景，文字保持清晰。 */
  @Builder
  commentSortControls() {
    Row({ space: 8 }) {
      ChannelControlCapsule({
        label: '最新', selected: this.commentSort === 'dd',
        onActivate: (): void => { this.commentSort = 'dd'; }
      })
      ChannelControlCapsule({
        label: '最早', selected: this.commentSort === 'da',
        onActivate: (): void => { this.commentSort = 'da'; }
      })
      ChannelControlCapsule({
        label: '最多赞', selected: this.commentSort === 'ld',
        onActivate: (): void => { this.commentSort = 'ld'; }
      })
    }
    .width('100%').height(44)
    .padding({ left: this.detailLeftInset + 16, right: this.detailRightInset + 16 })
    .position({ x: 0, y: this.topControlsHeight() + 8 })
    .zIndex(2)
    .transition(TransitionEffect.OPACITY)
    .animation({ duration: this.animationsOn ? 180 : 0, curve: Curve.EaseOut })
  }

  /** 单条评论（含子回复展开） */
  @Builder
  commentItem(comment: BikaComment) {
    Column({ space: 6 }) {
      Row() {
        if (comment._user && comment._user.avatar && comment._user.avatar.path) {
          NetImage({
            src: buildImageUrl(comment._user.avatar),
            fit: ImageFit.Cover,
            radius: 18,
            fillParent: true
          })
            .width(36)
            .height(36)
        } else {
          Image($r('app.media.ic_default_avatar'))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
        }

        Column({ space: 4 }) {
          Row() {
            Text(comment._user?.name ?? '匿名')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
            if (comment._user?.level) {
              Text('LV.' + comment._user.level)
                .fontSize(10)
                .fontColor(COLOR_PRIMARY)
                .margin({ left: 6 })
            }
          }
          Text(comment.content)
            .fontSize(14)
            .fontColor(COLOR_TEXT_TITLE)
          Row({ space: 14 }) {
            Text(comment.created_at ? comment.created_at.substring(0, 10) : '')
              .fontSize(11)
              .fontColor(COLOR_TEXT_HINT)
            Text('回复')
              .fontSize(11)
              .fontColor(COLOR_TEXT_SECONDARY)
              .onClick(() => this.openCommentSheet(comment))
            if ((comment.totalComments ?? 0) > 0) {
              Text('展开回复 (' + comment.totalComments + ')')
                .fontSize(11)
                .fontColor(COLOR_PRIMARY)
                .onClick(() => this.toggleReplies(comment._id))
            }
            Blank()
            Row({ space: 3 }) {
              SymbolGlyph($r(comment.isLiked ? 'sys.symbol.heart_fill' : 'sys.symbol.heart'))
                .fontSize(14)
                .fontColor([comment.isLiked ? COLOR_PRIMARY : COLOR_TEXT_HINT])
              Text('' + (comment.likesCount ?? 0))
                .fontSize(11)
                .fontColor(comment.isLiked ? COLOR_PRIMARY : COLOR_TEXT_HINT)
            }
            .onClick(() => this.onToggleCommentLike(comment._id, false))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 子回复区
      if (this.expandedReplies.indexOf(comment._id) >= 0) {
        if (this.repliesLoadingId === comment._id) {
          Row() {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(COLOR_PRIMARY)
            Text('加载回复中…')
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 48, top: 6, bottom: 6 })
        } else {
          this.repliesBlock(this.repliesMap[comment._id])
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /** 子回复列表块 */
  @Builder
  repliesBlock(replies: BikaComment[] | undefined) {
    Column({ space: 0 }) {
      if (replies && replies.length > 0) {
        ForEach(replies, (reply: BikaComment) => {
          Row() {
            Text(reply._user?.name ?? '匿名')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_PRIMARY)
            Text('：' + reply.content)
              .fontSize(12)
              .fontColor(COLOR_TEXT_TITLE)
              .layoutWeight(1)
            Row({ space: 3 }) {
              SymbolGlyph($r(reply.isLiked ? 'sys.symbol.heart_fill' : 'sys.symbol.heart'))
                .fontSize(12)
                .fontColor([reply.isLiked ? COLOR_PRIMARY : COLOR_TEXT_HINT])
              Text('' + (reply.likesCount ?? 0))
                .fontSize(10)
                .fontColor(reply.isLiked ? COLOR_PRIMARY : COLOR_TEXT_HINT)
            }
            .onClick(() => this.onToggleCommentLike(reply._id, true))
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ top: 6, bottom: 6 })
        }, (reply: BikaComment) => reply._id)
      } else {
        Text('暂无回复')
          .fontSize(12)
          .fontColor(COLOR_TEXT_HINT)
          .width('100%')
          .padding({ top: 6, bottom: 6 })
      }
    }
    .width('100%')
    .padding({ left: 48, right: 4, top: 2, bottom: 4 })
    .backgroundColor(COLOR_PRIMARY_TINT)
    .borderRadius(12)
  }

  @Builder
  detailBackAction() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(21).fontColor([COLOR_TEXT_TITLE])
    }
    .width(44).height(44)
    .backgroundColor(Color.Transparent)
    .accessibilityText('返回')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
    .onClick((): void => router.back())
  }

  @Builder
  detailTopActions() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(20)
          .fontColor([this.isFavourited ? COLOR_PRIMARY : COLOR_TEXT_TITLE])
          .scale({ x: this.favScale, y: this.favScale })
      }
      .width(44).height(44)
      .backgroundColor(Color.Transparent)
      .enabled(this.comic !== null && !this.favLoading)
      .accessibilityText(this.isFavourited ? '取消收藏' : '收藏')
      .accessibilitySelected(this.isFavourited)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
      .onClick((): void => { this.onToggleFavourite(); })
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.share')).fontSize(20).fontColor([COLOR_TEXT_TITLE])
      }
      .width(44).height(44)
      .backgroundColor(Color.Transparent)
      .enabled(this.comic !== null)
      .accessibilityText('分享')
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
      .onClick((): void => { this.shareComic(); })
    }
    .width('100%').height(44)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  detailTabButton(label: string, index: number) {
    Button(label, { type: ButtonType.Capsule })
      .layoutWeight(1)
      .height(36)
      .fontSize(15)
      .maxFontScale(1.3)
      .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .backgroundColor(Color.Transparent)
      .accessibilitySelected(this.currentTab === index)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.97 : 1 })
      .onClick((): void => {
        if (this.currentTab !== index) {
          // 先同步胶囊选中态，再发起切页，不等待 onChange 动画结束回调。
          this.setDetailTab(index);
          this.tabsController.changeIndex(index);
        }
      })
  }

  @Builder
  detailTabCapsule() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('33.33%')
        .height(36)
        .borderRadius(18)
        .backgroundColor(COLOR_PRIMARY_TINT)
        .translate({ x: (this.currentTab * 100) + '%' })
        .animation({ duration: this.animationsOn ? 180 : 0, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)
      Row() {
        this.detailTabButton('详情', 0)
        this.detailTabButton('章节', 1)
        this.detailTabButton('评论', 2)
      }
      .width('100%').height(36)
    }
    .width('100%').height(44)
    .padding(4)
  }

  @Builder
  detailTopControls() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        DetailGlassCapsule({ capsuleWidth: 44, content: (): void => { this.detailBackAction(); } })
        Text(this.comicTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .opacity(this.currentTab !== 0 || this.detailTitleVisible ? 1 : 0)
          .animation({ duration: this.animationsOn ? 180 : 0, curve: Curve.EaseOut })
        DetailGlassCapsule({ capsuleWidth: 96, content: (): void => { this.detailTopActions(); } })
      }
      .width('100%').height(44)
      Row() {
        DetailGlassCapsule({
          capsuleWidth: this.detailTabCapsuleWidth(),
          content: (): void => { this.detailTabCapsule(); }
        })
      }
      .width('100%').height(44)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(this.topControlsHeight())
    .padding({ top: this.detailTopInset + 4, bottom: 8,
      left: this.detailLeftInset + 16, right: this.detailRightInset + 16 })
  }

  @Builder
  detailReadAction() {
    Button({ type: ButtonType.Capsule }) {
      Stack() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(20)
            .fontColor([COLOR_PRIMARY])
          Text(this.lastReadOrder > 0 ? '继续阅读' : '开始阅读')
            .fontSize(16)
            .maxFontScale(1.3)
            .maxLines(1)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_PRIMARY)
          if (this.lastReadOrder > 0 && this.detailWidth - this.detailLeftInset - this.detailRightInset >= 340) {
            Text('第 ' + this.lastReadOrder + ' 话')
              .fontSize(12)
              .maxFontScale(1.3)
              .fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 12, right: 12 })
        .opacity(1 - this.bottomCommentProgress)
        .translate({ y: -6 * this.bottomCommentProgress })
        .accessibilityLevel('no-hide-descendants')
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(20)
            .fontColor([COLOR_PRIMARY])
          Text('写评论')
            .fontSize(16)
            .maxFontScale(1.3)
            .maxLines(1)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_PRIMARY)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 12, right: 12 })
        .opacity(this.bottomCommentProgress)
        .translate({ y: 6 * (1 - this.bottomCommentProgress) })
        .accessibilityLevel('no-hide-descendants')
      }
      .width('100%').height(52)
    }
    .width('100%').height(52)
    .backgroundColor(Color.Transparent)
    .accessibilityGroup(true)
    .accessibilityText(this.currentTab === 2 ? '写评论'
      : this.lastReadOrder > 0 ? '继续阅读，第' + this.lastReadOrder + '话' : '开始阅读')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.97 : 1 })
    .onClick((): void => {
      if (this.currentTab === 2) {
        this.openCommentSheet(null);
      } else {
        this.startReading();
      }
    })
  }

  @Builder
  detailDownloadAction() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.arrow_down_to_line')).fontSize(21).fontColor([COLOR_TEXT_TITLE])
    }
    .width(52).height(52)
    .backgroundColor(Color.Transparent)
    .enabled(this.currentTab !== 2 && this.chapters.length > 0)
    .accessibilityText('下载章节')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
    .onClick((): void => this.openDownloadSheet())
  }

  @Builder
  detailBottomControls() {
    Row() {
      DetailGlassCapsule({
        capsuleWidth: this.bottomControlsInnerWidth() - this.bottomDownloadSpan(), capsuleHeight: 52,
        content: (): void => { this.detailReadAction(); }
      })
      DetailGlassCapsule({
        capsuleWidth: this.bottomDownloadSpan() * 52 / 64, capsuleHeight: 52,
        content: (): void => { this.detailDownloadAction(); }
      })
        .margin({ left: this.bottomDownloadSpan() * 12 / 64 })
        .opacity(1 - this.bottomCommentProgress)
        .scale({ x: 1 - this.bottomCommentProgress * 0.1, y: 1 - this.bottomCommentProgress * 0.1 })
        .hitTestBehavior(this.currentTab === 2 ? HitTestMode.None : HitTestMode.Default)
        .accessibilityLevel(this.currentTab === 2 ? 'no-hide-descendants' : 'auto')
    }
    .width('90%')
    .constraintSize({ maxWidth: 480 })
    .height(this.bottomControlsHeight())
    .attributeModifier(this.detailBarBackground)
    .padding({ left: this.detailLeftInset + 16, right: this.detailRightInset + 16,
      top: 4, bottom: this.detailBottomInset + 12 })
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      const width = Number(size.width);
      if (Number.isFinite(width) && width > 0 && Math.abs(this.bottomControlsWidth - width) > 0.5) {
        this.bottomControlsWidth = width;
      }
    })
  }

  /** 在 Tabs 挂载后分批预加载，减少首次切换时的布局等待。 */
  private async preloadDetailTabs(): Promise<void> {
    try {
      await this.tabsController.preloadItems([1]);
      await this.tabsController.preloadItems([2]);
    } catch (err) {
      console.warn('[ComicDetailPage] tab preload skipped: ' + JSON.stringify(err));
    }
  }

  @Builder
  detailContentTabs() {
    Tabs({ index: this.contentTabIndex, controller: this.tabsController }) {
      TabContent() { this.detailTab() }
      TabContent() { this.chapterTab() }
      TabContent() { this.commentTab() }
    }
    .barHeight(0)
    .width('100%').height('100%')
    .animationCurve(Curve.EaseOut)
    .animationDuration(this.animationsOn ? 300 : 0)
    .backgroundColor(Color.Transparent)
    .onAppear((): void => { this.preloadDetailTabs(); })
    .onAnimationStart((_index: number, targetIndex: number): void => { this.setDetailTab(targetIndex); })
    .onAnimationEnd((index: number): void => {
      this.contentTabIndex = index;
      this.setDetailTab(index);
    })
    .onChange((index: number): void => {
      this.contentTabIndex = index;
      this.setDetailTab(index);
    })
  }

  /** 只占据模糊标题区；实际操作胶囊由同级前景单独绘制。 */
  @Builder
  detailBlurHeaderSlot() {
    Row().width('100%').height(112)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    Navigation() {
      Stack({ alignContent: Alignment.Top }) {
        HdsNavigation() {
          Tabs({ barPosition: BarPosition.End }) {
            TabContent() { this.detailContentTabs() }
              .tabBar(this.detailBottomControls())
          }
          .width('100%').height('100%')
          .barMode(BarMode.Fixed)
          .barHeight(this.bottomControlsHeight())
          .barOverlap(true)
          .barBackgroundColor(Color.Transparent)
          .barBackgroundEffect({ radius: 0, saturation: 1, brightness: 1, color: Color.Transparent })
          .divider(null)
          .fadingEdge(false)
          .scrollable(false)
          .animationDuration(0)
          .expandSafeArea([], [])
        }
        .width('100%').height('100%')
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(true)
        .titleBar(navigationBlurTitleBar((): void => { this.detailBlurHeaderSlot(); }))
        .bindToScrollable([this.currentTab === 0 ? this.detailScroller :
          this.currentTab === 1 ? this.chapterScroller : this.commentScroller])
        .backgroundColor(Color.Transparent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
        this.detailTopControls()
        if (this.currentTab === 2) {
          this.commentSortControls()
          this.commentsRefreshIndicator()
        }
      }
      .width('100%').height('100%')
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideBackButton(true)
    .hideToolBar(true)
    .backgroundColor(COLOR_BG)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      const width = Number(size.width);
      if (Number.isFinite(width) && width > 0) {
        this.detailWidth = width;
      }
    })
    .bindSheet($$this.showDetailSheet, this.detailUnifiedSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      // 系统 sheet 统一绘制表面与圆角，内容根容器不再叠加第二层表面。
      backgroundColor: COLOR_BG,
      systemMaterial: compatibleSheetMaterial(),
      blurStyle: BlurStyle.NONE,
      borderWidth: 0,
      showClose: false,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      // 下载内容自带顶部横条与标题，不再在它上方叠加系统标题区。
      title: this.detailSheetKind === 'comment'
        ? { title: this.replyTarget ? ('回复 @' + (this.replyTarget._user?.name ?? '匿名')) : '发表评论' }
        : undefined,
      onWillDismiss: (): void => {
        this.showDetailSheet = false;
      }
    })
    .width('100%')
    .height('100%')
  }

  /** 详情页弹窗统一分发（单 bindSheet 避免多实例互顶） */
  @Builder
  detailUnifiedSheet() {
    if (this.detailSheetKind === 'download') {
      this.downloadSheet()
    } else if (this.detailSheetKind === 'comment') {
      this.commentSheet()
    }
  }

  /** 评论输入弹窗（发表评论 / 回复某人） */
  @Builder
  commentSheet() {
    Column({ space: 10 }) {
      // 输入区收到约 4 行高（原 120 偏高，空态时整块留白显得头重脚轻）
      TextArea({ placeholder: '说点什么吧…', text: this.commentInput })
        .height(96)
        .width('100%')
        .fontSize(15)
        .fontColor(COLOR_TEXT_TITLE)
        .placeholderColor(COLOR_TEXT_HINT)
        // 输入框与系统弹窗表面区分，颜色随深浅主题切换。
        .backgroundColor(COLOR_INPUT_BG)
        .border({ width: 1, color: COLOR_DIVIDER })
        .borderRadius(14)
        .onChange((value: string) => {
          this.commentInput = value;
        })
      Row() {
        // 发送改为右下角紧凑胶囊（原先通栏 100% 宽 + 40 高，只承载两个控件时比例过重）
        Button(this.commentSending ? '发送中…' : '发送')
          .fontSize(15)
          .fontColor(COLOR_WHITE)
          .backgroundColor(this.commentSending ? COLOR_TEXT_DISABLED : COLOR_PRIMARY)
          .borderRadius(19)
          .width(96)
          .height(38)
          .onClick(() => this.sendComment())
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ bottom: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 下载选择弹窗（全选/清除 + 3 列等宽章节网格 + 开始下载） */
  @Builder
  downloadSheet() {
    ChapterDownloadSheet({
      chapters: this.chapters,
      selectedOrders: $downloadSelected,
      isDownloaded: (order: number): boolean => this.epDownloaded(order),
      onStart: (): void => this.startDownloadSelected()
    })
  }
}
