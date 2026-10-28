import { router, window, CommonModifier, uiMaterial } from '@kit.ArkUI';
import { unifiedDataChannel } from '@kit.ArkData';
import { inputConsumer, KeyCode } from '@kit.InputKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { showImmersiveToast } from '../common/ImmersiveToast';
import { supportsComponentImmersiveMaterial } from '../common/CompatibleMaterial';
import { ApiService } from '../network/ApiService';
import { ImageUrlManager } from '../network/ImageUrlManager';
import { NetImage } from '../components/NetImage';
import { ChapterDownloadSheet } from '../components/ChapterDownloadSheet';
import { ImageLoader } from '../common/ImageLoader';
import { exportImagesZip, exportImagesPdf } from '../common/ExportUtils';
import { BikaPageDoc, ComicDetailViewModel, EpViewModel } from '../models/Comic';
import { CacheManager } from '../common/CacheManager';
import {
  CONTINUATION_READING_KEY,
  CurrentReadingState,
  publishContinuationRoute,
  clearContinuationRoute,
  readContinuationRoute,
  ContinuationRouteState,
  ROUTE_READER
} from '../common/ContinuationState';
import { DownloadManager } from '../common/DownloadManager';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_READER_TEXT_MUTED,
  COLOR_READER_BG,
  COLOR_BG,
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

/** 标题栏及底部栏的外层只承载布局，显式关闭整行材质。 */
class ReaderBarBackground extends CommonModifier {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundColor(Color.Transparent);
    instance.backgroundBlurStyle(BlurStyle.NONE);
    if (supportsComponentImmersiveMaterial()) {
      instance.systemMaterial(uiMaterial.Material.empty);
    }
  }
}

/** 阅读器胶囊：仅用于标题栏和底部 TabBar 内的独立表面。 */
class ReaderCapsuleMaterial extends CommonModifier {
  private readonly level: string;

  constructor(level: string) {
    super();
    this.level = level;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    // 阅读器保持深色表面与白色图标；弱档增加底色，保证白底漫画上的可读性。
    const tint = this.level === 'EXQUISITE' ? '#991C1C1E'
      : this.level === 'SMOOTH' ? '#CC1C1C1E' : '#B31C1C1E';
    if (supportsComponentImmersiveMaterial()) {
      try {
        if (uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE) {
          // 通用材质只在标题栏、底部 TabBar 等官方作用域内生效。
          instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THIN,
            materialColor: tint,
            applyShadow: true,
            interactive: false,
            lightEffect: { color: '#FF7CA8' }
          }));
          return;
        }
      } catch (err) {
        console.warn('[ReaderPage] capsule material unavailable: ' + JSON.stringify(err));
      }
    }
    instance.backgroundColor(tint);
    instance.backdropBlur(20);
  }
}

