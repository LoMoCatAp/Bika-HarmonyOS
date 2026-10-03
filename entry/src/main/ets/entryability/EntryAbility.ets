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
import { WidgetData } from '../common/WidgetData';
import { WidgetExtraData } from '../common/WidgetExtraData';

const DOMAIN = 0x0000;

/**
 * 桌面卡片 FormLink 回传的参数载体。
 * 卡片 params 约定：{ action, comicId, comicTitle }
 *   - 2*2「继续阅读」卡片 与 4*4「最近更新」卡片顶部行：action = 'continue_reading'
 *   - 4*4「最近更新」卡片列表行：action = 'open_comic'
 */
interface WidgetActionPayload {
  action: string;
  comicId: string;
  comicTitle: string;
  timestamp: number;
}

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
    // 冷启动路径：桌面卡片点击首次拉起应用时，参数只在 onCreate 的 want 里
    this.parseWidgetWant(want);
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onCreate');
  }

  /** 从参数集合里安全取一个字符串值（缺失 / 类型异常一律返回空串） */
  private static pickParam(bag: Record<string, Object>, key: string): string {
    try {
      let v = bag[key];
      if (v === undefined || v === null) {
        return '';
      }
      return String(v);
    } catch (err) {
      return '';
    }
  }

  /**
   * 解析桌面卡片点击携带的参数并写入 AppStorage，交由 IndexPage 消费跳转。
   * 值形如 '{"action":"continue_reading","comicId":"...","comicTitle":"...","timestamp":1700000000000}'，
   * timestamp 每次都是新值，保证 IndexPage 的 @Watch 能感知到新事件。
   * 缺字段一律补空串，全过程 try/catch，绝不抛异常。
   */
  private parseWidgetWant(want: Want): void {
    try {
      if (want === undefined || want === null) {
        return;
      }
      let params = want.parameters;
      // 卡片点击是否真的到达系统侧，全靠这条日志判定（onCreate / onNewWant 都会打）
      hilog.info(DOMAIN, 'BikaTag', 'Widget want: %{public}s', JSON.stringify(want));
      if (params === undefined || params === null) {
        return;
      }
      let action: string = '';
      let comicId: string = '';
      let comicTitle: string = '';
      // 卡片侧 postCardAction / FormLink 的 params 会以 JSON 字符串放在
      // want.parameters.params 里（官方 arkts-ui-widget-event-router.md 示例同款），
      // 这里两种形态都兼容：嵌套 params（JSON 字符串或对象）+ 平铺参数。
      let bag: Record<string, Object> | null = null;
      let nested = params['params'];
      if (nested !== undefined && nested !== null) {
        if (typeof nested === 'string') {
          try {
            bag = JSON.parse(nested as string) as Record<string, Object>;
          } catch (e) {
            bag = null;
          }
        } else {
          bag = nested as Record<string, Object>;
        }
      }
      if (bag !== null) {
        action = EntryAbility.pickParam(bag, 'action');
        comicId = EntryAbility.pickParam(bag, 'comicId');
        comicTitle = EntryAbility.pickParam(bag, 'comicTitle');
      }
      if (action.length === 0) {
        action = EntryAbility.pickParam(params, 'action');
      }
      if (comicId.length === 0) {
        comicId = EntryAbility.pickParam(params, 'comicId');
      }
      if (comicTitle.length === 0) {
        comicTitle = EntryAbility.pickParam(params, 'comicTitle');
      }
      // 非卡片来源的普通启动不带 action，不写信号，避免首页被误跳转
      if (action.length === 0) {
        return;
      }
      let payload: WidgetActionPayload = {
        action: action,
        comicId: comicId,
        comicTitle: comicTitle,
        timestamp: Date.now()
      };
      AppStorage.setOrCreate('bika_widget_action', JSON.stringify(payload));
      hilog.info(DOMAIN, 'BikaTag',
        'Widget want parsed: action=%{public}s, hasComicId=%{public}s, hasTitle=%{public}s',
        action, comicId.length > 0 ? 'true' : 'false', comicTitle.length > 0 ? 'true' : 'false');
    } catch (err) {
      hilog.error(DOMAIN, 'BikaTag', 'Failed to parse widget want. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 应用已在后台时点击桌面卡片走 onNewWant（不会再次触发 onCreate）。
   * 复用同一份解析逻辑，保证热启动路径与冷启动一致。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'Ability onNewWant');
    this.parseWidgetWant(want);
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

        // 桌面卡片预热：在应用进程里把卡片要用的列表刷进本地缓存。
        // 卡片进程（FormExtensionAbility）生命周期只有 10s，不能每次都指望它自己联网；
        // 预热之后，卡片一挂上就能同步读到真实作品名。
        try {
          WidgetData.init(this.context);
          WidgetExtraData.init(this.context);
          if (this.context !== null) {
            WidgetData.bootstrapCache(this.context).catch((e: Error) => {
              hilog.info(DOMAIN, 'BikaTag', 'widget cache warmup failed: %{public}s', JSON.stringify(e));
            });
            WidgetExtraData.bootstrapCache(this.context).catch((e: Error) => {
              hilog.info(DOMAIN, 'BikaTag', 'widget extra warmup failed: %{public}s', JSON.stringify(e));
            });
          }
        } catch (e) {
          hilog.error(DOMAIN, 'BikaTag', 'widget warmup init failed: %{public}s', JSON.stringify(e));
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
