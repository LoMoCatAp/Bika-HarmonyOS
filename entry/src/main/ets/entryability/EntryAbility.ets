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
  /** 卡片缓存预热节流键（setting_ 前缀下）：窗口内只预热一次 */
  private static readonly WIDGET_WARMUP_KEY: string = 'widget_warmup_ts';
  /** 卡片缓存预热最小间隔：30 分钟 */
  private static readonly WIDGET_WARMUP_INTERVAL_MS: number = 30 * 60 * 1000;

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
    // ── 同步恢复登录态（修复冷启动先渲染「未登录」、过几秒才刷成已登录）──
    // preferences.getPreferencesSync 同步打开偏好库并持有句柄；在 loadContent 之前
    // 同步读取 auth_token，保证页面首帧渲染时 isLoggedIn 就是正确值。
    ApiService.setAppContext(this.context);
    ApiService.registerLogoutCleanup((): void => {
      // 退出登录时清掉主应用进程内缓存的旧作品信息（卡片内存态）
      WidgetData.resetMemo();
      hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'logout cleanup: WidgetData.resetMemo done');
    });
    let authCache: CacheManager = CacheManager.initSync(this.context);
    let bootTokenPresent: boolean = authCache.getToken().length > 0;
    let bootTokenInvalid: boolean = authCache.isTokenInvalid();
    let bootLoggedIn: boolean = bootTokenPresent && !bootTokenInvalid;
    // 同步句柄就绪才算「登录态已确定」；未就绪则由下面的异步复检置位
    let bootResolved: boolean = authCache.isReady();
    AppStorage.setOrCreate('isLoggedIn', bootLoggedIn);
    AppStorage.setOrCreate('auth_resolved', bootResolved);
    // 顺序打点：证明同步置位发生在页面首帧之前（只打印布尔与时间戳，不打印令牌内容）
    hilog.info(DOMAIN, 'BikaTag', '%{public}s', 'auth sync ts=' + Date.now()
      + ' tokenPresent=' + (bootTokenPresent ? 'true' : 'false')
      + ' invalid=' + (bootTokenInvalid ? 'true' : 'false')
      + ' isLoggedIn=' + (bootLoggedIn ? 'true' : 'false')
      + ' auth_resolved=' + (bootResolved ? 'true' : 'false'));
    // 首次登录态判定（异步复检）：保留原凭据恢复路径，发现令牌失效会把 isLoggedIn 置回 false
    ApiService.getInstance().resolveAuthState().catch((e: Error) => {
      hilog.debug(DOMAIN, 'BikaTag', 'auth resolve failed: %{public}s', JSON.stringify(e));
    });

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
      // 只记录「是否携带参数」这一布尔事实：完整 want 含作品名等敏感内容，禁止打印
      hilog.debug(DOMAIN, 'BikaTag', 'Widget want received, hasParams=%{public}s',
        (params === undefined || params === null) ? 'false' : 'true');
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
      // 只打 action 与布尔事实，不打印作品名 / comicId 原文
      hilog.debug(DOMAIN, 'BikaTag',
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
        // 预热改为串行 + 30 分钟节流，避免冷启动并发请求触发频控熔断（见 warmupWidgetCache）
        this.warmupWidgetCache(cache).catch((e: Error) => {
          hilog.debug(DOMAIN, 'BikaTag', 'widget warmup failed: %{public}s', JSON.stringify(e));
        });

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

    this.loadInitialContent(windowStage);
  }

  /** 登录态恢复后再决定首屏，每个版本只展示一次登录门。 */
  private async loadInitialContent(windowStage: window.WindowStage): Promise<void> {
    let showGate: boolean = false;
    try {
      await ApiService.getInstance().resolveAuthState();
      const cache = await CacheManager.getInstance(this.context);
      const version = AppStorage.get<string>('bika_current_version') ?? '';
      showGate = AppStorage.get<boolean>('auth_resolved') === true &&
        AppStorage.get<boolean>('isLoggedIn') === false && cache.isReady() &&
        version.length > 0 && cache.getSetting('login_gate_shown_version', '') !== version;
      if (showGate) {
        cache.saveSetting('login_gate_shown_version', version);
      }
    } catch (err) {
      // 无法确定登录态或无法持久化时，保留主页入口，避免反复弹门。
      showGate = false;
      hilog.warn(DOMAIN, 'BikaTag', 'Initial login gate state unavailable.');
    }
    AppStorage.setOrCreate('bika_login_gate_pending', showGate);
    windowStage.loadContent(showGate ? 'pages/LoginPage' : 'pages/IndexPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'BikaTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'BikaTag', 'Succeeded in loading the content.');
    });
  }

  /**
   * 桌面卡片缓存预热：串行 + 节流。
   *
   * 两个 bootstrapCache 各自都会立刻发网络请求；冷启动时并发调用会在数毫秒内
   * 连发两枪（实测两个请求相隔 8ms），极易命中服务端低频窗口的全局频控熔断
   * （命中后主应用所有请求冻结 90s 起，最长 60 分钟）。
   *
   * 因此：
   *  1) 用 preferences 记时间戳，30 分钟内直接跳过；
   *  2) 首次执行时逐个 await，保证同一时刻只有一个请求在途。
   */
  private async warmupWidgetCache(cache: CacheManager): Promise<void> {
    try {
      let last = parseInt(cache.getSetting(EntryAbility.WIDGET_WARMUP_KEY, '0'));
      let now = Date.now();
      if (!isNaN(last) && last > 0 && now - last < EntryAbility.WIDGET_WARMUP_INTERVAL_MS) {
        hilog.debug(DOMAIN, 'BikaTag', '%{public}s', 'widget warmup skipped (throttled)');
        return;
      }
      // 先落时间戳：即便本次失败也在 30 分钟内不再重试，避免失败重试把频控窗口续期
      cache.saveSetting(EntryAbility.WIDGET_WARMUP_KEY, now.toString());
      WidgetData.init(this.context);
      WidgetExtraData.init(this.context);
      await WidgetData.bootstrapCache(this.context);
      await WidgetExtraData.bootstrapCache(this.context);
      hilog.debug(DOMAIN, 'BikaTag', '%{public}s', 'widget warmup done');
    } catch (e) {
      hilog.debug(DOMAIN, 'BikaTag', 'widget warmup failed: %{public}s', JSON.stringify(e));
    }
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
