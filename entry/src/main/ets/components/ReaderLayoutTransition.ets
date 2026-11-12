import { image } from '@kit.ImageKit';
import { ReaderLayoutTransitionController } from '../models/ReaderLayoutTransitionController';

let layoutTransitionSequence: number = 0;

/** 在单双页重排前保留旧画面，待新组完成布局后淡出。 */
@Component
export struct ReaderLayoutTransition {
  @Prop animationsOn: boolean = true;
  controller: ReaderLayoutTransitionController = new ReaderLayoutTransitionController();
  @BuilderParam content: () => void;
  @State snapshot: image.PixelMap | null = null;
  @State snapshotOpacity: number = 0;
  @State snapshotScale: number = 1;
  private readonly contentId: string = 'reader_layout_' + (++layoutTransitionSequence);
  private alive: boolean = false;
  private revision: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.controller.attach((): void => this.capture(), (): void => this.clear());
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.clear();
    this.controller.detach();
  }

  private clear(): void {
    this.revision++;
    const old = this.snapshot;
    this.snapshot = null;
    this.snapshotOpacity = 0;
    this.snapshotScale = 1;
    if (old !== null) {
      setTimeout((): void => {
        try {
          old.release().catch((_error: Error): void => {});
        } catch (_error) {}
      }, 64);
    }
  }

  private capture(): void {
    this.clear();
    if (!this.alive || !this.animationsOn) {
      return;
    }
    try {
      this.snapshot = this.getUIContext().getComponentSnapshot().getSync(this.contentId);
      this.snapshotOpacity = 1;
      this.snapshotScale = 1;
      this.afterLayout(this.revision, 2);
    } catch (error) {
      this.clear();
      console.warn('[ReaderLayoutTransition] snapshot unavailable: ' + String(error));
    }
  }

  private afterLayout(revision: number, frames: number): void {
    this.getUIContext().postFrameCallback({
      onFrame: (_time: number): void => {
        if (!this.alive || revision !== this.revision) {
          return;
        }
        if (frames > 1) {
          this.afterLayout(revision, frames - 1);
          return;
        }
        this.getUIContext().animateTo({
          duration: 240, curve: Curve.EaseInOut,
          onFinish: (): void => {
            if (this.alive && revision === this.revision) {
              this.clear();
            }
          }
        }, (): void => {
          this.snapshotOpacity = 0;
          this.snapshotScale = 1.015;
        });
      },
      onIdle: (_time: number): void => {}
    });
  }

  build() {
    Stack() {
      Stack() {
        this.content()
      }
      .width('100%').height('100%')
      .id(this.contentId)
      if (this.snapshot !== null) {
        Image(this.snapshot)
          .width('100%').height('100%')
          .objectFit(ImageFit.Fill)
          .opacity(this.snapshotOpacity)
          .scale({ x: this.snapshotScale, y: this.snapshotScale })
          .draggable(false)
          .hitTestBehavior(HitTestMode.Block)
          .accessibilityLevel('no-hide-descendants')
      }
    }
    .width('100%').height('100%')
    .clip(true)
  }
}
