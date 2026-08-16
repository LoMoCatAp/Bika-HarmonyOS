import { ImageLoader } from '../common/ImageLoader';
import { IMAGE_HOST_POOL } from '../common/Constants';

/**
 * 网络图片组件：
 * - 通过 ImageLoader（自有网络栈）加载并缓存 PixelMap；
 * - 临时失败自动退避重试（2s 起倍增、30s 封顶）；
 * - 全部候选失败后显示点击重试占位；
 * - 支持四角/顶角圆角。
 */
@Component
export struct NetImage {
  @Prop src: string = '';
  @Prop candidates: string[] = [];
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop radius: number = 0;
  @Prop topRadius: number = 0;
  @Prop placeholderColor: string = '#EEF1F7';
  /** true=填满父容器（翻页模式）；false=按图片比例自适应高度（连续滚动无缝模式） */
  @Prop fillParent: boolean = false;
  @State pixelMap: PixelMap | null = null;
  @State failed: boolean = false;
  @State errorText: string = '';
  @State loading: boolean = false;
  /** 占位呼吸动画 */
  @State pulse: number = 0.5;
  private retryCount: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
    if (animOn) {
      animateTo({
        duration: 900,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.pulse = 0.9;
      });
    }
    this.load();
  }

  aboutToDisappear(): void {
    this.pulse = 0.5;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private async load(): Promise<void> {
    if (this.loading || this.src.length === 0) {
      return;
    }
    this.loading = true;
    this.failed = false;
    let urls: string[] = [this.src];
    for (let c of this.candidates) {
      if (c.length > 0 && urls.indexOf(c) < 0) {
        urls.push(c);
      }
    }
    // 自动镜像候选（BIKA DomainFallbackInterceptor 语义）：
    // 同路径换镜像域名依次回退
    let idx = this.src.indexOf('/static/');
    if (idx > 0) {
      let pathPart = this.src.substring(idx);
      for (let h of IMAGE_HOST_POOL) {
        let u = h + pathPart;
        if (u !== this.src && urls.indexOf(u) < 0) {
          urls.push(u);
        }
      }
    }
    try {
      let pm = await ImageLoader.load(urls);
      this.pixelMap = pm;
      this.retryCount = 0;
    } catch (err) {
      this.failed = true;
      this.errorText = (err as Error).message || '加载失败';
      // BIKA RetryableAsyncImage 退避重试语义
      this.retryCount++;
      let delay = Math.min(2000 * (1 << Math.min(this.retryCount - 1, 4)), 30000);
      this.timer = setTimeout(() => {
        this.load();
      }, delay);
    } finally {
      this.loading = false;
    }
  }

  private retry(): void {
    if (this.failed) {
      this.failed = false;
      this.load();
    }
  }

  build() {
    Stack() {
      if (this.src.startsWith('file://')) {
        Image(this.src)
          .width('100%')
          .height(this.fillParent ? '100%' : undefined)
          .draggable(false)
          .objectFit(this.fit)
          .borderRadius(this.topRadius > 0
            ? { topLeft: this.topRadius, topRight: this.topRadius, bottomLeft: this.radius, bottomRight: this.radius }
            : this.radius)
      } else if (this.pixelMap !== null) {
        Image(this.pixelMap)
          .width('100%')
          .height(this.fillParent ? '100%' : undefined)
          .draggable(false)
          .objectFit(this.fit)
          .borderRadius(this.topRadius > 0
            ? { topLeft: this.topRadius, topRight: this.topRadius, bottomLeft: this.radius, bottomRight: this.radius }
            : this.radius)
      } else if (this.failed) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor(['#98A1B3'])
          Text('加载失败')
            .fontSize(11)
            .fontColor('#98A1B3')
          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(9)
              .fontColor('#98A1B3')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .padding({ left: 4, right: 4 })
          }
        }
        .width('100%')
        .height(this.fillParent ? '100%' : 180)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.placeholderColor)
        .borderRadius(this.topRadius > 0
          ? { topLeft: this.topRadius, topRight: this.topRadius, bottomLeft: this.radius, bottomRight: this.radius }
          : this.radius)
        .onClick(() => this.retry())
      } else {
        Column()
          .width('100%')
          .height(this.fillParent ? '100%' : 180)
          .backgroundColor(this.placeholderColor)
          .opacity(this.pulse)
          .borderRadius(this.topRadius > 0
            ? { topLeft: this.topRadius, topRight: this.topRadius, bottomLeft: this.radius, bottomRight: this.radius }
            : this.radius)
      }
    }
    .width('100%')
    .height(this.fillParent ? '100%' : undefined)
  }
}