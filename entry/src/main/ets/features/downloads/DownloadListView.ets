import { router, promptAction } from '@kit.ArkUI';
import { showImmersiveToast, showImmersiveDialog } from '../../common/ImmersiveToast';
import { NetImage } from '../../components/NetImage';
import { DownloadManager, DownloadTask } from '../../common/DownloadManager';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_HINT, COLOR_TEXT_DISABLED, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_INPUT_BG, COLOR_DIVIDER } from '../../common/Constants';

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

@Component
export struct DownloadListView {
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
