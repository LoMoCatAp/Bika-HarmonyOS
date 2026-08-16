import { router, promptAction, window, display } from '@kit.ArkUI';
import { unifiedDataChannel } from '@kit.ArkData';
import { inputConsumer, KeyCode } from '@kit.InputKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { ApiService } from '../network/ApiService';
import { ImageUrlManager } from '../network/ImageUrlManager';
import { NetImage } from '../components/NetImage';
import { ImageLoader } from '../common/ImageLoader';
import { exportImagesZip, exportImagesPdf } from '../common/ExportUtils';
import { BikaPageDoc } from '../models/Comic';
import { CacheManager } from '../common/CacheManager';
import { DownloadManager } from '../common/DownloadManager';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_READER_TOOLBAR_BG,
  COLOR_READER_TOOLBAR_DISABLED,
  COLOR_READER_TOOLBAR_ACTIVE,
  COLOR_READER_TEXT_MUTED,
  COLOR_READER_BG,
  COLOR_TEXT_HINT,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_SECONDARY,
  COLOR_PLACEHOLDER,
  COLOR_CARD,
  COLOR_WHITE
} from '../common/Constants';

/**
 * 阅读器页面（
 * 5 种阅读模式 + 沉浸工具栏 + 设置面板）
 */

interface ReaderRouterParams {
  comicId: string;
  comicTitle: string;
  epsCount: number;
  currentOrder: number;
  localDir?: string;
  localCount?: number;
  coverUrl?: string;
}

/** 单张图片条目 */
interface ReaderImage {
  url: string;
  failed: boolean;
}

/** LazyForEach 数据源 */
class ImageDataSource implements IDataSource {
  private images: ReaderImage[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.images.length;
  }

