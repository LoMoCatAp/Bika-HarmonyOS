/** 音量键共用仿真翻页流程；控制器不持有页面、位图或阅读进度。 */
export class ReaderCurlController {
  private turnHandler: ((delta: number) => boolean) | null = null;
  private cancelHandler: (() => void) | null = null;

  attach(turn: (delta: number) => boolean, cancel: () => void): void {
    this.turnHandler = turn;
    this.cancelHandler = cancel;
  }

  detach(): void {
    this.turnHandler = null;
    this.cancelHandler = null;
  }

  turn(delta: number): boolean {
    return this.turnHandler?.(delta) ?? false;
  }

  cancel(): void {
    this.cancelHandler?.();
  }
}
