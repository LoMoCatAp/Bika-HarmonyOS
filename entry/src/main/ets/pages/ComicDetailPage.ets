import { router, promptAction } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, DividerShowType, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import { ComicDetailViewModel, EpViewModel, ComicViewModel, BikaComicSummary, BikaComment, buildImageUrl } from '../models/Comic';
import { CacheManager } from '../common/CacheManager';
import { DownloadManager } from '../common/DownloadManager';
import { NetImage } from '../components/NetImage';
import { ComicCard } from '../components/ComicCard';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_TEXT_HINT,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_SECONDARY,
  COLOR_TEXT_DISABLED,
  COLOR_BG,
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_WHITE
} from '../common/Constants';

/**
 * 漫画详情页（
 * HDS 沉浸光感返回栏 + 详情/章节/评论三 Tab + 连贯布局）
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
}

@Entry
@Component
struct ComicDetailPage {
  @State comic: ComicDetailViewModel | null = null;
  @State chapters: EpViewModel[] = [];
  @State recommendations: ComicViewModel[] = [];
  @State comments: BikaComment[] = [];
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State comicTitle: string = '详情';
  @State isFavourited: boolean = false;
  @State isLiked: boolean = false;
  @State favLoading: boolean = false;
  @State currentTab: number = 0;
  /** 下载弹窗与勾选 */
  @State showDownloadSheet: boolean = false;
  @State downloadSelected: number[] = [];
  /** 评论交互 */
  @State showCommentSheet: boolean = false;
  @State commentInput: string = '';
  @State commentSending: boolean = false;
  @State replyTarget: BikaComment | null = null;
  @State expandedReplies: string[] = [];
  @State repliesMap: Record<string, BikaComment[]> = {};
  @State repliesLoadingId: string = '';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  private lastReadOrder: number = 0;
  private comicId: string = '';
  private apiService: ApiService = ApiService.getInstance();
  private cacheManager: CacheManager | null = null;
  private detailScroller: Scroller = new Scroller();
  private chapterScroller: Scroller = new Scroller();
  private commentScroller: Scroller = new Scroller();
  private stack: NavPathStack = new NavPathStack();

  async aboutToAppear(): Promise<void> {
    let params = router.getParams() as DetailRouterParams;
    if (params) {
      this.comicId = params.comicId;
      this.comicTitle = params.comicTitle || '详情';
    }
    this.cacheManager = await CacheManager.getInstance();
    this.loadDetail();
    this.loadComments();
  }

  async loadDetail(): Promise<void> {
    this.isLoading = true;
    this.errorMsg = '';
    try {
      let results = await Promise.all([
        this.apiService.getComicDetail(this.comicId),
        this.apiService.getAllEps(this.comicId)
      ]);
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
        let recs = await this.apiService.getRecommendationsFor(this.comicId);
        this.recommendations = recs.map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      } catch (recErr) {
        console.warn('[ComicDetailPage] recommendations failed: ' + JSON.stringify(recErr));
      }
    } catch (err) {
      this.errorMsg = (err as Error).message || '加载失败';
      console.error('[ComicDetailPage] loadDetail error: ' + this.errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  async loadComments(): Promise<void> {
    try {
      this.comments = await this.apiService.getComicComments(this.comicId, 1);
    } catch (err) {
      console.warn('[ComicDetailPage] comments failed: ' + JSON.stringify(err));
    }
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
      promptAction.showToast({ message: (err as Error).message || '操作失败', duration: 2000 });
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
  }

  /** 发送评论/回复 */
  async sendComment(): Promise<void> {
    let content = this.commentInput.trim();
    if (content.length === 0) {
      promptAction.showToast({ message: '内容不能为空', duration: 1600 });
      return;
    }
    if (this.commentSending) {
      return;
    }
    this.commentSending = true;
    try {
      if (this.replyTarget) {
        await this.apiService.replyToComment(this.replyTarget._id, content);
        promptAction.showToast({ message: '回复成功', duration: 1600 });
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
        promptAction.showToast({ message: '评论成功', duration: 1600 });
        await this.loadComments();
      }
      this.showCommentSheet = false;
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '发送失败', duration: 2000 });
    } finally {
      this.commentSending = false;
    }
  }

  loadReadStatus(): void {
    if (!this.cacheManager) {
      return;
    }
    this.lastReadOrder = this.cacheManager.getReadProgress(this.comicId);
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
      currentOrder: ep.order
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

  async onToggleFavourite(): Promise<void> {
    if (this.favLoading) {
      return;
    }
    this.favLoading = true;
    try {
      await this.apiService.toggleFavourite(this.comicId, this.isFavourited);
      this.isFavourited = !this.isFavourited;
      promptAction.showToast({
        message: this.isFavourited ? '已收藏' : '已取消收藏',
        duration: 2000
      });
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '操作失败', duration: 2000 });
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
      promptAction.showToast({ message: this.isLiked ? '已点赞' : '已取消点赞', duration: 2000 });
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '操作失败', duration: 2000 });
    } finally {
      this.favLoading = false;
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

  /** 详情 Tab：连贯布局 */
  @Builder
  detailTab() {
    Scroll(this.detailScroller) {
      Column() {
        if (this.errorMsg.length > 0 && this.comic === null) {
          Column({ space: 12 }) {
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
            Button('重新加载', { type: ButtonType.Normal })
              .fontSize(13)
              .fontColor(COLOR_PRIMARY)
              .backgroundColor(COLOR_PRIMARY_TINT)
              .borderRadius(18)
              .height(36)
              .onClick(() => this.loadDetail())
          }
          .width('100%')
          .padding({ top: 120 })
        } else if (this.comic) {
          Row() {
            NetImage({
              src: this.comic.coverUrl,
              fit: ImageFit.Cover,
              radius: 14,
              fillParent: true
            })
              .width(120)
              .height(165)

            Column({ space: 6 }) {
              Text(this.comic.title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT_TITLE)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .lineHeight(24)

              Text(this.comic.author)
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)

              Text(this.comic.finished ? '已完结' : '连载中')
                .fontSize(12)
                .fontColor(this.comic.finished ? COLOR_TEXT_HINT : COLOR_PRIMARY)

              Text('观看 ' + this.comic.totalViews + ' · 收藏 ' + this.comic.totalLikes)
                .fontSize(12)
                .fontColor(COLOR_TEXT_HINT)
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })

          Row({ space: 12 }) {
            Button({ type: ButtonType.Normal }) {
              Text(this.isFavourited ? '已收藏' : '收藏')
                .fontSize(15)
                .fontColor(this.isFavourited ? COLOR_TEXT_SECONDARY : COLOR_WHITE)
            }
            .backgroundColor(this.isFavourited ? COLOR_CARD : COLOR_PRIMARY)
            .border({ width: 1, color: this.isFavourited ? COLOR_DIVIDER : COLOR_PRIMARY, radius: 22 })
            .layoutWeight(1)
            .height(44)
            .enabled(!this.favLoading)
            .onClick(() => this.onToggleFavourite())

            Button({ type: ButtonType.Normal }) {
              Text(this.isLiked ? '已点赞' : '点赞')
                .fontSize(15)
                .fontColor(this.isLiked ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            }
            .backgroundColor(COLOR_CARD)
            .border({ width: 1, color: this.isLiked ? COLOR_PRIMARY : COLOR_DIVIDER, radius: 22 })
            .layoutWeight(1)
            .height(44)
            .enabled(!this.favLoading)
            .onClick(() => this.onToggleLike())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })

          Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
            ForEach(this.comic.categories, (cat: string) => {
              Text(cat)
                .fontSize(12)
                .fontColor(COLOR_PRIMARY)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor(COLOR_PRIMARY_TINT)
                .borderRadius(12)
                .margin({ right: 8, bottom: 8 })
            }, (cat: string) => cat)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })

          if (this.comic.description.length > 0) {
            Text(this.comic.description)
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .lineHeight(20)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12 })
          }

          Button({ type: ButtonType.Normal }) {
            Text(this.lastReadOrder > 0 ? '继续阅读 第' + this.lastReadOrder + '话' : '开始阅读')
              .fontSize(16)
              .fontColor(COLOR_WHITE)
          }
          .width('92%')
          .height(48)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(24)
          .margin({ top: 16 })
          .onClick(() => {
            if (this.chapters.length > 0) {
              let target = this.lastReadOrder > 0 ? this.lastReadOrder : this.chapters[0].order;
              let ep = this.chapters.find((e: EpViewModel) => e.order === target);
              this.onChapterClick(ep ?? this.chapters[0]);
            } else {
              promptAction.showToast({ message: '暂无章节', duration: 1600 });
            }
          })

          if (this.recommendations.length > 0) {
            Column() {
              Text('相关推荐')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT_TITLE)
                .margin({ bottom: 10 })
              Grid() {
                ForEach(this.recommendations, (rec: ComicViewModel) => {
                  GridItem() {
                    ComicCard({ comic: rec })
                  }
                  .onClick(() => {
                    this.comicId = rec.id;
                    this.comicTitle = rec.title;
                    this.comic = null;
                    this.chapters = [];
                    this.recommendations = [];
                    this.comments = [];
                    this.loadDetail();
                    this.loadComments();
                  })
                }, (rec: ComicViewModel) => rec.id)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(10)
              .rowsGap(12)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, top: 20 })
          }

          Row().height(40)
        } else {
          Column() {
            LoadingProgress().width(40).height(40).color(COLOR_PRIMARY)
          }
          .width('100%')
          .padding({ top: 120 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(COLOR_BG)
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
      promptAction.showToast({ message: '该话已下载', duration: 1600 });
      return;
    }
    if (existing && (existing.status === 'waiting' || existing.status === 'downloading')) {
      promptAction.showToast({ message: '该话已在下载队列', duration: 1600 });
      return;
    }
    DownloadManager.getInstance().addTask(
      this.comicId, this.comic.title, this.comic.coverUrl,
      this.comic.description, this.comic.author, ep.order, ep.title);
    promptAction.showToast({ message: '已加入下载队列', duration: 1600 });
  }

  /** 打开下载选择弹窗 */
  private openDownloadSheet(): void {
    this.downloadSelected = [];
    this.showDownloadSheet = true;
  }

  /** 弹窗内勾选切换 */
  private toggleDownloadSelect(order: number): void {
    let idx = this.downloadSelected.indexOf(order);
    if (idx >= 0) {
      let next = this.downloadSelected.slice();
      next.splice(idx, 1);
      this.downloadSelected = next;
    } else {
      this.downloadSelected = this.downloadSelected.concat(order);
    }
  }

  /** 弹窗内全选/清除 */
  private selectAllChapters(): void {
    this.downloadSelected = this.chapters.map((ep: EpViewModel) => ep.order);
  }

  private clearChapterSelection(): void {
    this.downloadSelected = [];
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
    promptAction.showToast({ message: count > 0 ? '已加入 ' + count + ' 话到下载队列' : '所选章节已在队列中', duration: 2000 });
  }

  

  /** 章节 Tab */
  @Builder
  chapterTab() {
    Column() {
    Row({ space: 8 }) {
      Text('共 ' + this.chapters.length + ' 话')
        .fontSize(13)
        .fontColor(COLOR_TEXT_HINT)
        .layoutWeight(1)
      Button('下载', { type: ButtonType.Normal })
        .fontSize(13)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_PRIMARY_TINT)
        .borderRadius(16)
        .height(32)
        .padding({ left: 16, right: 16 })
        .onClick(() => this.openDownloadSheet())
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    List({ scroller: this.chapterScroller, space: 0 }) {
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
                .fontColor(this.lastReadOrder >= ep.order ? COLOR_TEXT_SECONDARY : COLOR_TEXT_TITLE)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.lastReadOrder >= ep.order) {
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
    .backgroundColor(COLOR_CARD)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_DIVIDER })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  /** 评论 Tab */
  @Builder
  commentTab() {
    Column() {
      List({ scroller: this.commentScroller, space: 0 }) {
        if (this.comments.length === 0) {
          ListItem() {
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
        ForEach(this.comments, (comment: BikaComment, index: number) => {
          ListItem() {
            this.commentItem(comment)
          }
          if (index < this.comments.length - 1) {
            ListItem() {
              Divider().height(1).color(COLOR_DIVIDER).margin({ left: 64 })
            }
          }
        }, (comment: BikaComment) => comment._id)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(COLOR_CARD)
      .borderRadius(18)
      .border({ width: 1, color: COLOR_DIVIDER })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 底部输入栏（bika 同款假输入框 → 弹层输入）
      Row({ space: 10 }) {
        Text('写下你的评论…')
          .fontSize(14)
          .fontColor(COLOR_TEXT_HINT)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([COLOR_PRIMARY])
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .backgroundColor(COLOR_CARD)
      .borderRadius(22)
      .border({ width: 1, color: COLOR_DIVIDER })
      .margin({ top: 10 })
      .onClick(() => this.openCommentSheet(null))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
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
  TabBuilder(label: string) {
    Text(label)
      .fontSize(15)
      .fontWeight(this.currentTab === (label === '详情' ? 0 : (label === '章节' ? 1 : 2)) ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.currentTab === (label === '详情' ? 0 : (label === '章节' ? 1 : 2)) ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  build() {
    HdsNavigation(this.stack) {
      Tabs({ index: this.currentTab, barPosition: BarPosition.Start }) {
        TabContent() {
          this.detailTab()
        }
        .tabBar(this.TabBuilder('详情'))

        TabContent() {
          this.chapterTab()
        }
        .tabBar(this.TabBuilder('章节'))

        TabContent() {
          this.commentTab()
        }
        .tabBar(this.TabBuilder('评论'))
      }
      .barMode(BarMode.Fixed)
      .barHeight(44)
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
      .onChange((index: number) => {
        this.currentTab = index;
      })
    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.immersiveTitleBar(this.comicTitle))
    .hideTitleBar(false)
    .hideBackButton(false)
    .bindSheet($$this.showDownloadSheet, this.downloadSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showDownloadSheet = false;
      }
    })
    .bindSheet($$this.showCommentSheet, this.commentSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: true,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      // 系统原生标题：关闭按钮自动避让，不与内容重叠
      title: { title: this.replyTarget ? ('回复 @' + (this.replyTarget._user?.name ?? '匿名')) : '发表评论' },
      onWillDismiss: (): void => {
        this.showCommentSheet = false;
      }
    })
    .width('100%')
    .height('100%')
  }

  /** 评论输入弹窗（发表评论 / 回复某人） */
  @Builder
  commentSheet() {
    Column({ space: 12 }) {
      TextArea({ placeholder: '说点什么吧…', text: this.commentInput })
        .height(120)
        .width('100%')
        .fontSize(15)
        .fontColor(COLOR_TEXT_TITLE)
        .placeholderColor(COLOR_TEXT_HINT)
        .backgroundColor(COLOR_BG)
        .borderRadius(14)
        .onChange((value: string) => {
          this.commentInput = value;
        })
      Row() {
        Button(this.commentSending ? '发送中…' : '发送')
          .fontSize(15)
          .fontColor(COLOR_WHITE)
          .backgroundColor(this.commentSending ? COLOR_TEXT_DISABLED : COLOR_PRIMARY)
          .borderRadius(20)
          .height(40)
          .layoutWeight(1)
          .onClick(() => this.sendComment())
      }
      .width('100%')
      .padding({ bottom: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 下载选择弹窗（bika 同款：全选/清除 + 3 列等宽章节网格 + 开始下载） */
  @Builder
  downloadSheet() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6 })
      Row() {
        Text('选择要下载的章节')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        Text('全选')
          .fontSize(14)
          .fontColor(COLOR_PRIMARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => this.selectAllChapters())
        Text('清除')
          .fontSize(14)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 8 })
          .onClick(() => this.clearChapterSelection())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })

      Scroll() {
        Grid() {
          ForEach(this.chapters, (ep: EpViewModel) => {
            GridItem() {
              Row({ space: 4 }) {
                if (this.epDownloaded(ep.order)) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(14)
                    .fontColor([this.downloadSelected.indexOf(ep.order) >= 0 ? COLOR_WHITE : COLOR_PRIMARY])
                }
                Text(ep.title.length > 0 ? ep.title : ('第' + ep.order + '话'))
                  .fontSize(13)
                  .fontColor(this.downloadSelected.indexOf(ep.order) >= 0 ? COLOR_WHITE : COLOR_TEXT_TITLE)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(this.epDownloaded(ep.order) ? 1 : 0)
              }
              .width('100%')
              .height(38)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 8, right: 8 })
              .backgroundColor(this.downloadSelected.indexOf(ep.order) >= 0 ? COLOR_PRIMARY : COLOR_CARD)
              .border({ width: 1, color: this.downloadSelected.indexOf(ep.order) >= 0 ? COLOR_PRIMARY : COLOR_DIVIDER, radius: 12 })
              .onClick(() => this.toggleDownloadSelect(ep.order))
            }
          }, (ep: EpViewModel) => String(ep.order))
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
      }
      .width('100%')
      .height(220)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Button(this.downloadSelected.length > 0
        ? '开始下载所选章节 (' + this.downloadSelected.length + ')'
        : '开始下载所选章节 (0)', { type: ButtonType.Normal })
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(COLOR_WHITE)
        .backgroundColor(this.downloadSelected.length > 0 ? COLOR_PRIMARY : COLOR_TEXT_DISABLED)
        .borderRadius(23)
        .enabled(this.downloadSelected.length > 0)
        .onClick(() => this.startDownloadSelected())
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 })
    .backgroundColor(COLOR_BG)
  }
}