  getData(index: number): ReaderImage {
    return this.images[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    let pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  reload(images: ReaderImage[]): void {
    this.images = images;
    this.listeners.forEach(l => l.onDataReloaded());
  }

  getAll(): ReaderImage[] {
    return this.images;
  }
}

@Entry
@Component
struct ReaderPage {
  @State showControls: boolean = true;
  @State currentVisibleIndex: number = 0;
  @State totalImages: number = 0;
  @State isLoading: boolean = true;
  @State errorText: string = '';
  @State currentOrder: number = 1;
  @State epsCount: number = 1;
  @State comicTitle: string = '';
  @State hasPrevChapter: boolean = false;
  @State hasNextChapter: boolean = false;
  @State isZoomed: boolean = false;
  @State zoomScale: number = 1.0;
  /** 阅读模式：0 左→右 1 右→左 2 上→下单页 3 条漫(有隙) 4 条漫(无缝，默认) */
  @State readingMode: number = 4;
  /** 音量键翻页开关 */
  @State volumeTurnEnabled: boolean = true;
  /** 动画总开关 */
  @StorageProp('bika_animations') animationsOn: boolean = true;
  /** 页码胶囊提示 */
  @State pageTipVisible: boolean = false;
  @State pageTipText: string = '';
  private pageTipTimer: number = -1;
  /** 底部弹窗（单例，按类型分发：settings/saveImage/export/saveFile） */
  @State showSheet: boolean = false;
  @State sheetKind: string = '';
  @State exporting: boolean = false;
  @State exportFilePath: string = '';
  @State exportFileName: string = '';
  /** 单页模式的当前页（切换模式时保留阅读位置） */
  @State swiperIndex: number = 0;
  /** 单页模式控制器（非受控 index，避免手势被状态回写打断） */
  private swiperController: SwiperController = new SwiperController();
  @State showSettings: boolean = false;
  /** 阅读亮度（0.1 ~ 1.0，-1 表示跟随系统） */
  @State readerBrightness: number = -1;
  /** 屏幕方向：system | portrait | landscape */
  @State orientation: string = 'system';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;

  private comicId: string = '';
  private coverUrl: string = '';
  private localDir: string = '';
  private localCount: number = 0;
  /** 是否本地离线阅读模式 */
  private localMode: boolean = false;
  private apiService: ApiService = ApiService.getInstance();
  private imageUrlManager: ImageUrlManager = ImageUrlManager.getInstance();
  private candidateUrls: string[][] = [];
  private candidateIndex: number[] = [];
  private generation: number = 0;
  private scrollScroller: Scroller = new Scroller();
  private listScroller: Scroller = new Scroller();
  private imageDataSource: ImageDataSource = new ImageDataSource();

  async aboutToAppear(): Promise<void> {
    let cache = await CacheManager.getInstance();
    this.volumeTurnEnabled = cache.getSetting('reader_volume_turn', 'true') === 'true';
    this.registerVolumeKeys();
    let params = router.getParams() as ReaderRouterParams;
    if (params) {
      this.comicId = params.comicId;
      this.comicTitle = params.comicTitle || '';
      this.coverUrl = params.coverUrl || '';
      this.epsCount = params.epsCount || 1;
      this.currentOrder = params.currentOrder || 1;
      if (params.localDir) {
        this.localMode = true;
        this.localDir = params.localDir;
        this.localCount = params.localCount || 0;
      }
    }
    this.updateChapterButtons();
    if (this.localMode) {
      this.loadLocalImages();
    } else {
      await this.loadImagesWithCache();
    }
  }

  /** 本地优先：当前话已下载则读本地，否则回退在线 */
  private loadLocalChapter(): void {
    let task = DownloadManager.getInstance().hasTask(this.comicId, this.currentOrder);
    if (task !== undefined && task.status === 'completed') {
      this.localDir = task.dir;
      this.localCount = task.total;
      this.loadLocalImages();
    } else {
      this.localMode = false;
      this.loadImagesWithCache();
    }
  }

  /** 本地下载模式：直接读取本地图片文件 */
  private loadLocalImages(): void {
    let list: ReaderImage[] = [];
    this.candidateUrls = [];
    this.candidateIndex = [];
    for (let i = 0; i < this.localCount; i++) {
      list.push({ url: 'file://' + this.localDir + '/' + i + '.jpg', failed: false });
    }
    this.imageDataSource.reload(list);
    this.totalImages = list.length;
    this.currentVisibleIndex = 0;
    this.swiperIndex = 0;
    this.isLoading = false;
    this.showControls = true;
    // 本地阅读同样记录进度与历史，并恢复上次阅读页
    CacheManager.getInstance().then(cache => {
      cache.saveReadProgress(this.comicId, this.currentOrder);
      cache.saveHistoryItem(this.comicId, this.comicTitle, this.currentOrder, this.coverUrl);
      this.restoreLastPage(cache);
    });
  }

  private async loadImagesWithCache(): Promise<void> {
    this.generation++;
    let gen = this.generation;
    this.isLoading = true;
    this.errorText = '';
    this.imageDataSource.reload([]);
    this.totalImages = 0;
    this.currentVisibleIndex = 0;
    this.swiperIndex = 0;

    try {
      let cache = await CacheManager.getInstance();
      let cached = cache.loadChapterPages(this.comicId, this.currentOrder);
      let docs: BikaPageDoc[] = [];
      if (cached) {
        try {
          docs = JSON.parse(cached) as BikaPageDoc[];
        } catch {
          docs = [];
        }
      }
      if (!docs || docs.length === 0) {
        docs = await this.apiService.getChapterPages(this.comicId, this.currentOrder);
        cache.saveChapterPages(this.comicId, this.currentOrder, JSON.stringify(docs));
      }
      if (gen !== this.generation) {
        return;
      }

      let list: ReaderImage[] = [];
      this.candidateUrls = [];
      this.candidateIndex = [];
      for (let doc of docs) {
        let candidates = this.imageUrlManager.buildCandidateUrls(doc.media.fileServer, doc.media.path);
        this.candidateUrls.push(candidates);
        this.candidateIndex.push(0);
        list.push({ url: candidates[0], failed: false });
      }
      this.imageDataSource.reload(list);
      this.totalImages = list.length;
      cache.saveReadProgress(this.comicId, this.currentOrder);
      cache.saveHistoryItem(this.comicId, this.comicTitle, this.currentOrder, this.coverUrl);
      this.restoreLastPage(cache);
    } catch (err) {
      if (gen !== this.generation) {
        return;
      }
      let errMsg = (err as Error).message || '加载图片失败，请重试';
      console.error('[ReaderPage] loadImages error:', errMsg);
      this.errorText = errMsg;
    } finally {
      if (gen === this.generation) {
        this.isLoading = false;
      }
    }
  }

  onBack(): void {
    router.back();
  }

  toggleControls(): void {
    if (this.animationsOn) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.showControls = !this.showControls;
      });
    } else {
      this.showControls = !this.showControls;
    }
  }

  private updateChapterButtons(): void {
    this.hasPrevChapter = this.currentOrder > 1;
    this.hasNextChapter = this.currentOrder < this.epsCount;
  }

  goPrevChapter(): void {
    if (!this.hasPrevChapter) {
      return;
    }
    this.persistPageIndex();
    this.currentOrder--;
    this.updateChapterButtons();
    this.zoomScale = 1.0;
    this.isZoomed = false;
    this.scrollScroller.scrollEdge(Edge.Top);
    if (this.localMode) {
      this.loadLocalChapter();
    } else {
      this.loadImagesWithCache();
    }
  }

  goNextChapter(): void {
    if (!this.hasNextChapter) {
      return;
    }
    this.persistPageIndex();
    this.currentOrder++;
    this.updateChapterButtons();
    this.zoomScale = 1.0;
    this.isZoomed = false;
    this.scrollScroller.scrollEdge(Edge.Top);
    if (this.localMode) {
      this.loadLocalChapter();
    } else {
      this.loadImagesWithCache();
    }
  }

  private onImageFailed(index: number): void {
    let candidates = this.candidateUrls[index] || [];
    let nextIdx = (this.candidateIndex[index] || 0) + 1;
    if (nextIdx < candidates.length) {
      console.warn('[ReaderPage] 图片加载失败，切换镜像 (' + (index + 1) + '/' + this.totalImages + ')');
      this.candidateIndex[index] = nextIdx;
      this.imageDataSource.getData(index).url = candidates[nextIdx];
      this.imageDataSource.reload(this.imageDataSource.getAll());
    } else {
      this.imageDataSource.getData(index).failed = true;
      this.imageDataSource.reload(this.imageDataSource.getAll());
    }
  }

  /** 阅读模式选项行 */
  @Builder
  ModeRow(mode: number, label: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(this.readingMode === mode ? COLOR_PRIMARY : COLOR_TEXT_TITLE)
        .layoutWeight(1)
      if (this.readingMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([COLOR_PRIMARY])
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 20, right: 20 })
    .onClick(() => {
      this.switchReadingMode(mode);
    })
  }

  /** 音量键回调（官方示例写法：具名回调，off 时精确移除） */
  private volumeUpCallback = (): void => {
    this.turnByVolume(1);
  };
  private volumeDownCallback = (): void => {
    this.turnByVolume(-1);
  };
  /** 上一次音量翻页时间（防重复事件） */
  private lastVolumeTurnAt: number = 0;

  /** 音量键翻页（音量上=下一页，音量下=上一页；可在设置中关闭） */
  private registerVolumeKeys(): void {
    if (!this.volumeTurnEnabled) {
      return;
    }
    try {
      let upOptions: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: 1,
        isRepeat: false
      };
      inputConsumer.on('keyPressed', upOptions, this.volumeUpCallback);
      let downOptions: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: 1,
        isRepeat: false
      };
      inputConsumer.on('keyPressed', downOptions, this.volumeDownCallback);
    } catch (err) {
      console.warn('[ReaderPage] volume key register failed: ' + JSON.stringify(err));
    }
  }

  /** 切换音量键翻页开关 */
  private toggleVolumeTurn(enabled: boolean): void {
    this.volumeTurnEnabled = enabled;
    CacheManager.getInstance().then(cache => {
      cache.saveSetting('reader_volume_turn', enabled ? 'true' : 'false');
    });
    if (!enabled) {
      this.unregisterVolumeKeys();
    } else {
      this.registerVolumeKeys();
    }
  }

  private unregisterVolumeKeys(): void {
    try {
      inputConsumer.off('keyPressed', this.volumeUpCallback);
      inputConsumer.off('keyPressed', this.volumeDownCallback);
    } catch (err) {
      console.warn('[ReaderPage] volume key unregister failed');
    }
  }

  /** 按音量方向翻页（防抖 300ms，弹窗打开时不翻页） */
  private turnByVolume(delta: number): void {
    if (this.showSheet) {
      return;
    }
    let now = Date.now();
    if (now - this.lastVolumeTurnAt < 300) {
      return;
    }
    this.lastVolumeTurnAt = now;
    if (this.totalImages <= 0) {
      return;
    }
    try {
      let index = this.readingMode <= 2 ? this.swiperIndex : this.currentVisibleIndex;
      let target = index + delta;
      if (target < 0 || target >= this.totalImages) {
        return;
      }
      if (this.readingMode <= 2) {
        this.swiperIndex = target;
        this.currentVisibleIndex = target;
        setTimeout(() => {
          try {
            this.swiperController.changeIndex(target, false);
          } catch (err) {
            console.warn('[ReaderPage] changeIndex failed: ' + JSON.stringify(err));
          }
        }, 0);
      } else {
        this.listScroller.scrollToIndex(target, true, ScrollAlign.START);
        this.currentVisibleIndex = target;
      }
      this.persistPageIndex();
      this.showPageTip(target);
    } catch (err) {
      console.warn('[ReaderPage] volume turn failed: ' + JSON.stringify(err));
    }
  }

  /** 页码胶囊（动画开关打开时淡入淡出） */
  private showPageTip(page: number): void {
    this.pageTipText = (page + 1) + ' / ' + this.totalImages;
    if (this.pageTipTimer >= 0) {
      clearTimeout(this.pageTipTimer);
    }
    if (!this.pageTipVisible) {
      this.pageTipVisible = true;
    }
    this.pageTipTimer = setTimeout(() => {
      if (this.animationsOn) {
        animateTo({ duration: 260, curve: Curve.EaseIn }, () => {
          this.pageTipVisible = false;
        });
      } else {
        this.pageTipVisible = false;
      }
      this.pageTipTimer = -1;
    }, 900);
  }

  /** 切换阅读模式并保留当前阅读位置 */
  private switchReadingMode(mode: number): void {
    if (mode === this.readingMode) {
      this.showSheet = false;
      return;
    }
    // 记录切换前所在页
    let currentIndex = this.readingMode <= 2 ? this.swiperIndex : this.currentVisibleIndex;
    this.swiperIndex = currentIndex;
    if (mode > 2) {
      // 切到连续滚动：重建 List 后定位到同一张图
      this.readingMode = mode;
      this.showSheet = false;
      setTimeout(() => {
        this.listScroller.scrollToIndex(this.swiperIndex, true, ScrollAlign.START);
      }, 80);
    } else {
      // 切到单页：Swiper 渲染完成后跳到当前页（非受控，手势不受状态干扰）
      this.readingMode = mode;
      this.showSheet = false;
      let target = this.swiperIndex;
      setTimeout(() => {
        this.swiperController.changeIndex(target, false);
      }, 150);
    }
    console.info('[ReaderPage] readingMode = ' + mode + ', keepIndex = ' + this.swiperIndex);
  }

  /** 屏幕方向选项行 */
  @Builder
  OrientationRow(mode: string, label: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(this.orientation === mode ? COLOR_PRIMARY : COLOR_TEXT_TITLE)
        .layoutWeight(1)
      if (this.orientation === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([COLOR_PRIMARY])
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 20, right: 20 })
    .onClick(() => {
      this.orientation = mode;
      this.applyOrientation();
    })
  }

  /** 应用窗口方向锁定 */
  private applyOrientation(): void {
    let context = getContext(this);
    window.getLastWindow(context).then((win: window.Window) => {
      if (this.orientation === 'portrait') {
        win.setPreferredOrientation(window.Orientation.PORTRAIT);
      } else if (this.orientation === 'landscape') {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
      } else {
        win.setPreferredOrientation(window.Orientation.UNSPECIFIED);
      }
    }).catch((err: Error) => {
      console.warn('[ReaderPage] setPreferredOrientation failed: ' + JSON.stringify(err));
    });
  }

  /** 应用窗口亮度（-1 恢复跟随系统） */
  private applyBrightness(): void {
    let context = getContext(this);
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowBrightness(this.readerBrightness);
    }).catch((err: Error) => {
      console.warn('[ReaderPage] setWindowBrightness failed: ' + JSON.stringify(err));
    });
  }

  /** 进入章节后恢复到上次阅读的页 */
  private restoreLastPage(cache: CacheManager): void {
    let savedPage = cache.getPageProgress(this.comicId, this.currentOrder);
    if (savedPage > 0 && savedPage < this.totalImages) {
      this.currentVisibleIndex = savedPage;
      this.swiperIndex = savedPage;
      setTimeout(() => {
        if (this.readingMode <= 2) {
          this.swiperController.changeIndex(savedPage, false);
        } else {
          this.listScroller.scrollToIndex(savedPage, true, ScrollAlign.START);
        }
      }, 150);
    }
  }

  /** 当前页可拖拽的图片本地路径（本地文件或磁盘缓存），供中转站拖拽 */
  private dragImagePath(index: number): string {
    let img = this.imageDataSource.getData(index);
    if (!img || img.failed) {
      return '';
    }
    if (img.url.startsWith('file://')) {
      return img.url.substring(7);
    }
    return ImageLoader.diskFilePath(img.url);
  }

  /** 拖拽预览（优先用内存 PixelMap 按原图比例渲染；否则系统默认快照，均无白边） */
  private dragPreviewInfo(index: number): DragItemInfo {
    let img = this.imageDataSource.getData(index);
    if (img && !img.failed) {
      let pm = ImageLoader.getCached(img.url);
      if (pm !== null) {
        let info: DragItemInfo = { pixelMap: pm };
        return info;
      }
    }
    let info: DragItemInfo = {};
    return info;
  }

  /** 图片拖拽开始：挂 UDM 图片数据（可拖到中转站/其他应用） */
  private handleImageDragStart(event: DragEvent, index: number): void {
    let path = this.dragImagePath(index);
    if (path.length === 0) {
      return;
    }
    try {
      let uri = fileUri.getUriFromPath(path);
      let record = new unifiedDataChannel.Image();
      record.imageUri = uri;
      let data = new unifiedDataChannel.UnifiedData(record);
      event.setData(data);
    } catch (err) {
      console.warn('[ReaderPage] drag setData failed: ' + JSON.stringify(err));
    }
  }

  /** 收集当前章节全部图片字节（本地文件直读，远程下载） */
  private async collectChapterBytes(): Promise<ArrayBuffer[]> {
    let list = this.imageDataSource.getAll();
    let out: ArrayBuffer[] = [];
    for (let img of list) {
      if (img.url.startsWith('file://')) {
        let path = img.url.substring(7);
        try {
          let stat = fs.statSync(path);
          let buf = new ArrayBuffer(stat.size);
          let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
          fs.readSync(file.fd, buf);
          fs.closeSync(file.fd);
          out.push(buf);
        } catch (err) {
          throw new Error('读取本地图片失败');
        }
      } else {
        out.push(await ImageLoader.downloadBytes([img.url]));
      }
    }
    return out;
  }

  /** 文件名安全化（去掉系统不允许的字符） */
  private safeFileName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_');
  }

  /** 导出当前章节（PDF / ZIP）→ 系统文件保存对话框（自定义位置 + 作品名） */
  private async doExport(kind: string): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    this.showSheet = false;
    promptAction.showToast({ message: '正在导出，请稍候…', duration: 1600 });
    try {
      let bytes = await this.collectChapterBytes();
      let ctx = getContext(this) as common.UIAbilityContext;
      let dir = ctx.cacheDir + '/export';
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      let base = this.safeFileName(this.comicTitle) + '_第' + this.currentOrder + '话';
      let ext = kind === 'pdf' ? '.pdf' : '.zip';
      let tmpPath = dir + '/' + base + ext;
      if (kind === 'pdf') {
        await exportImagesPdf(bytes, tmpPath, this.comicTitle);
      } else {
        await exportImagesZip(bytes, tmpPath, base);
      }
      // 系统保存对话框：用户选择位置，默认文件名为作品名
      let options = new picker.DocumentSaveOptions();
      options.newFileNames = [base + ext];
      options.fileSuffixChoices = kind === 'pdf' ? ['文档|.pdf'] : ['压缩包|.zip'];
      let documentViewPicker = new picker.DocumentViewPicker(ctx);
      let uris = await documentViewPicker.save(options);
      if (uris.length > 0) {
        // 官方文档写法：直接用 picker 返回的 URI 打开写入（READ_WRITE）
        let src = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
        let stat = fs.statSync(tmpPath);
        let buf = new ArrayBuffer(stat.size);
        fs.readSync(src.fd, buf);
        fs.closeSync(src);
        let dest = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
        fs.writeSync(dest.fd, buf);
        fs.closeSync(dest);
        promptAction.showToast({ message: '已保存', duration: 1600 });
      }
    } catch (err) {
      promptAction.showToast({ message: '导出失败：' + (err as Error).message, duration: 2000 });
    } finally {
      this.exporting = false;
    }
  }

  /** 导出选择弹窗 */
  @Builder
  exportSheet() {
    Column({ space: 0 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6, bottom: 4 })
      Text('导出当前章节')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 10 })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(22)
          .fontColor([COLOR_PRIMARY])
        Text('导出为 PDF')
          .fontSize(15)
          .fontColor(COLOR_TEXT_TITLE)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .onClick(() => this.doExport('pdf'))
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.doc_zipper'))
          .fontSize(22)
          .fontColor([COLOR_PRIMARY])
        Text('导出为图片压缩包（ZIP）')
          .fontSize(15)
          .fontColor(COLOR_TEXT_TITLE)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .onClick(() => this.doExport('zip'))
    }
    .width('100%')
    .padding({ bottom: this.bottomSafeHeight + 12 })
    .backgroundColor(COLOR_CARD)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  /** 保存当前页级进度（单页模式用 swiperIndex，滚动模式用当前可见页） */
  private persistPageIndex(): void {
    let page = this.readingMode <= 2 ? this.swiperIndex : this.currentVisibleIndex;
    if (page < 0 || this.totalImages <= 0) {
      return;
    }
    CacheManager.getInstance().then(cache => {
      cache.savePageProgress(this.comicId, this.currentOrder, page);
    });
  }

  aboutToDisappear(): void {
    // 退出阅读器：注销音量键 + 保存页级进度 + 恢复系统亮度与方向
    this.unregisterVolumeKeys();
    this.persistPageIndex();
    let context = getContext(this);
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowBrightness(-1);
      win.setPreferredOrientation(window.Orientation.UNSPECIFIED);
    }).catch((err: Error) => {
      console.warn('[ReaderPage] restore window failed: ' + JSON.stringify(err));
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(COLOR_PRIMARY)
          Text('加载图片中...')
            .fontSize(14)
            .fontColor(COLOR_TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .padding({ top: 80 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(COLOR_READER_BG)
      } else if (this.errorText.length > 0) {
        Column() {
          Text(this.errorText)
            .fontSize(16)
            .fontColor(COLOR_PRIMARY)
            .margin({ bottom: 16 })
          Button('重试')
            .fontSize(14)
            .backgroundColor(COLOR_PRIMARY)
            .fontColor(COLOR_WHITE)
            .borderRadius(20)
            .height(40)
            .padding({ left: 28, right: 28 })
            .onClick(() => this.loadImagesWithCache())
        }
        .width('100%')
        .height('100%')
        .padding({ top: 80 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(COLOR_READER_BG)
      } else if (this.totalImages === 0) {
        Column() {
          Text('暂无图片')
            .fontSize(16)
            .fontColor(COLOR_TEXT_HINT)
        }
        .width('100%')
        .height('100%')
        .padding({ top: 80 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(COLOR_READER_BG)
      } else {
        if (this.readingMode <= 2) {
          // ── 单页翻页模式 ──
          Swiper(this.swiperController) {
            ForEach(this.imageDataSource.getAll(), (img: ReaderImage, index: number) => {
              NetImage({
                src: img.url,
                candidates: this.candidateUrls[index] || [],
                fit: ImageFit.Contain,
                radius: 0,
                fillParent: true
              })
                .width('100%')
                .height('100%')
                .draggable(true)
                .onDragStart((event: DragEvent) => {
                  this.handleImageDragStart(event, index);
                  return this.dragPreviewInfo(index);
                })
            }, (img: ReaderImage, index: number) => String(index) + '_' + img.url)
          }
          .vertical(this.readingMode === 2)
          .indicator(false)
          .loop(false)
          .width('100%')
          .height('100%')
          .backgroundColor(COLOR_READER_BG)
          .key('swiper_' + this.comicId + '_' + this.currentOrder)
          .onChange((index: number) => {
            this.swiperIndex = index;
            this.currentVisibleIndex = index;
            this.persistPageIndex();
          })
          .onClick(() => this.toggleControls())
        } else {
          // ── 连续滚动模式（无缝 / 有隙） ──
          Scroll(this.scrollScroller) {
            List({ scroller: this.listScroller, space: this.readingMode === 3 ? 8 : 0 }) {
              LazyForEach(this.imageDataSource, (img: ReaderImage, index: number) => {
                ListItem() {
                  if (img.failed) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                        .fontSize(32)
                        .fontColor([COLOR_READER_TEXT_MUTED])
                      Text('加载失败')
                        .fontSize(12)
                        .fontColor(COLOR_TEXT_HINT)
                        .margin({ top: 6 })
                    }
                    .width('100%')
                    .height(200)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(COLOR_PLACEHOLDER)
                  } else {
                    NetImage({
                      src: img.url,
                      candidates: this.candidateUrls[index] || [],
                      fit: ImageFit.Contain,
                      radius: 0
                    })
                      .width('100%')
                      .backgroundColor(COLOR_CARD)
                      .draggable(true)
                      .onDragStart((event: DragEvent) => {
                        this.handleImageDragStart(event, index);
                        return this.dragPreviewInfo(index);
                      })
                  }
                }
                .width('100%')
              }, (img: ReaderImage, index: number) => String(index) + '_' + img.url + '_' + img.failed)
            }
            .listDirection(Axis.Vertical)
            .scrollBar(BarState.Off)
            .cachedCount(10)
            .width('100%')
            .height('100%')
            .onScrollIndex((start: number, end: number, center: number) => {
              this.currentVisibleIndex = start;
              this.persistPageIndex();
            })
            .nestedScroll({
              scrollForward: NestedScrollMode.PARENT_FIRST,
              scrollBackward: NestedScrollMode.PARENT_FIRST
            })
          }
          .width('100%')
          .height('100%')
          .scrollable(ScrollDirection.FREE)
          .maxZoomScale(3.0)
          .minZoomScale(1.0)
          .zoomScale(this.zoomScale)
          .enableBouncesZoom(true)
          .edgeEffect(EdgeEffect.None)
          .scrollBar(BarState.Off)
          .onDidZoom((scale: number) => {
            this.zoomScale = scale;
            let zoomed = scale > 1.0;
            if (this.isZoomed !== zoomed) {
              this.isZoomed = zoomed;
            }
          })
          .onClick(() => this.toggleControls())
        }
      }

      // ── 悬浮顶部工具栏 ──
      if (this.showControls) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([COLOR_WHITE])
            .onClick(() => this.onBack())

          Text(this.comicTitle + ' - 第' + this.currentOrder + '话')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_WHITE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 8, right: 8 })

          SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
            .fontSize(24)
            .fontColor([COLOR_WHITE])
            .margin({ right: 14 })
            .onClick(() => {
              this.sheetKind = 'export';
              this.showSheet = true;
            })
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(24)
            .fontColor([COLOR_WHITE])
            .onClick(() => {
              this.sheetKind = 'settings';
              this.showSheet = true;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.topSafeHeight + 8, bottom: 8 })
        .backgroundColor(COLOR_READER_TOOLBAR_BG)
        .backdropBlur(20)
        .transition(this.animationsOn
          ? TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          : TransitionEffect.IDENTITY)

        // ── 悬浮底部工具栏（position+offset 悬浮，无 markAnchor） ──
        Row() {
          Button(this.hasPrevChapter ? '上一话' : '已是第一话')
            .fontSize(14)
            .fontColor(this.hasPrevChapter ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
            .backgroundColor(this.hasPrevChapter ? COLOR_READER_TOOLBAR_ACTIVE : COLOR_READER_TOOLBAR_DISABLED)
            .borderRadius(18)
            .width(100)
            .height(36)
            .enabled(this.hasPrevChapter)
            .onClick(() => this.goPrevChapter())

          Text((this.currentVisibleIndex + 1) + ' / ' + this.totalImages)
            .fontSize(13)
            .fontColor(COLOR_READER_TEXT_MUTED)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button(this.hasNextChapter ? '下一话' : '已是最后一话')
            .fontSize(14)
            .fontColor(this.hasNextChapter ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
            .backgroundColor(this.hasNextChapter ? COLOR_READER_TOOLBAR_ACTIVE : COLOR_READER_TOOLBAR_DISABLED)
            .borderRadius(18)
            .width(100)
            .height(36)
            .enabled(this.hasNextChapter)
            .onClick(() => this.goNextChapter())
        }
        .position({ x: 0, y: '100%' })
        .markAnchor({ x: 0, y: '100%' })
        .offset({ x: 0, y: -(this.bottomSafeHeight + 16) })
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(COLOR_READER_TOOLBAR_BG)
        .backdropBlur(20)
        .justifyContent(FlexAlign.SpaceBetween)
        .transition(this.animationsOn
          ? TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          : TransitionEffect.IDENTITY)
      }

      // ── 页码胶囊提示（音量键/手势翻页时浮现） ──
      if (this.pageTipVisible) {
        Text(this.pageTipText)
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#66000000')
          .borderRadius(18)
          .position({ x: '50%', y: '50%' })
          .markAnchor({ x: '50%', y: '50%' })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_READER_BG)
    .bindSheet($$this.showSheet, this.unifiedSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showSheet = false;
      }
    })
  }

  /** 底部弹窗统一分发（单 bindSheet 避免多实例互相顶掉） */
  @Builder
  unifiedSheet() {
    if (this.sheetKind === 'settings') {
      this.readerSettingsSheet()
    } else if (this.sheetKind === 'export') {
      this.exportSheet()
    }
  }

  /** 阅读设置弹窗（系统 bindSheet 样式） */
  @Builder
  readerSettingsSheet() {
    Column({ space: 0 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6, bottom: 4 })
      Scroll() {
        Column({ space: 0 }) {
          Text('阅读模式')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 10 })
          this.ModeRow(0, '单页式（从左到右）')
          this.ModeRow(1, '单页式（从右到左）')
          this.ModeRow(2, '单页式（从上到下）')
          this.ModeRow(3, '条漫（页间有空隙）')
          this.ModeRow(4, '条漫')

          Text('屏幕方向')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 10 })
          this.OrientationRow('system', '跟随系统')
          this.OrientationRow('portrait', '锁定竖屏')
          this.OrientationRow('landscape', '锁定横屏')

          Text('音量键翻页')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 10 })
          Row() {
            Text('音量上=下一页，音量下=上一页')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.volumeTurnEnabled })
              .selectedColor(COLOR_PRIMARY)
              .onChange((checked: boolean) => {
                this.toggleVolumeTurn(checked);
              })
          }
          .width('100%')
          .height(48)
          .padding({ left: 20, right: 20 })

          Text('亮度')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 6 })
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.sun_min'))
              .fontSize(18)
              .fontColor([COLOR_TEXT_SECONDARY])
            Slider({
              value: this.readerBrightness < 0 ? 0.5 : this.readerBrightness,
              min: 0.1,
              max: 1.0,
              step: 0.01,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .trackColor(COLOR_PRIMARY_TINT)
              .selectedColor(COLOR_PRIMARY)
              .showTips(false)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.readerBrightness = value;
                if (mode === SliderChangeMode.End) {
                  this.applyBrightness();
                }
              })
            SymbolGlyph($r('sys.symbol.sun_max'))
              .fontSize(20)
              .fontColor([COLOR_TEXT_SECONDARY])
          }
          .width('100%')
          .height(40)
          .padding({ left: 20, right: 20 })
        }
        .width('100%')
        .padding({ bottom: this.bottomSafeHeight + 12 })
      }
      .width('100%')
      .constraintSize({ maxHeight: this.readerSheetMaxHeight() })
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  /** 弹窗最大高度（屏幕 82%） */
  private readerSheetMaxHeight(): number {
    return px2vp(display.getDefaultDisplaySync().height) * 0.82;
  }
}