import { router, promptAction, window } from '@kit.ArkUI';
import { ApiService } from '../network/ApiService';
import { ImageUrlManager } from '../network/ImageUrlManager';
import { NetImage } from '../components/NetImage';
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
  @State showSettings: boolean = false;
  /** 阅读亮度（0.1 ~ 1.0，-1 表示跟随系统） */
  @State readerBrightness: number = -1;
  /** 屏幕方向：system | portrait | landscape */
  @State orientation: string = 'system';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;

  private comicId: string = '';
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
    let params = router.getParams() as ReaderRouterParams;
    if (params) {
      this.comicId = params.comicId;
      this.comicTitle = params.comicTitle || '';
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
    this.isLoading = false;
    this.showControls = true;
  }

  private async loadImagesWithCache(): Promise<void> {
    this.generation++;
    let gen = this.generation;
    this.isLoading = true;
    this.errorText = '';
    this.imageDataSource.reload([]);
    this.totalImages = 0;
    this.currentVisibleIndex = 0;

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
    this.showControls = !this.showControls;
  }

  private updateChapterButtons(): void {
    this.hasPrevChapter = this.currentOrder > 1;
    this.hasNextChapter = this.currentOrder < this.epsCount;
  }

  goPrevChapter(): void {
    if (!this.hasPrevChapter) {
      return;
    }
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
      this.readingMode = mode;
      this.showSettings = false;
      console.info('[ReaderPage] readingMode = ' + mode);
    })
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

  aboutToDisappear(): void {
    // 退出阅读器时恢复系统亮度与方向
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
          Swiper() {
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
            }, (img: ReaderImage, index: number) => String(index) + '_' + img.url)
          }
          .index(0)
          .vertical(this.readingMode === 2)
          .indicator(false)
          .loop(false)
          .width('100%')
          .height('100%')
          .backgroundColor(COLOR_READER_BG)
          .onChange((index: number) => {
            this.currentVisibleIndex = index;
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
                  }
                }
                .width('100%')
                .onAppear(() => {
                  this.currentVisibleIndex = index;
                })
              }, (img: ReaderImage, index: number) => String(index) + '_' + img.url + '_' + img.failed)
            }
            .listDirection(Axis.Vertical)
            .scrollBar(BarState.Off)
            .cachedCount(10)
            .width('100%')
            .height('100%')
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

          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(24)
            .fontColor([COLOR_WHITE])
            .onClick(() => {
              this.showSettings = true;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.topSafeHeight + 8, bottom: 8 })
        .backgroundColor(COLOR_READER_TOOLBAR_BG)
        .backdropBlur(20)

        // ── 悬浮底部工具栏 ──
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
      }

      // ── 阅读设置面板 ──
      if (this.showSettings) {
        Column() {
          Scroll() {
            Column({ space: 0 }) {
            Text('阅读模式')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
              .padding({ left: 20, right: 20, top: 16, bottom: 10 })
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
            Row() {
              Button('关闭', { type: ButtonType.Normal })
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontColor(COLOR_PRIMARY)
                .backgroundColor(COLOR_PRIMARY_TINT)
                .borderRadius(22)
                .onClick(() => {
                  this.showSettings = false;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 12 })
            }
            .width('100%')
            .backgroundColor(COLOR_CARD)
            .borderRadius({ topLeft: 20, topRight: 20 })
          }
          .width('100%')
          .constraintSize({ maxHeight: '82%' })
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showSettings = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_READER_BG)
  }
}