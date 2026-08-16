import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, bundleManager, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiRouteManager } from '../network/ApiRouteManager';
import { BikaHttpClient } from '../network/BikaHttpClient';
import { WindowHelper } from '../common/WindowHelper';
import { CacheManager } from '../common/CacheManager';
import { ImageLoader } from '../common/ImageLoader';
import { ApiService } from '../network/ApiService';

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
    // 记录当前版本号（检查更新对比用）
    try {
      let info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      AppStorage.setOrCreate('bika_current_version', info.versionName);
    } catch (e) {
      hilog.error(DOMAIN, 'BikaTag', 'Failed to read version. Cause: %{public}s', JSON.stringify(e));
    }
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

      // 注入主窗口单例
      WindowHelper.setMainWindow(windowClass);

      // 从持久化恢复全部设置并应用（AppStorage 为内存态）
      // 显式传入 AbilityContext：getContext() 全局函数在非 UI 场景不可用
      ImageLoader.initDiskCache(this.context as common.UIAbilityContext);
      CacheManager.getInstance(this.context).then(cache => {
        let colorMode = cache.getSetting('color_mode', 'system');
        AppStorage.setOrCreate('bika_color_mode', colorMode);
        AppStorage.set('bika_color_mode', colorMode);
        AppStorage.setOrCreate('bika_material_level', cache.getSetting('material_level', 'EXQUISITE'));
        AppStorage.set('bika_material_level', cache.getSetting('material_level', 'EXQUISITE'));
        AppStorage.setOrCreate('bika_auto_punch', cache.getSetting('auto_punch', 'false') === 'true');
        AppStorage.set('bika_auto_punch', cache.getSetting('auto_punch', 'false') === 'true');
        AppStorage.setOrCreate('bika_secure_screen', cache.getSetting('secure_screen', 'false') === 'true');
        AppStorage.set('bika_secure_screen', cache.getSetting('secure_screen', 'false') === 'true');
        AppStorage.setOrCreate('bika_dns_api_ips', cache.getSetting('dns_api_ips', '[]'));
        AppStorage.set('bika_dns_api_ips', cache.getSetting('dns_api_ips', '[]'));
        AppStorage.setOrCreate('bika_dns_image_ips', cache.getSetting('dns_image_ips', '[]'));
        AppStorage.set('bika_dns_image_ips', cache.getSetting('dns_image_ips', '[]'));
        AppStorage.setOrCreate('bika_blocked_tags', JSON.stringify(cache.loadBlockedTags()));
        AppStorage.set('bika_blocked_tags', JSON.stringify(cache.loadBlockedTags()));
        AppStorage.setOrCreate('bika_animations', cache.getSetting('animations', 'true') === 'true');
        AppStorage.set('bika_animations', cache.getSetting('animations', 'true') === 'true');
        let proxyOn = cache.getSetting('use_system_proxy', 'false') === 'true';
        AppStorage.setOrCreate('bika_use_proxy', proxyOn);
        ApiService.setUseSystemProxy(proxyOn);

        // 应用显示模式
        try {
          let appCtx = this.context.getApplicationContext();
          if (colorMode === 'dark') {
            appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
          } else if (colorMode === 'light') {
            appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
          } else {
            appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
          }
        } catch (e) {
          hilog.error(DOMAIN, 'BikaTag', 'Failed to apply color mode. Cause: %{public}s', JSON.stringify(e));
        }

        // 应用防截屏
        if (cache.getSetting('secure_screen', 'false') === 'true') {
          windowClass.setWindowPrivacyMode(true).catch((e: BusinessError) => {
            hilog.error(DOMAIN, 'BikaTag', 'Failed to set privacy mode. Cause:' + JSON.stringify(e));
          });
        }
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

    // 启动即后台刷新直连 IP 池（非阻塞，默认池已可用）
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
