import { window } from '@kit.ArkUI';

/**
 * 主窗口单例：窗口级能力（防截屏等）统一入口。
 * 在 EntryAbility 拿到主窗口后注入，页面侧通过 applyPrivacyMode 直接生效。
 */
export class WindowHelper {
  private static mainWindow: window.Window | null = null;
  private static readerSystemBarRequest: number = 0;
  private static readerSystemBarQueue: Promise<void> = Promise.resolve();

  static setMainWindow(win: window.Window): void {
    WindowHelper.mainWindow = win;
  }

  /** 串行更新窗口级系统栏，确保退出时的恢复请求不会被较早的隐藏请求覆盖。 */
  static setReaderSystemBars(win: window.Window, visible: boolean, animated: boolean): Promise<void> {
    const request = ++WindowHelper.readerSystemBarRequest;
    WindowHelper.readerSystemBarQueue = WindowHelper.readerSystemBarQueue.then(async (): Promise<void> => {
      if (request !== WindowHelper.readerSystemBarRequest) {
        return;
      }
      await WindowHelper.applyReaderSystemBar(win, 'status', visible, animated);
      if (request === WindowHelper.readerSystemBarRequest) {
        await WindowHelper.applyReaderSystemBar(win, 'navigationIndicator', visible, animated);
      }
    });
    return WindowHelper.readerSystemBarQueue;
  }

  private static async applyReaderSystemBar(win: window.Window, bar: window.SpecificSystemBar,
    visible: boolean, animated: boolean): Promise<void> {
    try {
      await win.setSpecificSystemBarEnabled(bar, visible, animated);
    } catch (err) {
      console.warn('[WindowHelper] reader system bar ' + bar + ' unavailable: ' + JSON.stringify(err));
    }
  }

  /** 应用防截屏开关（截图/录屏时窗口内容变黑） */
  static applyPrivacyMode(flag: boolean): Promise<void> {
    let win = WindowHelper.mainWindow;
    if (win !== null) {
      return win.setWindowPrivacyMode(flag);
    }
    return Promise.reject(new Error('main window not ready'));
  }
}
