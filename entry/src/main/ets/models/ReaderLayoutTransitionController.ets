export class ReaderLayoutTransitionController {
  private captureHandler: (() => void) | null = null;
  private clearHandler: (() => void) | null = null;

  attach(capture: () => void, clear: () => void): void {
    this.captureHandler = capture;
    this.clearHandler = clear;
  }

  capture(): void {
    this.captureHandler?.();
  }

  clear(): void {
    this.clearHandler?.();
  }

  detach(): void {
    this.captureHandler = null;
    this.clearHandler = null;
  }
}