@Entry
@Component
struct ReaderPage {
  @StorageProp('bika_material_level') readerMaterialLevel: string = 'EXQUISITE';
  private readonly readerBarBackground: ReaderBarBackground = new ReaderBarBackground();
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
  /** 底栏整栏进度模式：拖动只预览，松手跳页，空闲 3 秒恢复按钮。 */
  @State progressMode: boolean = false;
  @State progressPage: number = 1;
  @State progressDragging: boolean = false;
  private progressTouching: boolean = false;
  private progressCancelled: boolean = false;
  private progressAppliedPage: number = -1;
  private progressRestoreTimer: number = -1;
  private progressNavigationId: number = 0;
  /** 底部弹窗（单例，按类型分发：settings/saveImage/export/saveFile） */
  @State showSheet: boolean = false;
  @State sheetKind: string = '';
  @State readerDownloadChapters: EpViewModel[] = [];
  @State downloadSelected: number[] = [];
  @State readerDownloadBusy: boolean = false;
  private readerDownloadComic: ComicDetailViewModel | null = null;
  private readerDownloadActionId: number = 0;
  private downloadMenuVisible: boolean = false;
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
  /** 顶部与底部胶囊使用当前窗口安全区，不修改全局布局数据。 */
  @State readerTopInset: number = 0;
  @State readerBottomInset: number = 0;
  @State readerWindowHeight: number = 0;
  @State readerLeftInset: number = 0;
  @State readerRightInset: number = 0;
  @State readerSettingsMeasuredHeight: number = 0;
  @State readerSettingsBodyHeight: number = 0;
  private readerWindow: window.Window | undefined = undefined;
  private readerWindowActive: boolean = false;
  private readerAvoidAreaListener = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_SYSTEM || options.type === window.AvoidAreaType.TYPE_CUTOUT ||
      options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.updateReaderInsets();
    }
  };

  private readerWindowSizeListener = (size: window.Size): void => {
    if (!this.readerWindowActive) {
      return;
    }
    this.updateReaderWindowHeight(size.height);
    this.updateReaderInsets();
  };

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
  /** 忽略已被下一次模式选择或页面退出取代的设置操作。 */
  private readingModeChangeId: number = 0;
  private scrollScroller: Scroller = new Scroller();
  private listScroller: Scroller = new Scroller();
  private imageDataSource: ImageDataSource = new ImageDataSource();

  async aboutToAppear(): Promise<void> {
    this.observeReaderInsets();
    let cache = await CacheManager.getInstance();
    const savedMode = cache.getSetting('reader_mode', '4');
    this.readingMode = /^[0-4]$/.test(savedMode) ? Number(savedMode) : 4;
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

  private updateReaderWindowHeight(height: number, inPixels: boolean = true): void {
    if (!Number.isFinite(height) || height <= 0) {
      return;
    }
    const next = inPixels ? this.getUIContext().px2vp(height) : height;
    if (Math.abs(this.readerWindowHeight - next) > 0.5) {
      this.readerWindowHeight = next;
    }
  }

  private updateReaderWindowMetrics(): void {
    const win = this.readerWindow;
    if (win !== undefined) {
      this.updateReaderWindowHeight(win.getWindowProperties().windowRect.height);
      this.updateReaderInsets();
    }
  }

  private updateReaderInsets(): void {
    const win = this.readerWindow;
    if (win === undefined) {
      return;
    }
    const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const cutoutArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    const navigationArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.readerTopInset = this.getUIContext().px2vp(Math.max(systemArea.topRect.height, cutoutArea.topRect.height));
    this.readerBottomInset = this.getUIContext().px2vp(Math.max(
      systemArea.bottomRect.height, cutoutArea.bottomRect.height, navigationArea.bottomRect.height));
    this.readerLeftInset = this.getUIContext().px2vp(Math.max(
      systemArea.leftRect.width, cutoutArea.leftRect.width, navigationArea.leftRect.width));
    this.readerRightInset = this.getUIContext().px2vp(Math.max(
      systemArea.rightRect.width, cutoutArea.rightRect.width, navigationArea.rightRect.width));
  }

  private observeReaderInsets(): void {
    this.readerTopInset = this.topSafeHeight;
    this.readerBottomInset = this.bottomSafeHeight;
    this.readerWindowActive = true;
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      if (!this.readerWindowActive) {
        return;
      }
      this.readerWindow = win;
      this.updateReaderWindowMetrics();
      win.on('windowSizeChange', this.readerWindowSizeListener);
      win.on('avoidAreaChange', this.readerAvoidAreaListener);
    }).catch((err: Error) => {
      console.warn('[ReaderPage] window metrics unavailable: ' + JSON.stringify(err));
    });
  }

  private stopObservingReaderInsets(): void {
    this.readerWindowActive = false;
    const win = this.readerWindow;
    this.readerWindow = undefined;
    if (win !== undefined) {
      try {
        win.off('windowSizeChange', this.readerWindowSizeListener);
      } catch (err) {
        console.warn('[ReaderPage] remove window size listener failed: ' + JSON.stringify(err));
      }
      try {
        win.off('avoidAreaChange', this.readerAvoidAreaListener);
      } catch (err) {
        console.warn('[ReaderPage] remove top safe area listener failed: ' + JSON.stringify(err));
      }
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
    this.resetProgressControl();
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
      this.publishCurrentReading();
    });
  }

  private async loadImagesWithCache(): Promise<void> {
    this.resetProgressControl();
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
      this.publishCurrentReading();
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
    // 关闭时保留正在淡出的内容形态，重新打开前再恢复按钮，避免滑块闪回按钮。
    this.resetProgressControl(this.showControls);
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
    this.publishCurrentReading();
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
    this.publishCurrentReading();
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
    if (this.showSheet || this.downloadMenuVisible || this.progressDragging || this.progressTouching) {
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

  private currentReaderPage(): number {
    if (this.totalImages <= 0) {
      return 0;
    }
    const index = this.readingMode <= 2 ? this.swiperIndex : this.currentVisibleIndex;
    return Math.min(this.totalImages, Math.max(1, index + 1));
  }

  private clampProgressPage(value: number): number {
    return Math.min(Math.max(1, this.totalImages), Math.max(1, Math.round(value)));
  }

  private clearProgressRestore(): void {
    if (this.progressRestoreTimer >= 0) {
      clearTimeout(this.progressRestoreTimer);
      this.progressRestoreTimer = -1;
    }
  }

  private hidePageTip(): void {
    if (this.pageTipTimer >= 0) {
      clearTimeout(this.pageTipTimer);
      this.pageTipTimer = -1;
    }
    this.pageTipVisible = false;
  }

  /** 仅切换胶囊内容；背板节点保持稳定，避免材质闪烁。 */
  private setProgressMode(enabled: boolean): void {
    if (this.progressMode === enabled) {
      return;
    }
    if (this.animationsOn && this.showControls) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.progressMode = enabled;
      });
    } else {
      this.progressMode = enabled;
    }
  }

  private resetProgressControl(keepLayout: boolean = false): void {
    this.clearProgressRestore();
    const wasProgressMode = this.progressMode;
    if (!keepLayout) {
      this.setProgressMode(false);
    }
    this.progressDragging = false;
    this.progressTouching = false;
    this.progressCancelled = false;
    this.progressAppliedPage = -1;
    if (wasProgressMode) {
      this.hidePageTip();
    }
  }

  private scheduleProgressRestore(): void {
    this.clearProgressRestore();
    if (!this.progressMode) {
      return;
    }
    this.progressRestoreTimer = setTimeout(() => {
      this.progressRestoreTimer = -1;
      if (!this.progressDragging && !this.progressTouching) {
        this.resetProgressControl();
      }
    }, 3000);
  }

  private openProgressControl(): void {
    if (this.progressMode || !this.showControls || this.isLoading || this.totalImages <= 1) {
      return;
    }
    this.progressPage = this.currentReaderPage();
    this.progressDragging = false;
    this.progressTouching = false;
    this.progressCancelled = false;
    this.progressAppliedPage = -1;
    this.setProgressMode(true);
    this.scheduleProgressRestore();
  }

  /** 保持图片原始索引，RTL 只反转滑块方向，不反转页码。 */
  private jumpToReaderPage(page: number): boolean {
    if (this.totalImages <= 0 || this.isLoading) {
      return false;
    }
    const target = this.clampProgressPage(page) - 1;
    try {
      if (this.readingMode <= 2) {
        this.swiperController.changeIndex(target, false);
      } else {
        this.listScroller.scrollToIndex(target, false, ScrollAlign.START);
      }
      this.progressNavigationId++;
      this.swiperIndex = target;
      this.currentVisibleIndex = target;
      this.persistPageIndex();
      this.publishCurrentReading();
      return true;
    } catch (err) {
      console.warn('[ReaderPage] progress jump failed: ' + JSON.stringify(err));
      showImmersiveToast({ message: '跳页失败，请重试', duration: 1600 });
      return false;
    }
  }

  private finishProgressSeek(commit: boolean): void {
    if (!this.progressMode) {
      return;
    }
    this.progressDragging = false;
    if (commit && !this.progressCancelled) {
      const target = this.clampProgressPage(this.progressPage);
      if (this.progressAppliedPage !== target && this.jumpToReaderPage(target)) {
        this.progressAppliedPage = target;
      }
      this.progressPage = this.currentReaderPage();
      this.showPageTip(this.progressPage - 1);
    } else {
      this.progressPage = this.currentReaderPage();
      this.hidePageTip();
    }
    this.scheduleProgressRestore();
  }

  private onProgressChange(value: number, mode: SliderChangeMode): void {
    if (!this.showControls || !this.progressMode || this.totalImages <= 1 || this.isLoading) {
      return;
    }
    if (this.progressCancelled && mode !== SliderChangeMode.Begin) {
      return;
    }
    this.progressPage = this.clampProgressPage(value);
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      if (mode === SliderChangeMode.Begin) {
        this.progressCancelled = false;
        this.progressAppliedPage = -1;
      }
      this.clearProgressRestore();
      this.progressDragging = true;
      this.showPageTip(this.progressPage - 1, true);
    } else if (mode === SliderChangeMode.End) {
      this.finishProgressSeek(true);
    } else if (mode === SliderChangeMode.Click) {
      if (this.progressTouching) {
        this.progressDragging = true;
        this.showPageTip(this.progressPage - 1, true);
      } else {
        this.progressAppliedPage = -1;
        this.finishProgressSeek(true);
      }
    }
  }

  private onProgressTouch(event: TouchEvent): void {
    if (!this.showControls || !this.progressMode) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.clearProgressRestore();
      this.progressTouching = true;
      this.progressCancelled = false;
      this.progressAppliedPage = -1;
      this.progressPage = this.currentReaderPage();
      this.progressDragging = true;
      this.showPageTip(this.progressPage - 1, true);
    } else if (event.type === TouchType.Up) {
      this.progressTouching = false;
      if (this.progressDragging) {
        this.finishProgressSeek(true);
      } else {
        this.scheduleProgressRestore();
      }
    } else if (event.type === TouchType.Cancel) {
      this.progressTouching = false;
      this.progressCancelled = true;
      this.finishProgressSeek(false);
    }
  }

  /** 同一枚页码 Toast 持续更新；拖动停住时也保持显示，不循环创建系统 Toast。 */
  private showPageTip(page: number, hold: boolean = false): void {
    if (this.totalImages <= 0) {
      return;
    }
    this.pageTipText = this.clampProgressPage(page + 1) + ' / ' + this.totalImages;
    if (this.pageTipTimer >= 0) {
      clearTimeout(this.pageTipTimer);
      this.pageTipTimer = -1;
    }
    this.pageTipVisible = true;
    if (hold) {
      return;
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
  private async switchReadingMode(mode: number): Promise<void> {
    if (!Number.isInteger(mode) || mode < 0 || mode > 4) {
      return;
    }
    const changeId = ++this.readingModeChangeId;
    try {
      const cache = await CacheManager.getInstance();
      if (changeId !== this.readingModeChangeId) {
        return;
      }
      if (!cache.isReady()) {
        throw new Error('设置存储尚未就绪');
      }
      cache.saveSetting('reader_mode', String(mode));
    } catch (err) {
      if (changeId === this.readingModeChangeId) {
        showImmersiveToast({ message: '阅读模式保存失败，请重试', duration: 2000 });
      }
      return;
    }
    if (mode === this.readingMode) {
      this.showSheet = false;
      return;
    }
    // 保持图片的原始索引；RTL 只改变翻页方向，不反转图片数组或页码。
    this.resetProgressControl();
    const navigationId = this.progressNavigationId;
    const currentIndex = this.readingMode <= 2 ? this.swiperIndex : this.currentVisibleIndex;
    this.swiperIndex = currentIndex;
    this.currentVisibleIndex = currentIndex;
    this.readingMode = mode;
    this.showSheet = false;
    setTimeout(() => {
      if (changeId !== this.readingModeChangeId || navigationId !== this.progressNavigationId) {
        return;
      }
      if (mode > 2) {
        this.listScroller.scrollToIndex(currentIndex, true, ScrollAlign.START);
      } else {
        this.swiperController.changeIndex(currentIndex, false);
      }
    }, mode > 2 ? 80 : 150);
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
      const navigationId = this.progressNavigationId;
      const order = this.currentOrder;
      setTimeout(() => {
        if (!this.readerWindowActive || order !== this.currentOrder || navigationId !== this.progressNavigationId) {
          return;
        }
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

  private readerDownloadMenu(): MenuElement[] {
    return [
      {
        value: '下载本话',
        enabled: !this.readerDownloadBusy,
        action: (): void => { this.onReaderDownloadAction('current'); }
      },
      {
        value: '下载全部章节',
        enabled: !this.readerDownloadBusy,
        action: (): void => { this.onReaderDownloadAction('all'); }
      },
      {
        value: '下载范围章节',
        enabled: !this.readerDownloadBusy,
        action: (): void => { this.onReaderDownloadAction('range'); }
      },
      {
        value: '导出为文件',
        enabled: !this.readerDownloadBusy && !this.exporting,
        action: (): void => {
          this.resetProgressControl();
          this.sheetKind = 'export';
          this.showSheet = true;
        }
      }
    ];
  }

  private async loadReaderDownloadComic(): Promise<void> {
    if (this.readerDownloadComic !== null) {
      return;
    }
    // 已下载作品优先沿用本地元信息，避免离线阅读时额外请求详情。
    const local = DownloadManager.getInstance().getTasks().find(task => task.comicId === this.comicId);
    if (local !== undefined) {
      const comic = new ComicDetailViewModel();
      comic.id = this.comicId;
      comic.title = local.comicTitle || this.comicTitle;
      comic.coverUrl = local.coverUrl || this.coverUrl;
      comic.description = local.description;
      comic.author = local.author;
      this.readerDownloadComic = comic;
      return;
    }
    const detail = await this.apiService.getComicDetail(this.comicId);
    if (this.readerWindowActive) {
      this.readerDownloadComic = ComicDetailViewModel.fromDetail(detail);
    }
  }

  private async loadReaderDownloadChapters(): Promise<void> {
    if (this.readerDownloadChapters.length > 0) {
      return;
    }
    const docs = await this.apiService.getAllEps(this.comicId);
    const chapters: EpViewModel[] = [];
    const orders = new Set<number>();
    for (const doc of docs) {
      const ep = EpViewModel.fromDoc(doc);
      if (Number.isInteger(ep.order) && ep.order > 0 && !orders.has(ep.order)) {
        orders.add(ep.order);
        chapters.push(ep);
      }
    }
    chapters.sort((a: EpViewModel, b: EpViewModel) => a.order - b.order);
    if (this.readerWindowActive) {
      this.readerDownloadChapters = chapters;
    }
  }

  /** 三项菜单统一入队；当前话在点击时捕获，避免等待接口期间切章后下载错话。 */
  private async onReaderDownloadAction(kind: string): Promise<void> {
    if (this.readerDownloadBusy || this.comicId.length === 0 || !this.readerWindowActive) {
      return;
    }
    const order = this.currentOrder;
    const manager = DownloadManager.getInstance();
    if (kind === 'current') {
      const existing = manager.hasTask(this.comicId, order);
      if (existing !== undefined) {
        if (existing.status === 'failed' || existing.status === 'paused') {
          manager.retryTask(this.comicId, order);
          showImmersiveToast({ message: '已恢复本话下载', duration: 1600 });
        } else {
          showImmersiveToast({
            message: existing.status === 'completed' ? '本话已下载' : '本话已在下载队列', duration: 1600
          });
        }
        return;
      }
    }
    const actionId = ++this.readerDownloadActionId;
    this.readerDownloadBusy = true;
    this.resetProgressControl();
    showImmersiveToast({ message: kind === 'range' ? '正在获取章节…' : '正在准备下载…', duration: 1600 });
    try {
      await Promise.all([
        this.loadReaderDownloadComic(),
        kind === 'current' ? Promise.resolve() : this.loadReaderDownloadChapters()
      ]);
      if (!this.readerWindowActive || actionId !== this.readerDownloadActionId) {
        return;
      }
      if (this.readerDownloadComic === null) {
        throw new Error('漫画信息不可用');
      }
      if (kind === 'current') {
        const ep = this.readerDownloadChapters.find(chapter => chapter.order === order) || new EpViewModel();
        ep.order = order;
        if (ep.title.length === 0) {
          ep.title = '第' + order + '话';
        }
        this.queueReaderChapters([ep]);
      } else if (this.readerDownloadChapters.length === 0) {
        showImmersiveToast({ message: '暂无可下载的章节', duration: 1600 });
      } else if (kind === 'all') {
        this.queueReaderChapters(this.readerDownloadChapters);
      } else if (kind === 'range') {
        this.downloadSelected = [];
        this.sheetKind = 'download';
        this.showSheet = true;
      }
    } catch (err) {
      if (this.readerWindowActive && actionId === this.readerDownloadActionId) {
        console.warn('[ReaderPage] prepare download failed: ' + JSON.stringify(err));
        showImmersiveToast({ message: '获取下载信息失败，请重试', duration: 2000 });
      }
    } finally {
      if (actionId === this.readerDownloadActionId) {
        this.readerDownloadBusy = false;
      }
    }
  }

  private readerChapterDownloaded(order: number): boolean {
    return DownloadManager.getInstance().hasTask(this.comicId, order)?.status === 'completed';
  }

  private queueReaderChapters(chapters: EpViewModel[]): void {
    const comic = this.readerDownloadComic;
    if (comic === null) {
      return;
    }
    const manager = DownloadManager.getInstance();
    const orders = new Set<number>();
    let added = 0;
    let resumed = 0;
    let completed = 0;
    for (const ep of chapters) {
      if (orders.has(ep.order)) {
        continue;
      }
      orders.add(ep.order);
      const existing = manager.hasTask(this.comicId, ep.order);
      if (existing === undefined) {
        manager.addTask(this.comicId, comic.title, comic.coverUrl, comic.description, comic.author, ep.order, ep.title);
        added++;
      } else if (existing.status === 'failed' || existing.status === 'paused') {
        manager.retryTask(this.comicId, ep.order);
        resumed++;
      } else if (existing.status === 'completed') {
        completed++;
      }
    }
    const count = added + resumed;
    showImmersiveToast({
      message: count > 0
        ? (resumed > 0 ? '已添加或恢复 ' + count + ' 话下载' : '已加入 ' + count + ' 话到下载队列')
        : (orders.size > 0 && completed === orders.size ? '所选章节已下载' : '所选章节已在下载队列'),
      duration: 2000
    });
  }

  private startReaderDownloadSelected(): void {
    if (!this.showSheet || this.sheetKind !== 'download' || this.downloadSelected.length === 0) {
      return;
    }
    const chapters = this.readerDownloadChapters.filter(ep => this.downloadSelected.includes(ep.order));
    if (chapters.length === 0) {
      return;
    }
    this.showSheet = false;
    this.queueReaderChapters(chapters);
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
    showImmersiveToast({ message: '正在导出，请稍候…', duration: 1600 });
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
        showImmersiveToast({ message: '已保存', duration: 1600 });
      }
    } catch (err) {
      showImmersiveToast({ message: '导出失败：' + (err as Error).message, duration: 2000 });
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

  /**
   * 发布「当前正在阅读」到 AppStorage（应用接续源端只认这个状态）。
   * 阅读器进入 / 切换话 / 翻页都会调用，保证接续到的是「此刻」的话与页，而不是历史快照。
   * 只写内存态，不落盘；离开阅读器时由 clearCurrentReading 清除。
   */
  private publishCurrentReading(): void {
    try {
      if (this.comicId.length === 0) {
        return;
      }
      let page: number = this.readingMode <= 2 ? this.swiperIndex : this.currentVisibleIndex;
      if (page < 0) {
        page = 0;
      }
      let state: CurrentReadingState = {
        comicId: this.comicId,
        comicTitle: this.comicTitle,
        order: this.currentOrder,
        page: page,
        coverUrl: this.coverUrl,
        timestamp: Date.now()
      };
      AppStorage.setOrCreate(CONTINUATION_READING_KEY, JSON.stringify(state));
      // 通用页面描述符：接续到任意设备都落回阅读器的「当前话 + 当前页」
      publishContinuationRoute(ROUTE_READER, {
        comicId: this.comicId,
        comicTitle: this.comicTitle,
        coverUrl: this.coverUrl,
        order: this.currentOrder,
        page: page
      });
    } catch (err) {
      console.warn('[ReaderPage] publishCurrentReading failed: ' + JSON.stringify(err));
    }
  }

  /**
   * 清除「当前正在阅读」：离开阅读器后不再参与接续。
   * 只在本页状态仍是最新时清除（页栈里可能还压着另一个阅读器实例）。
   *
   * 注意：用 aboutToDisappear 而不是 onPageHide——应用退到后台（正是用户去触发接续的时刻）
   * 也会触发页面隐藏，若在那里清除会导致接续永远拿不到位置。
   */
  private clearCurrentReading(): void {
    try {
      let raw: string = AppStorage.get<string>(CONTINUATION_READING_KEY) ?? '';
      if (raw.length === 0) {
        return;
      }
      let state = JSON.parse(raw) as CurrentReadingState;
      if (state !== null && state !== undefined && state.comicId === this.comicId) {
        AppStorage.setOrCreate(CONTINUATION_READING_KEY, '');
      }
    } catch (err) {
      AppStorage.setOrCreate(CONTINUATION_READING_KEY, '');
    }
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
    this.readerDownloadActionId++;
    this.downloadMenuVisible = false;
    this.resetProgressControl();
    this.hidePageTip();
    this.progressNavigationId++;
    this.stopObservingReaderInsets();
    this.readingModeChangeId++;
    // 退出阅读器：清除「当前正在阅读」状态（接续不再带走旧位置）
    this.clearCurrentReading();
    // 描述符也清掉（仅当它仍指向本阅读器）；下层页面（详情页/首页）的 onPageShow 会重新发布
    try {
      let st: ContinuationRouteState | null = readContinuationRoute();
      if (st !== null && st.route === ROUTE_READER) {
        clearContinuationRoute();
      }
    } catch (err) {
      clearContinuationRoute();
    }
    // 注销音量键 + 保存页级进度 + 恢复系统亮度与方向
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

  @Builder
  readerContent() {
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
        .padding({
          top: this.showControls ? this.readerTopInset + 60 : this.readerTopInset,
          bottom: this.showControls ? this.readerBottomInset + 60 : this.readerBottomInset
        })
        .justifyContent(FlexAlign.Center)
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
        .padding({
          top: this.showControls ? this.readerTopInset + 60 : this.readerTopInset,
          bottom: this.showControls ? this.readerBottomInset + 60 : this.readerBottomInset
        })
        .justifyContent(FlexAlign.Center)
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
        .padding({
          top: this.showControls ? this.readerTopInset + 60 : this.readerTopInset,
          bottom: this.showControls ? this.readerBottomInset + 60 : this.readerBottomInset
        })
        .justifyContent(FlexAlign.Center)
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
          .direction(this.readingMode === 1 ? Direction.Rtl : Direction.Ltr)
          .vertical(this.readingMode === 2)
          .indicator(false)
          .loop(false)
          .width('100%')
          .height('100%')
          .backgroundColor(COLOR_READER_BG)
          // 平板限宽：图片两侧留黑，居中阅读
          .constraintSize({ maxWidth: 780 })
          .key('swiper_' + this.comicId + '_' + this.currentOrder)
          .onChange((index: number) => {
            this.swiperIndex = index;
            this.currentVisibleIndex = index;
            this.persistPageIndex();
            this.publishCurrentReading();
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
            .constraintSize({ maxWidth: 780 })
            .onScrollIndex((start: number, end: number, center: number) => {
              this.currentVisibleIndex = start;
              this.persistPageIndex();
              this.publishCurrentReading();
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
          .hitTestBehavior(HitTestMode.None)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_READER_BG)
    .bindSheet($$this.showSheet, this.unifiedSheet(), {
      // 范围下载与详情页采用同一个表面及内容组件，不叠加第二层圆角背景。
      backgroundColor: this.sheetKind === 'download' ? COLOR_BG : undefined,
      blurStyle: this.sheetKind === 'download' ? BlurStyle.NONE : undefined,
      borderWidth: this.sheetKind === 'download' ? 0 : undefined,
      detents: [this.sheetKind === 'settings' ? this.readerSettingsSheetHeight() : SheetSize.FIT_CONTENT],
      detentSelection: this.sheetKind === 'settings' ? this.readerSettingsSheetHeight() : undefined,
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onHeightDidChange: (height: number): void => {
        this.updateReaderSettingsHeight(height);
      },
      onWillDismiss: (): void => {
        this.showSheet = false;
        this.readerSettingsMeasuredHeight = 0;
      }
    })
  }

  /** 底部 TabBar 是普通组件沉浸材质的官方生效范围。 */
  @Builder
  readerWithBottomBar() {
    Tabs({ barPosition: BarPosition.End }) {
      TabContent() {
        this.readerContent()
      }
      .tabBar(this.readerBottomBar())
    }
    .width('100%')
    .height('100%')
    .vertical(false)
    .barMode(BarMode.Fixed)
    .barHeight(60 + Math.max(0, this.readerBottomInset - 7))
    .barOverlap(true)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundEffect({ radius: 0, saturation: 1, brightness: 1, color: Color.Transparent })
    .divider(null)
    .fadingEdge(false)
    .scrollable(false)
    .animationDuration(0)
    // 手动避让底部区域，避免原生自动扩展与胶囊底边距叠加。
    .expandSafeArea([], [])
    .onTabBarClick(() => {
      if (!this.showControls) {
        this.toggleControls();
      }
    })
  }

  @Builder
  readerBottomBar() {
    Stack({ alignContent: Alignment.Top }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.progressMode) {
          Row() {
            Slider({
              value: this.progressDragging ? this.progressPage : Math.max(1, this.currentReaderPage()),
              min: 1,
              max: Math.max(2, this.totalImages),
              step: 1,
              direction: Axis.Horizontal,
              reverse: this.readingMode === 1,
              style: SliderStyle.OutSet
            })
              .direction(Direction.Ltr)
              .width('100%')
              .height(44)
              .trackThickness(4)
              .blockSize({ width: 20, height: 20 })
              .trackColor('#4DFFFFFF')
              .selectedColor(COLOR_PRIMARY)
              .blockColor(COLOR_WHITE)
              .showTips(false)
              .enabled(this.totalImages > 1 && !this.isLoading)
              .accessibilityText('阅读页码')
              .onChange((value: number, mode: SliderChangeMode) => {
                this.onProgressChange(value, mode);
              })
              .onTouch((event: TouchEvent) => {
                this.onProgressTouch(event);
              })
          }
          .width('100%')
          .height(52)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 14 })
          .transition(this.animationsOn
            ? TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
            : TransitionEffect.IDENTITY)
        } else {
          Row() {
            Button('上一话', { type: ButtonType.Normal })
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_WHITE)
              .backgroundColor(Color.Transparent)
              .borderRadius(22)
              .padding({ left: 4, right: 4 })
              .height(44)
              .layoutWeight(1)
              .opacity(this.hasPrevChapter && !this.isLoading ? 1 : 0.38)
              .enabled(this.hasPrevChapter && !this.isLoading)
              .onClick(() => this.goPrevChapter())

            Button({ type: ButtonType.Normal }) {
              Text(this.currentReaderPage() + ' / ' + this.totalImages)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_WHITE)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .backgroundColor(Color.Transparent)
            .borderRadius(22)
            .padding({ left: 4, right: 4 })
            .height(44)
            .layoutWeight(1)
            .enabled(this.totalImages > 1 && !this.isLoading)
            .accessibilityText('当前第' + this.currentReaderPage() + '页，共' + this.totalImages + '页，点击调整进度')
            .onClick(() => this.openProgressControl())

            Button('下一话', { type: ButtonType.Normal })
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_WHITE)
              .backgroundColor(Color.Transparent)
              .borderRadius(22)
              .padding({ left: 4, right: 4 })
              .height(44)
              .layoutWeight(1)
              .opacity(this.hasNextChapter && !this.isLoading ? 1 : 0.38)
              .enabled(this.hasNextChapter && !this.isLoading)
              .onClick(() => this.goNextChapter())
          }
          .width('100%')
          .height(52)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 6, right: 6 })
          .transition(this.animationsOn
            ? TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
            : TransitionEffect.IDENTITY)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .height(52)
      .borderRadius(26)
      .attributeModifier(new ReaderCapsuleMaterial(this.readerMaterialLevel))
    }
    .width('100%')
    .height(60 + Math.max(0, this.readerBottomInset - 7))
    .padding({ left: 12, right: 12, top: 8, bottom: Math.max(0, this.readerBottomInset - 7) })
    .attributeModifier(this.readerBarBackground)
    .opacity(this.showControls ? 1 : 0)
    .hitTestBehavior(this.showControls ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.showControls ? 'auto' : 'no-hide-descendants')
  }

  @Builder
  readerInfoCapsule() {
    Row({ space: 4 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([COLOR_WHITE])
      }
      .width(40)
      .height(48)
      .accessibilityGroup(true)
      .accessibilityText('返回')
      .onClick(() => this.onBack())

      Column({ space: 2 }) {
        Text('第' + this.currentOrder + '话')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_WHITE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.comicTitle)
          .fontSize(13)
          .fontColor('#D9FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 6, right: 14 })
    .borderRadius(26)
    .attributeModifier(new ReaderCapsuleMaterial(this.readerMaterialLevel))
  }

  @Builder
  readerActionCapsule() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(24)
          .fontColor([COLOR_WHITE])
      }
      .width(48)
      .height(48)
      .accessibilityGroup(true)
      .accessibilityText('下载章节')
      .bindMenu(this.readerDownloadMenu(), {
        placement: Placement.BottomRight,
        offset: { x: 0, y: 8 },
        showInSubWindow: false,
        onAppear: (): void => {
          this.downloadMenuVisible = true;
          this.resetProgressControl();
        },
        onDisappear: (): void => {
          this.downloadMenuVisible = false;
        }
      })
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(24)
          .fontColor([COLOR_WHITE])
      }
      .width(48)
      .height(48)
      .accessibilityGroup(true)
      .accessibilityText('阅读设置')
      .onClick(() => this.openReaderSettings())
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 6, right: 6 })
    .borderRadius(26)
    .attributeModifier(new ReaderCapsuleMaterial(this.readerMaterialLevel))
  }

  /** 材质仅在两个胶囊各自的标题栏范围内绘制，不再创建横贯顶部的标题栏背板。 */
  @Builder
  readerTopBar() {
    Row({ space: 12 }) {
      Navigation() {
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 440 })
      .height(52)
      .backgroundColor(Color.Transparent)
      .borderRadius(26)
      .clip(true)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .hideToolBar(true)
      .title({ builder: this.readerInfoCapsule, height: 52 }, {
        barStyle: BarStyle.STACK,
        backgroundColor: Color.Transparent,
        backgroundBlurStyle: BlurStyle.NONE,
        systemMaterial: supportsComponentImmersiveMaterial() ? uiMaterial.Material.empty : undefined
      })
      .hideTitleBar(false)
      .ignoreLayoutSafeArea([], [])

      Navigation() {
      }
      .width(108)
      .height(52)
      .backgroundColor(Color.Transparent)
      .borderRadius(26)
      .clip(true)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .hideToolBar(true)
      .title({ builder: this.readerActionCapsule, height: 52 }, {
        barStyle: BarStyle.STACK,
        backgroundColor: Color.Transparent,
        backgroundBlurStyle: BlurStyle.NONE,
        systemMaterial: supportsComponentImmersiveMaterial() ? uiMaterial.Material.empty : undefined
      })
      .hideTitleBar(false)
      .ignoreLayoutSafeArea([], [])
    }
    .width('100%')
    .height(this.readerTopInset + 60)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 12, right: 12, top: this.readerTopInset + 4, bottom: 4 })
    .attributeModifier(this.readerBarBackground)
    .opacity(this.showControls ? 1 : 0)
    .hitTestBehavior(this.showControls ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.showControls ? 'auto' : 'no-hide-descendants')
  }

  build() {
    Navigation() {
      Stack({ alignContent: Alignment.TopStart }) {
        this.readerWithBottomBar()
        this.readerTopBar()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_READER_BG)
    .mode(NavigationMode.Stack)
    .titleMode(NavigationTitleMode.Mini)
    .hideBackButton(true)
    .hideToolBar(true)
    // 主导航完全隐藏标题栏；顶部只保留两个限定圆角范围的材质宿主。
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      // Window 尚未就绪时，用当前布局尺寸提供初始值，避免读取物理屏幕高度。
      if (this.readerWindow === undefined) {
        this.updateReaderWindowHeight(Number(size.height), false);
      }
    })
  }

  private openReaderSettings(): void {
    this.updateReaderWindowMetrics();
    this.readerSettingsMeasuredHeight = 0;
    this.resetProgressControl();
    this.sheetKind = 'settings';
    this.showSheet = true;
  }

  /** 底部弹窗统一分发（单 bindSheet 避免多实例互相顶掉） */
  @Builder
  unifiedSheet() {
    if (this.sheetKind === 'settings') {
      this.readerSettingsSheet()
    } else if (this.sheetKind === 'export') {
      this.exportSheet()
    } else if (this.sheetKind === 'download') {
      ChapterDownloadSheet({
        chapters: this.readerDownloadChapters,
        selectedOrders: $downloadSelected,
        isDownloaded: (order: number): boolean => this.readerChapterDownloaded(order),
        onStart: (): void => this.startReaderDownloadSelected()
      })
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
        .padding({ bottom: this.readerBottomInset + 12 })
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
          // Scroll 内的内容列按自然高度测量，返回值已经是 vp。
          this.updateReaderSettingsBodyHeight(Number(size.height));
        })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height(this.readerSettingsContentHeight())
    .padding({ left: this.readerLeftInset, right: this.readerRightInset })
    .backgroundColor(COLOR_CARD)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  private updateReaderSettingsBodyHeight(height: number): void {
    if (!this.readerWindowActive || !Number.isFinite(height) || height <= 0) {
      return;
    }
    if (Math.abs(this.readerSettingsBodyHeight - height) > 0.5) {
      this.readerSettingsBodyHeight = height;
    }
  }

  private updateReaderSettingsHeight(height: number): void {
    if (!this.showSheet || this.sheetKind !== 'settings') {
      return;
    }
    const next = this.getUIContext().px2vp(height);
    if (Number.isFinite(next) && next > 0 && Math.abs(this.readerSettingsMeasuredHeight - next) > 0.5) {
      this.readerSettingsMeasuredHeight = next;
    }
  }

  /** 内容少时收紧面板；小窗/横屏时受可用高度限制，余下内容仍可滚动。 */
  private readerSettingsSheetHeight(): number {
    const height = Math.max(1, this.readerWindowHeight);
    const maximum = Math.max(1, Math.min(height * 0.82, height - this.readerTopInset - 12));
    // 顶部横条 4vp + 上下间距 6vp/4vp；正文高度已包含底部安全区留白。
    const content = this.readerSettingsBodyHeight > 0 ? this.readerSettingsBodyHeight + 14 : maximum;
    return Math.min(maximum, content);
  }

  private readerSettingsContentHeight(): number {
    const requested = this.readerSettingsSheetHeight();
    return this.readerSettingsMeasuredHeight > 0
      ? Math.min(requested, this.readerSettingsMeasuredHeight) : requested;
  }
}