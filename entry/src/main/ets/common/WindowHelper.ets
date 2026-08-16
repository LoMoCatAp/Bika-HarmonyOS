import { window } from '@kit.ArkUI';

/**
 * 主窗口单例：窗口级能力（防截屏等）统一入口。
 * 在 EntryAbility 拿到主窗口后注入，页面侧通过 applyPrivacyMode 直接生效。
 */
export class WindowHelper {
  private static mainWindow: window.Window | null = null;

  static setMainWindow(win: window.Window): void {
    WindowHelper.mainWindow = win;
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
