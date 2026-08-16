import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiRouteManager } from '../network/ApiRouteManager';
import { BikaHttpClient } from '../network/BikaHttpClient';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'BikaTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 记录系统深浅色（沉浸光感材质按此取色）
    const systemMode: string = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? 'dark' : 'light';
    AppStorage.setOrCreate('system_color_mode', systemMode);
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 跟随系统时同步系统深浅色（仅记录设备模式，应用内覆盖不动）
    const selectedMode: string = String(AppStorage.get('bika_color_mode') ?? 'system');
    if (selectedMode !== 'system') {
      return;
    }
    const isDark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('system_color_mode', isDark ? 'dark' : 'light');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onDestroy');
    // 释放共享 HTTP 连接池
    BikaHttpClient.destroySharedRequest();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.getMainWindow((err, windowClass) => {
      let errCode: number = err.code;
      if (errCode) {
        hilog.error(DOMAIN, 'BikaTag', 'Failed to obtain the main window. Cause: ' + JSON.stringify(err));
        return;
      }

      // 设置窗口为全屏沉浸式模式
      windowClass.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, 'BikaTag', 'Succeeded in setting the window layout to full-screen mode.');
      }).catch((e: BusinessError) => {
        hilog.error(DOMAIN, 'BikaTag', 'Failed to set fullscreen. Cause:' + JSON.stringify(e));
      });

      // 获取状态栏区域高度
      let notificationArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      let topHeight = px2vp(notificationArea.topRect.height);
      AppStorage.setOrCreate('topSafeHeight', topHeight);

      // 获取导航栏区域高度
      let navigationArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      let bottomHeight = px2vp(navigationArea.bottomRect.height);
      AppStorage.setOrCreate('bottomSafeHeight', bottomHeight);

      hilog.info(DOMAIN, 'BikaTag', `topSafeHeight=${topHeight}, bottomSafeHeight=${bottomHeight}`);
    });

    // 复刻 BIKA startUpSyncWork：启动即后台刷新直连 IP 池（非阻塞，默认池已可用）
    ApiRouteManager.getInstance().ensureInitialized();

    windowStage.loadContent('pages/IndexPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'BikaTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'BikaTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onBackground');
  }
}
