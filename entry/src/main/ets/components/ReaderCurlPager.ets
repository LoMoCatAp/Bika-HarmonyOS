import { image } from '@kit.ImageKit';
import { COLOR_READER_BG } from '../common/Constants';
import { ReaderCurlController } from '../models/ReaderCurlController';
import { readerBoundarySwipeDelta, readerCurlTarget, readerCurlProgress, shouldCommitReaderCurl } from '../models/ReaderCurlGeometry';
import { ReaderCurlFrame, ReaderCurlNodeController } from './ReaderCurlRenderer';
import { ReaderPaperRect, validReaderPaperRect } from '../models/ReaderSpineMesh';

let curlPagerSequence: number = 0;

@Component
export struct ReaderCurlPager {
  @Prop @Watch('onExternalChange') index: number = 0;
  @Prop @Watch('onExternalChange') count: number = 0;
  @Prop @Watch('onExternalChange') rtl: boolean = false;
  @Prop @Watch('onExternalChange') revision: number = 0;
  @Prop @Watch('onExternalChange') blocked: boolean = false;
  @Prop @Watch('onExternalChange') animationsOn: boolean = true;
  @Prop @Watch('onExternalChange') maxContentWidth: number = 0;
  @BuilderParam page: (index: number) => void;
  controller: ReaderCurlController = new ReaderCurlController();
  isPaired: (index: number) => boolean = (_index: number): boolean => false;
  isSpreadDecoded: (index: number) => boolean = (_index: number): boolean => false;
  getPageBounds: (index: number, width: number, height: number) => ReaderPaperRect[] =
    (_index: number, _width: number, _height: number): ReaderPaperRect[] => [];
  onIndexChange: (index: number) => void = (_index: number): void => {};
  onTurnStart: () => void = (): void => {};
  onTurnEnd: () => void = (): void => {};
  onBoundaryTurn: (delta: number) => void = (_delta: number): void => {};
  onContentTouch: (event: TouchEvent) => void = (_event: TouchEvent): void => {};
  onContentClick: (x: number, width: number) => void = (_x: number, _width: number): void => {};
  @State drawing: boolean = false;
  private readonly instanceId: string = 'reader_curl_' + (++curlPagerSequence);
  private nodeController: ReaderCurlNodeController = new ReaderCurlNodeController();
  private alive: boolean = false;
  private pageWidth: number = 0;
  private pageHeight: number = 0;
  private busy: boolean = false;
  private settling: boolean = false;
  private session: number = 0;
  private sourceIndex: number = -1;
  private targetIndex: number = -1;
  private committingIndex: number = -1;
  private sessionRevision: number = 0;
  private initialOffset: number = 0;
  private progress: number = 0;
  private frame: ReaderCurlFrame | null = null;
  private gestureOpen: boolean = false;
  private gestureCancelled: boolean = false;
  private drawQueued: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.controller.attach((delta: number): boolean => this.turn(delta), (): void => this.cancelTurn());
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.cancelTurn();
    this.controller.detach();
    this.nodeController.dispose();
  }

  private onExternalChange(property: string): void {
    if (property === 'index' && this.index === this.committingIndex) {
      return;
    }
    this.cancelTurn();
  }

  private visiblePages(): number[] {
    const pages: number[] = [];
    for (let i = Math.max(0, this.index - 1); i <= Math.min(this.count - 1, this.index + 1); i++) {
      pages.push(i);
    }
    return pages;
  }

  private snapshotId(index: number): string {
    return this.instanceId + '_' + index;
  }

  private releaseSnapshot(snapshot: image.PixelMap): void {
    try {
      snapshot.release().catch((_error: Error): void => {});
    } catch (_error) {
      // 同步截图可能在失败前已被框架释放。
    }
  }

  private retireFrame(frame: ReaderCurlFrame): void {
    // 先撤掉绘制节点引用，再让两帧正在提交的绘制完成，最后释放本次专用截图。
    setTimeout((): void => {
      this.releaseSnapshot(frame.current);
      this.releaseSnapshot(frame.next);
    }, 64);
  }

  private imageRect(index: number, rightSide: boolean, paired: boolean): ReaderPaperRect {
    const context = this.getUIContext();
    const rects = this.getPageBounds(index, this.pageWidth, this.pageHeight).filter(validReaderPaperRect);
    const fallback: ReaderPaperRect = { left: 0, top: 0, right: this.pageWidth, bottom: this.pageHeight };
    let rect: ReaderPaperRect = fallback;
    if (paired && rects.length === 2) {
      rect = rects[rightSide ? 1 : 0];
    } else if (rects.length > 0) {
      rect = { left: Math.min(...rects.map((r: ReaderPaperRect): number => r.left)),
        top: Math.min(...rects.map((r: ReaderPaperRect): number => r.top)),
        right: Math.max(...rects.map((r: ReaderPaperRect): number => r.right)),
        bottom: Math.max(...rects.map((r: ReaderPaperRect): number => r.bottom)) };
    }
    return { left: context.vp2px(rect.left), top: context.vp2px(rect.top),
      right: context.vp2px(rect.right), bottom: context.vp2px(rect.bottom) };
  }

  private takeFrame(target: number, offset: number, anchorY: number): ReaderCurlFrame | null {
    if (!this.isSpreadDecoded(this.index) || !this.isSpreadDecoded(target)) {
      return null;
    }
    let current: image.PixelMap | null = null;
    let next: image.PixelMap | null = null;
    try {
      const context = this.getUIContext();
      const pixelWidth = context.vp2px(this.pageWidth);
      const pixelHeight = context.vp2px(this.pageHeight);
      const scale = Math.min(1, 1920 / Math.max(pixelWidth, pixelHeight));
      const snapshot = context.getComponentSnapshot();
      current = snapshot.getSync(this.snapshotId(this.index), { scale, waitUntilRenderFinished: true });
      next = snapshot.getSync(this.snapshotId(target), { scale, waitUntilRenderFinished: true });
      const a = current.getImageInfoSync().size;
      const b = next.getImageInfoSync().size;
      if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0) {
        throw new Error('Empty page snapshot');
      }
      const sourcePaired = this.isPaired(this.index);
      const targetPaired = this.isPaired(target);
      const paired = sourcePaired && targetPaired;
      const fromRight = offset < 0;
      const frontRect = this.imageRect(this.index, fromRight, paired);
      const backRect = paired ? this.imageRect(target, !fromRight, true) : frontRect;
      const height = frontRect.bottom - frontRect.top;
      const anchor = Math.max(0, Math.min(height, context.vp2px(anchorY) - frontRect.top));
      const cornerY = anchor < height * 0.3 ? 0 : anchor > height * 0.7 ? height : anchor;
      return {
        current, next, width: pixelWidth, height: pixelHeight, frontRect, backRect, paired, mixed: sourcePaired !== targetPaired, fromRight,
        touchX: frontRect.right - frontRect.left, touchY: cornerY, cornerY, progress: 0, completed: false
      };
    } catch (error) {
      if (current !== null) {
        this.releaseSnapshot(current);
      }
      if (next !== null) {
        this.releaseSnapshot(next);
      }
      console.warn('[ReaderCurl] snapshot unavailable; completing without animation: ' + String(error));
      return null;
    }
  }

  private begin(offset: number, anchorY: number): boolean {
    if (!this.alive || this.busy || this.blocked || this.pageWidth <= 0 || this.pageHeight <= 0) {
      return false;
    }
    const target = readerCurlTarget(this.index, this.count, offset, this.rtl);
    if (target < 0) {
      return false;
    }
    this.session++;
    this.sourceIndex = this.index;
    this.targetIndex = target;
    this.sessionRevision = this.revision;
    this.initialOffset = offset;
    this.committingIndex = -1;
    this.progress = 0;
    this.busy = true;
    this.settling = false;
    this.onTurnStart();
    this.frame = this.animationsOn ? this.takeFrame(target, offset, anchorY) : null;
    if (this.frame !== null) {
      this.nodeController.show(this.frame);
      this.drawing = true;
    }
    return true;
  }

  private update(offset: number, verticalOffset: number = 0): void {
    if (!this.busy || this.settling) {
      return;
    }
    const width = this.maxContentWidth > 0 ? Math.min(this.pageWidth, this.maxContentWidth) : this.pageWidth;
    this.progress = readerCurlProgress(offset, width, this.initialOffset);
    if (this.frame !== null) {
      this.frame.progress = this.progress;
      const context = this.getUIContext();
      const width = this.frame.frontRect.right - this.frame.frontRect.left;
      const height = this.frame.frontRect.bottom - this.frame.frontRect.top;
      const travel = Math.max(0, offset * Math.sign(this.initialOffset));
      this.frame.touchX = Math.max(-width, width - context.vp2px(travel));
      this.frame.touchY = Math.max(0, Math.min(height, this.frame.cornerY + context.vp2px(verticalOffset)));
      this.frame.completed = false;
      this.queueDragDraw();
    }
  }

  private queueDragDraw(): void {
    if (this.drawQueued) {
      return;
    }
    this.drawQueued = true;
    const session = this.session;
    this.getUIContext().postFrameCallback({
      onFrame: (_time: number): void => {
        if (session !== this.session) {
          return;
        }
        this.drawQueued = false;
        if (this.alive && !this.settling && this.frame !== null) {
          this.nodeController.show(this.frame);
        }
      },
      onIdle: (_time: number): void => {}
    });
  }

  private canCommit(): boolean {
    return this.alive && !this.blocked && this.index === this.sourceIndex && this.revision === this.sessionRevision
      && this.targetIndex >= 0 && this.targetIndex < this.count;
  }

  private finish(commit: boolean, session: number): void {
    if (!this.busy || session !== this.session) {
      return;
    }
    if (!commit || !this.canCommit()) {
      this.cancelTurn();
      return;
    }
    this.committingIndex = this.targetIndex;
    this.onIndexChange(this.targetIndex);
    // 保留终态截图至新页完成布局，避免在提交页码时短暂露出旧页。
    this.afterPaint(session, 2);
  }

  private afterPaint(session: number, remaining: number): void {
    this.getUIContext().postFrameCallback({
      onFrame: (_time: number): void => {
        if (session !== this.session || !this.alive) {
          return;
        }
        if (remaining > 1) {
          this.afterPaint(session, remaining - 1);
        } else {
          this.cancelTurn();
        }
      },
      onIdle: (_time: number): void => {}
    });
  }

  private settle(commit: boolean): void {
    if (!this.busy || this.settling) {
      return;
    }
    this.settling = true;
    const session = this.session;
    if (this.frame === null || !this.animationsOn) {
      this.finish(commit, session);
      return;
    }
    this.animateSettle(session, commit, this.progress, Date.now(), this.frame.touchX, this.frame.touchY);
  }

  private animateSettle(session: number, commit: boolean, start: number, started: number,
    startX: number, startY: number): void {
    this.getUIContext().postFrameCallback({
      onFrame: (_time: number): void => {
        if (session !== this.session || !this.alive || this.frame === null) {
          return;
        }
        const goal = commit ? 1 : 0;
        const duration = 180 + Math.abs(goal - start) * 180;
        const elapsed = Math.min(1, Math.max(0, (Date.now() - started) / duration));
        this.progress = start + (goal - start) * (1 - Math.pow(1 - elapsed, 3));
        this.frame.progress = this.progress;
        const width = this.frame.frontRect.right - this.frame.frontRect.left;
        const fraction = 1 - Math.pow(1 - elapsed, 3);
        this.frame.touchX = startX + ((commit ? -width : width) - startX) * fraction;
        this.frame.touchY = startY + (this.frame.cornerY - startY) * fraction;
        this.frame.completed = commit && elapsed >= 1;
        this.nodeController.show(this.frame);
        if (elapsed >= 1) {
          this.finish(commit, session);
        } else {
          this.animateSettle(session, commit, start, started, startX, startY);
        }
      },
      onIdle: (_time: number): void => {}
    });
  }

  private cancelTurn(): void {
    if (this.gestureOpen) {
      this.gestureCancelled = true;
    }
    this.session++;
    this.drawQueued = false;
    this.nodeController.clear();
    this.drawing = false;
    const frame = this.frame;
    this.frame = null;
    if (frame !== null) {
      this.retireFrame(frame);
    }
    const wasBusy = this.busy;
    this.busy = false;
    this.settling = false;
    this.committingIndex = -1;
    if (wasBusy) {
      this.onTurnEnd();
    }
  }

  private turn(delta: number): boolean {
    if (this.gestureOpen || (delta !== 1 && delta !== -1)) {
      return false;
    }
    const offset = (delta === 1 ? -1 : 1) * (this.rtl ? -1 : 1);
    if (!this.begin(offset, this.pageHeight * 0.8)) {
      return false;
    }
    this.settle(true);
    return true;
  }

  private beginPan(event: GestureEvent): void {
    const offsetY = event.offsetY ?? 0;
    if (Math.abs(event.offsetX) < Math.abs(offsetY) * 0.65) {
      return;
    }
    const finger = event.fingerList[0];
    const startY = finger === undefined ? this.pageHeight * 0.8 : finger.localY - offsetY;
    this.begin(event.offsetX, startY);
  }

  private onPanStart(event: GestureEvent): void {
    this.gestureOpen = true;
    this.gestureCancelled = this.busy || this.blocked;
    if (!this.gestureCancelled) {
      this.beginPan(event);
    }
  }

  private onPanUpdate(event: GestureEvent): void {
    if (!this.gestureOpen || this.gestureCancelled) {
      return;
    }
    if (!this.busy) {
      this.beginPan(event);
    }
    this.update(event.offsetX, event.offsetY ?? 0);
  }

  private onPanEnd(event: GestureEvent): void {
    const active = this.gestureOpen && !this.gestureCancelled && this.alive && !this.blocked;
    this.gestureOpen = false;
    if (!active) {
      return;
    }
    if (!this.busy) {
      const delta = readerBoundarySwipeDelta(this.index, this.count, event.offsetX, event.offsetY ?? 0, this.rtl);
      if (delta !== 0) {
        this.onBoundaryTurn(delta);
      }
      return;
    }
    this.update(event.offsetX, event.offsetY ?? 0);
    this.settle(shouldCommitReaderCurl(this.progress, this.initialOffset, event.velocityX));
  }

  private onPanCancel(): void {
    this.gestureOpen = false;
    this.gestureCancelled = true;
    this.settle(false);
  }

  private resize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return;
    }
    if (Math.abs(width - this.pageWidth) > 0.5 || Math.abs(height - this.pageHeight) > 0.5) {
      this.cancelTurn();
      this.pageWidth = width;
      this.pageHeight = height;
      this.nodeController.resize(width, height);
    }
  }

  build() {
    Stack() {
      ForEach(this.visiblePages(), (pageIndex: number) => {
        Stack() {
          this.page(pageIndex)
        }
        .width('100%').height('100%')
        .backgroundColor(COLOR_READER_BG)
        .id(this.snapshotId(pageIndex))
        .zIndex(pageIndex === this.index ? 1 : 0)
        .hitTestBehavior(pageIndex === this.index && !this.busy ? HitTestMode.Default : HitTestMode.None)
        .accessibilityLevel(pageIndex === this.index ? 'auto' : 'no-hide-descendants')
      }, (pageIndex: number): string => String(pageIndex))
      NodeContainer(this.nodeController)
        .width('100%').height('100%')
        .zIndex(2)
        .opacity(this.drawing ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
    }
    .width('100%').height('100%')
    .clip(true)
    .onAreaChange((_oldArea: Area, area: Area): void => this.resize(area))
    .onTouch((event: TouchEvent): void => this.onContentTouch(event))
    .onClick((event: ClickEvent): void => {
      if (!this.busy) {
        this.onContentClick(event.x, this.pageWidth);
      }
    })
    .gesture(PanGesture({ direction: PanDirection.All, distance: 6 })
      .onActionStart((event: GestureEvent): void => this.onPanStart(event))
      .onActionUpdate((event: GestureEvent): void => this.onPanUpdate(event))
      .onActionEnd((event: GestureEvent): void => this.onPanEnd(event))
      .onActionCancel((): void => this.onPanCancel()))
  }
}
