import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { CacheManager } from './CacheManager';
import { ApiService } from '../network/ApiService';
import { BikaComicSummary, buildImageUrl } from '../models/Comic';
import { WidgetCover, WidgetCoverBundle, WidgetCoverFormData, WidgetCoverRequest } from './WidgetCover';

/**
 * 桌面卡片数据层：「继续阅读」2*2 与「最近更新」4*4 共用。
 *
 * 设计约束：
 * - 卡片 UI 处于受限 ArkTS 子集，卡片进程也不适合读 preferences；
 *   因此真实数据统一由 FormExtensionAbility 调用本类取得，再通过
 *   formBindingData → @LocalStorageProp 下发给卡片。
 * - 所有方法都吞掉异常并返回安全默认值，绝不向调用方抛异常。
 * - 开关默认开启（用户要求卡片默认显示真实内容与封面）；
 *   关闭「显示真实内容」时只下发占位数据，不暴露任何作品名。
 * - 封面不下发 http 地址：由 common/WidgetCover.ets 下载成沙箱文件 fd，
 *   通过 formImages 下发，卡片侧用 Image('memory://' + coverKey) 渲染。
 *
 * preferences 名称与 key 约定与 CacheManager 完全一致（'BikaCache'）：
 *   history_ids
 *   history_title_<comicId> / history_order_<comicId> / history_time_<comicId> / history_cover_<comicId>
 *   progress_<comicId> / page_<comicId>_<order>
 *   setting_<key>（CacheManager.saveSetting / getSetting 同款）
 */

/** 「继续阅读」聚合信息 */
export class WidgetReadInfo {
  comicId: string = '';
  title: string = '';
  order: number = 0;
  page: number = 0;
  cover: string = '';
  timestamp: number = 0;
}

/**
 * 「最近更新」列表项。
 * cover 为内部使用的 http(s) 地址，不下发给卡片；
 * 下发给卡片的是 coverKey（memory:// 的 key）。
 */
export class WidgetUpdateItem {
  id: string = '';
  title: string = '';
  cover: string = '';
  /** 看到第几话（0 = 未知） */
  order: number = 0;
  /** 最后阅读时间戳（0 = 未知） */
  time: number = 0;
  /** 下发到卡片的封面 key（空串 = 显示占位） */
  coverKey: string = '';
}

/** 下发给卡片的列表行（只含卡片需要的字段，不含 http 地址） */
interface WidgetCardRow {
  id: string;
  title: string;
  coverKey: string;
  order: number;
  time: number;
}

/**
 * 「继续阅读」2*2 与「最近更新」4*4 的绑定数据（key 为超集，卡片只取自己认识的 key）。
 * formImages / coverToken 由 WidgetCoverFormData 提供。
 */
export class WidgetRecentFormData extends WidgetCoverFormData {
  recentTitle: string = '最近更新';
  continueTitle: string = '';
  continueSubtitle: string = '';
  continueComicId: string = '';
  /** 「继续阅读」封面 key（memory:// 的 key） */
  continueCoverKey: string = '';
  /** 「最近更新」列表 JSON：[{ id, title, coverKey, order, time }] */
  recentJson: string = '[]';
  showCover: string = 'true';
  emptyText: string = '打开 Bika 开始阅读';
}

export class WidgetData {
  private static readonly PREF_NAME: string = 'BikaCache';
  private static readonly KEY_HISTORY_IDS: string = 'history_ids';
  private static readonly KEY_TOKEN: string = 'auth_token';
  private static readonly PREFIX_HISTORY_TITLE: string = 'history_title_';
  private static readonly PREFIX_HISTORY_ORDER: string = 'history_order_';
  private static readonly PREFIX_HISTORY_TIME: string = 'history_time_';
  private static readonly PREFIX_HISTORY_COVER: string = 'history_cover_';
  private static readonly PREFIX_PROGRESS: string = 'progress_';
  private static readonly PREFIX_PAGE: string = 'page_';
  private static readonly PREFIX_SETTING: string = 'setting_';
  /** formId → 卡片名（onUpdateForm 只给 formId，需要靠它分派数据源） */
  private static readonly PREFIX_FORM_NAME: string = 'widget_form_name_';

  /** 主应用开关：卡片是否显示真实作品名/历史（默认开启） */
  static readonly SETTING_REAL_DATA: string = 'widget_show_real_data';
  /** 主应用开关：卡片是否显示封面（默认开启） */
  static readonly SETTING_SHOW_COVER: string = 'widget_show_cover';
  /** 最近更新列表缓存（JSON 字符串），由本类写入 / 读取 */
  private static readonly SETTING_RECENT_JSON: string = 'widget_recent_json';

  private static readonly MAX_ROWS: number = 4;
  /** FormExtensionAbility 只有 10s 生命周期，网络预算必须远小于它 */
  private static readonly NET_TIMEOUT_MS: number = 3500;

  private static syncPrefs: preferences.Preferences | null = null;
  private static memoReadInfo: WidgetReadInfo | null = null;

  // ═══════════════ 初始化与同步读取 ═══════════════

  /** FormExtensionAbility 启动时调用一次：缓存 preferences 句柄，之后可全同步读取 */
  static init(ctx: Context): void {
    try {
      let options: preferences.Options = { name: WidgetData.PREF_NAME };
      WidgetData.syncPrefs = preferences.getPreferencesSync(ctx, options);
    } catch (err) {
      console.warn('[WidgetData] init failed: ' + JSON.stringify(err));
    }
  }

  private static openPrefsSync(ctx?: Context): preferences.Preferences | null {
    if (WidgetData.syncPrefs !== null) {
      return WidgetData.syncPrefs;
    }
    try {
      let context: Context | null = null;
      if (ctx !== undefined && ctx !== null) {
        context = ctx;
      } else {
        // getContext() 只在 UI 上下文可用；卡片 / FormExtensionAbility 非 UI 场景会抛异常
        context = getContext();
      }
      if (context === null) {
        return null;
      }
      let options: preferences.Options = { name: WidgetData.PREF_NAME };
      WidgetData.syncPrefs = preferences.getPreferencesSync(context, options);
      return WidgetData.syncPrefs;
    } catch (err) {
      return null;
    }
  }

  private static readString(prefs: preferences.Preferences, key: string, def: string): string {
    try {
      let v: preferences.ValueType = prefs.getSync(key, def);
      if (typeof v === 'string') {
        return v as string;
      }
      return def;
    } catch (err) {
      return def;
    }
  }

  private static readNumber(prefs: preferences.Preferences, key: string, def: number): number {
    try {
      let v: preferences.ValueType = prefs.getSync(key, def);
      if (typeof v === 'number') {
        return v as number;
      }
      if (typeof v === 'string') {
        let n = parseInt(v as string);
        return isNaN(n) ? def : n;
      }
      return def;
    } catch (err) {
      return def;
    }
  }

  // ═══════════════ formId → 卡片名 ═══════════════

  /** onAddForm 时记住 formId 对应的卡片名，供 onUpdateForm 分派 */
  static rememberFormName(formId: string, name: string, ctx?: Context): void {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null || formId.length === 0 || name.length === 0) {
        return;
      }
      prefs.putSync(WidgetData.PREFIX_FORM_NAME + formId, name);
      prefs.flushSync();
    } catch (err) {
      console.warn('[WidgetData] rememberFormName failed: ' + JSON.stringify(err));
    }
  }

  static recallFormName(formId: string, ctx?: Context): string {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null || formId.length === 0) {
        return '';
      }
      return WidgetData.readString(prefs, WidgetData.PREFIX_FORM_NAME + formId, '');
    } catch (err) {
      return '';
    }
  }

  static forgetFormName(formId: string, ctx?: Context): void {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null || formId.length === 0) {
        return;
      }
      prefs.deleteSync(WidgetData.PREFIX_FORM_NAME + formId);
      prefs.flushSync();
    } catch (err) {
      // 键不存在 / 删除失败：忽略
    }
  }

  // ═══════════════ 「继续阅读」 ═══════════════

  /** 最近阅读的完整信息（作品名 / 话数 / 页码 / 封面 / 时间） */
  static getRecentReadInfo(ctx?: Context): WidgetReadInfo | null {
    try {
      if (WidgetData.memoReadInfo !== null && WidgetData.memoReadInfo.title.length > 0) {
        return WidgetData.memoReadInfo;
      }
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null) {
        return WidgetData.memoReadInfo;
      }
      let info = WidgetData.readRecentFromPrefs(prefs);
      if (info !== null) {
        WidgetData.memoReadInfo = info;
      }
      return info;
    } catch (err) {
      return null;
    }
  }

  /**
   * 异步读取最近阅读信息：优先走 CacheManager（含 index 索引与排序），
   * 失败时回退到同步 preferences 扫描。
   */
  static async loadRecentReadInfo(ctx?: Context): Promise<WidgetReadInfo | null> {
    try {
      let cache = await CacheManager.getInstance(ctx);
      let items = cache.loadHistory();
      if (items.length === 0) {
        return WidgetData.getRecentReadInfo(ctx);
      }
      let top = items[0];
      let info = new WidgetReadInfo();
      info.comicId = top.comicId;
      info.title = top.title;
      info.order = top.order;
      info.timestamp = top.timestamp;
      info.cover = top.coverUrl;
      if (top.order > 0) {
        info.page = cache.getPageProgress(top.comicId, top.order);
      }
      WidgetData.memoReadInfo = info;
      return info;
    } catch (err) {
      return WidgetData.getRecentReadInfo(ctx);
    }
  }

  /**
   * 同步读取最近一条历史：
   * - 先用 history_ids 索引；
   * - 再用 getAllSync() 扫描 history_time_<id> 兜底（索引缺失/不完整时仍可用）；
   * - 标题优先 history_title_<id>，没有再尝试漫画列表缓存（不为标题发网络请求）。
   */
  private static readRecentFromPrefs(prefs: preferences.Preferences): WidgetReadInfo | null {
    let ids: string[] = WidgetData.collectHistoryIds(prefs);
    let best: WidgetReadInfo | null = null;
    for (let id of ids) {
      let t = WidgetData.readNumber(prefs, WidgetData.PREFIX_HISTORY_TIME + id, 0);
      if (t <= 0) {
        continue;
      }
      if (best === null || t > best.timestamp) {
        let info = new WidgetReadInfo();
        info.comicId = id;
        info.timestamp = t;
        info.title = WidgetData.readString(prefs, WidgetData.PREFIX_HISTORY_TITLE + id, '');
        info.order = WidgetData.readNumber(prefs, WidgetData.PREFIX_HISTORY_ORDER + id, 0);
        if (info.order <= 0) {
          info.order = WidgetData.readNumber(prefs, WidgetData.PREFIX_PROGRESS + id, 0);
        }
        if (info.order > 0) {
          info.page = WidgetData.readNumber(prefs, WidgetData.PREFIX_PAGE + id + '_' + info.order, 0);
        }
        info.cover = WidgetData.readString(prefs, WidgetData.PREFIX_HISTORY_COVER + id, '');
        best = info;
      }
    }
    if (best !== null && best.title.length === 0) {
      best.title = WidgetData.findTitleInComicsCache(prefs, best.comicId);
    }
    return best;
  }

  private static collectHistoryIds(prefs: preferences.Preferences): string[] {
    let ids: string[] = [];
    try {
      let raw = WidgetData.readString(prefs, WidgetData.KEY_HISTORY_IDS, '[]');
      let parsed = JSON.parse(raw) as string[];
      if (parsed && parsed.length > 0) {
        for (let id of parsed) {
          if (id.length > 0 && ids.indexOf(id) < 0) {
            ids.push(id);
          }
        }
      }
    } catch (err) {
      // 索引损坏：忽略，改用全量扫描
    }
    try {
      let all = prefs.getAllSync();
      let keys = Object.keys(all);
      for (let k of keys) {
        if (k.startsWith(WidgetData.PREFIX_HISTORY_TIME)) {
          let id = k.substring(WidgetData.PREFIX_HISTORY_TIME.length);
          if (id.length > 0 && ids.indexOf(id) < 0) {
            ids.push(id);
          }
        }
      }
    } catch (err) {
      // getAllSync 失败：只使用索引结果
    }
    return ids;
  }

  /**
   * 标题兜底：从本地漫画列表缓存里按 _id 找标题。纯本地读取，找不到返回空串。
   */
  private static findTitleInComicsCache(prefs: preferences.Preferences, comicId: string): string {
    if (comicId.length === 0) {
      return '';
    }
    try {
      let all = prefs.getAllSync();
      let keys = Object.keys(all);
      for (let k of keys) {
        if (!k.startsWith('comics_') || k === 'comics_cache_version') {
          continue;
        }
        let raw = WidgetData.readString(prefs, k, '');
        if (raw.length === 0) {
          continue;
        }
        let entry = JSON.parse(raw) as Record<string, string>;
        let docsRaw = entry['data'];
        if (docsRaw === undefined || docsRaw.length === 0) {
          continue;
        }
        let docs = JSON.parse(docsRaw) as BikaComicSummary[];
        if (!docs || docs.length === 0) {
          continue;
        }
        for (let d of docs) {
          if (d._id === comicId) {
            return d.title;
          }
        }
      }
    } catch (err) {
      return '';
    }
    return '';
  }

  // ═══════════════ 格式化 ═══════════════

  /** 进度文案：如「看到第 3 话 · 今天 20:31」；无数据返回空串 */
  static formatProgress(order: number, timestamp: number): string {
    try {
      let head = '';
      if (order > 0) {
        head = '看到第 ' + order + ' 话';
      }
      let tail = WidgetData.formatTime(timestamp);
      if (head.length > 0 && tail.length > 0) {
        return head + ' · ' + tail;
      }
      return head.length > 0 ? head : tail;
    } catch (err) {
      return '';
    }
  }

  /** 时间文案：今天 HH:mm / MM-DD HH:mm；无效时间返回空串 */
  static formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    try {
      let d = new Date(timestamp);
      let now = new Date();
      let pad = (n: number): string => n < 10 ? '0' + n : String(n);
      if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()) {
        return '今天 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
      }
      return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    } catch (err) {
      return '';
    }
  }

  /** 解析卡片列表 JSON（最多 MAX_ROWS 条），异常返回空数组 */
  static parseUpdates(json: string): WidgetUpdateItem[] {
    let list: WidgetUpdateItem[] = [];
    if (json.length === 0) {
      return list;
    }
    try {
      let parsed = JSON.parse(json) as WidgetUpdateItem[];
      if (parsed && parsed.length > 0) {
        for (let i = 0; i < parsed.length && list.length < WidgetData.MAX_ROWS; i++) {
          let it = parsed[i];
          let row = new WidgetUpdateItem();
          row.id = WidgetData.safeString(it.id);
          row.title = WidgetData.safeString(it.title);
          row.cover = WidgetData.safeString(it.cover);
          row.order = it.order > 0 ? it.order : 0;
          row.time = it.time > 0 ? it.time : 0;
          row.coverKey = WidgetData.safeString(it.coverKey);
          if (row.title.length === 0) {
            continue;
          }
          list.push(row);
        }
      }
    } catch (err) {
      list = [];
    }
    return list;
  }

  private static safeString(v: string | undefined | null): string {
    if (v === undefined || v === null) {
      return '';
    }
    return v;
  }

  // ═══════════════ 开关（主应用控制，默认开启） ═══════════════

  /** 是否允许卡片显示真实内容（默认开启） */
  static isRealDataEnabled(ctx?: Context): boolean {
    return WidgetData.readSettingBool(WidgetData.SETTING_REAL_DATA, true, ctx);
  }

  /** 是否允许下发封面（默认开启） */
  static isCoverEnabled(ctx?: Context): boolean {
    return WidgetData.readSettingBool(WidgetData.SETTING_SHOW_COVER, true, ctx);
  }

  static setRealDataEnabled(on: boolean, ctx?: Context): void {
    WidgetData.writeSettingBool(WidgetData.SETTING_REAL_DATA, on, ctx);
  }

  static setCoverEnabled(on: boolean, ctx?: Context): void {
    WidgetData.writeSettingBool(WidgetData.SETTING_SHOW_COVER, on, ctx);
  }

  private static readSettingBool(key: string, def: boolean, ctx?: Context): boolean {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null) {
        return def;
      }
      let raw = WidgetData.readString(prefs, WidgetData.PREFIX_SETTING + key, def ? 'true' : 'false');
      return raw === 'true';
    } catch (err) {
      return def;
    }
  }

  private static writeSettingBool(key: string, on: boolean, ctx?: Context): void {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null) {
        return;
      }
      prefs.putSync(WidgetData.PREFIX_SETTING + key, on ? 'true' : 'false');
      prefs.flushSync();
    } catch (err) {
      console.warn('[WidgetData] writeSettingBool failed: ' + JSON.stringify(err));
    }
  }

  // ═══════════════ 绑定数据（下发给卡片） ═══════════════

  /** 同步构建绑定数据（供 onAddForm 使用）：只读本地，不含封面 */
  static buildRecentFormSync(ctx?: Context): WidgetRecentFormData {
    let data = new WidgetRecentFormData();
    try {
      if (!WidgetData.isRealDataEnabled(ctx)) {
        data.continueTitle = '';
        data.continueSubtitle = '';
        data.continueComicId = '';
        data.continueCoverKey = '';
        data.recentJson = '[]';
        data.showCover = 'false';
        data.emptyText = '打开 Bika 开始阅读';
        return data;
      }
      data.showCover = WidgetData.isCoverEnabled(ctx) ? 'true' : 'false';
      let rows: WidgetUpdateItem[] = WidgetData.parseUpdates(WidgetData.getCachedRecentJson(ctx));
      let info = WidgetData.getRecentReadInfo(ctx);
      if (info !== null && info.title.length > 0) {
        data.continueTitle = info.title;
        data.continueSubtitle = WidgetData.formatProgress(info.order, info.timestamp);
        data.continueComicId = info.comicId;
      }
      // 本地历史缺标题 / id 时用最近更新缓存首项兜底，保证卡片有真实作品名且点击能进阅读器
      WidgetData.applyContinueFallback(data, rows);
      data.recentJson = WidgetData.toCardJson(rows);
      return data;
    } catch (err) {
      console.error('[WidgetData] buildRecentFormSync failed: ' + JSON.stringify(err));
      return data;
    }
  }

  /**
   * 异步刷新绑定数据（供 onUpdateForm / onAddForm 后二次刷新使用）：
   * 取数（5s 超时）→ 并发下载封面 → 组装。
   */
  static async refreshRecentForm(ctx?: Context): Promise<WidgetRecentFormData> {
    let data = new WidgetRecentFormData();
    try {
      if (!WidgetData.isRealDataEnabled(ctx)) {
        return WidgetData.buildRecentFormSync(ctx);
      }
      let showCover: boolean = WidgetData.isCoverEnabled(ctx);
      data.showCover = showCover ? 'true' : 'false';
      let items: WidgetUpdateItem[] = await WidgetData.getRecentUpdates(ctx);
      let info: WidgetReadInfo | null = await WidgetData.loadRecentReadInfo(ctx);
      if (info !== null && info.title.length > 0) {
        data.continueTitle = info.title;
        data.continueSubtitle = WidgetData.formatProgress(info.order, info.timestamp);
        data.continueComicId = info.comicId;
      }
      // 本地历史缺标题 / id 时，优先按 comicId 在最近更新列表里找标题，再用首项兜底
      WidgetData.applyContinueFallback(data, items);
      let continueCover: string = '';
      if (info !== null && info.cover.length > 0 && info.comicId === data.continueComicId) {
        continueCover = info.cover;
      }
      if (continueCover.length === 0) {
        for (let it of items) {
          if (it.id === data.continueComicId) {
            continueCover = it.cover;
            break;
          }
        }
      }
      // 组装封面请求：继续阅读 + 列表行
      let requests: WidgetCoverRequest[] = [];
      if (showCover) {
        if (continueCover.length > 0) {
          let req = new WidgetCoverRequest();
          req.bizKey = 'continue';
          req.url = continueCover;
          requests.push(req);
        }
        for (let i = 0; i < items.length; i++) {
          if (items[i].cover.length === 0) {
            continue;
          }
          let req = new WidgetCoverRequest();
          req.bizKey = 'row' + i;
          req.url = items[i].cover;
          requests.push(req);
        }
      }
      let bundle: WidgetCoverBundle = await WidgetCover.prepare(requests, ctx);
      if (bundle.coverKeyOf('continue').length > 0) {
        data.continueCoverKey = bundle.coverKeyOf('continue');
      }
      for (let i = 0; i < items.length; i++) {
        items[i].coverKey = bundle.coverKeyOf('row' + i);
      }
      data.recentJson = WidgetData.toCardJson(items);
      WidgetCover.attach(data, bundle);
      return data;
    } catch (err) {
      console.error('[WidgetData] refreshRecentForm failed: ' + JSON.stringify(err));
      return WidgetData.buildRecentFormSync(ctx);
    }
  }

  /**
   * 「继续阅读」兜底：本地历史没有标题 / 作品 id 时，用最近更新列表补齐，
   * 保证卡片上一定有真实作品名，且点击能带着 comicId 进阅读器。
   */
  private static applyContinueFallback(data: WidgetRecentFormData, items: WidgetUpdateItem[]): void {
    if (data.continueTitle.length > 0) {
      return;
    }
    if (data.continueComicId.length > 0) {
      for (let it of items) {
        if (it.id === data.continueComicId && it.title.length > 0) {
          data.continueTitle = it.title;
          break;
        }
      }
    }
    if (data.continueTitle.length === 0 && items.length > 0) {
      data.continueTitle = items[0].title;
      data.continueComicId = items[0].id;
    }
    if (data.continueTitle.length > 0 && data.continueSubtitle.length === 0) {
      data.continueSubtitle = '继续上次阅读';
    }
  }

  /** 列表项 → 下发 JSON（只含 id / title / coverKey / order / time） */
  private static toCardJson(items: WidgetUpdateItem[]): string {
    let rows: WidgetCardRow[] = [];
    for (let it of items) {
      let row: WidgetCardRow = {
        id: it.id,
        title: it.title,
        coverKey: it.coverKey,
        order: it.order,
        time: it.time
      };
      rows.push(row);
    }
    return JSON.stringify(rows);
  }

  /**
   * 主应用侧预热：登录后在应用进程里把「最近更新」列表刷进本地缓存。
   * 目的是让卡片同步路径（onAddForm）一挂上就有真实作品名，
   * 不依赖卡片进程那 10s 的生命周期预算。异常全部吞掉。
   */
  static async bootstrapCache(ctx?: Context): Promise<void> {
    try {
      if (!WidgetData.isRealDataEnabled(ctx)) {
        return;
      }
      await WidgetData.getRecentUpdates(ctx);
    } catch (err) {
      console.info('[WidgetData] bootstrapCache skipped: ' + JSON.stringify(err));
    }
  }

  // ═══════════════ 轻量网络取数 ═══════════════

  /**
   * 首页「最近更新」列表（GET comics?page=1&s=dd）。
   * - 未登录不发请求；5s 超时；失败降级为本地历史；再失败返回空数组，绝不抛异常。
   */
  static async getRecentUpdates(ctx?: Context): Promise<WidgetUpdateItem[]> {
    try {
      let net = await WidgetData.fetchRecentFromNetwork(ctx);
      if (net.length > 0) {
        WidgetData.cacheRecentUpdates(net, ctx);
        return net;
      }
    } catch (err) {
      console.info('[WidgetData] network unavailable, fallback to local history: ' + JSON.stringify(err));
    }
    return WidgetData.getLocalHistoryUpdates(ctx);
  }

  private static async fetchRecentFromNetwork(ctx?: Context): Promise<WidgetUpdateItem[]> {
    let prefs = WidgetData.openPrefsSync(ctx);
    if (prefs !== null) {
      let token = WidgetData.readString(prefs, WidgetData.KEY_TOKEN, '');
      if (token.length === 0) {
        // 未登录：不发请求，直接降级
        return [];
      }
      // 卡片进程里 ApiService 自己是拿不到令牌的（构造函数依赖 getContext()），
      // 这里显式注入，否则请求必然失败、卡片永远只有本地缓存。
      ApiService.getInstance().injectToken(token);
    }
    let task: Promise<WidgetUpdateItem[]> = WidgetData.requestRecentComics();
    return WidgetData.withTimeout(task, WidgetData.NET_TIMEOUT_MS);
  }

  private static async requestRecentComics(): Promise<WidgetUpdateItem[]> {
    let list: WidgetUpdateItem[] = [];
    let api = ApiService.getInstance();
    let res = await api.getComics('', 'dd', 1);
    if (!res || !res.comics) {
      return list;
    }
    let comics: BikaComicSummary[] = res.comics;
    // 环节 1：确认接口返回条数与封面原始字段
    let firstThumb: string = '';
    if (comics.length > 0 && comics[0] && comics[0].thumb) {
      firstThumb = comics[0].thumb.path;
    }
    console.info('[WidgetData] api items=' + comics.length + ' thumb.path=' + firstThumb);
    for (let i = 0; i < comics.length && list.length < WidgetData.MAX_ROWS; i++) {
      let c: BikaComicSummary = comics[i];
      if (!c || !c.title || c.title.length === 0) {
        continue;
      }
      let item = new WidgetUpdateItem();
      item.id = c._id;
      item.title = c.title;
      item.cover = buildImageUrl(c.thumb);
      item.order = 0;
      item.time = 0;
      list.push(item);
    }
    return list;
  }

  private static withTimeout(task: Promise<WidgetUpdateItem[]>, ms: number): Promise<WidgetUpdateItem[]> {
    return new Promise<WidgetUpdateItem[]>((resolve: (v: WidgetUpdateItem[]) => void,
      reject: (e: Error) => void) => {
      let settled = false;
      let timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('widget data timeout'));
        }
      }, ms);
      task.then((value: WidgetUpdateItem[]) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(value);
        }
      }).catch((err: Error) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(err);
        }
      });
    });
  }

  /**
   * 本地降级：用最近一条历史 + 本地缓存列表。
   * 最近历史优先，保证「继续阅读」永远是真实的本地数据。
   */
  private static async getLocalHistoryUpdates(ctx?: Context): Promise<WidgetUpdateItem[]> {
    let list: WidgetUpdateItem[] = [];
    try {
      let info = await WidgetData.loadRecentReadInfo(ctx);
      if (info !== null && info.title.length > 0) {
        let item = new WidgetUpdateItem();
        item.id = info.comicId;
        item.title = info.title;
        item.cover = info.cover;
        item.order = info.order;
        item.time = info.timestamp;
        list.push(item);
      }
    } catch (err) {
      // 本地历史读取失败：降级为空列表
    }
    // 本地缓存里的其它条目补足（最近更新）
    let cached = WidgetData.parseUpdates(WidgetData.getCachedRecentJson(ctx));
    for (let c of cached) {
      if (list.length >= WidgetData.MAX_ROWS) {
        break;
      }
      let dup = false;
      for (let e of list) {
        if (e.id === c.id) {
          dup = true;
          break;
        }
      }
      if (!dup) {
        list.push(c);
      }
    }
    return list;
  }

  // ═══════════════ 列表缓存 ═══════════════

  /**
   * 缓存最近更新列表（网络刷新后由本类自动调用）。
   * 注意：缓存里必须保留 http 封面地址 —— 卡片侧只认 coverKey（memory://），
   * 但下一次刷新要重新下载封面时只能靠这里存的 http 地址，
   * 否则一旦写入缓存就再也拿不到封面（只有作品名没有图）。
   */
  static cacheRecentUpdates(items: WidgetUpdateItem[], ctx?: Context): void {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null) {
        return;
      }
      prefs.putSync(WidgetData.PREFIX_SETTING + WidgetData.SETTING_RECENT_JSON,
        WidgetData.toCacheJson(items));
      prefs.flushSync();
    } catch (err) {
      console.warn('[WidgetData] cacheRecentUpdates failed: ' + JSON.stringify(err));
    }
  }

  /** 列表项 → 本地缓存 JSON（含 http 封面地址，仅供本类内部使用） */
  private static toCacheJson(items: WidgetUpdateItem[]): string {
    let out: WidgetUpdateItem[] = [];
    for (let it of items) {
      let row = new WidgetUpdateItem();
      row.id = it.id;
      row.title = it.title;
      row.cover = it.cover;
      row.order = it.order;
      row.time = it.time;
      row.coverKey = it.coverKey;
      out.push(row);
    }
    return JSON.stringify(out);
  }

  /** 读取缓存的最近更新列表 JSON（默认 '[]'） */
  static getCachedRecentJson(ctx?: Context): string {
    try {
      let prefs = WidgetData.openPrefsSync(ctx);
      if (prefs === null) {
        return '[]';
      }
      return WidgetData.readString(prefs, WidgetData.PREFIX_SETTING + WidgetData.SETTING_RECENT_JSON, '[]');
    } catch (err) {
      return '[]';
    }
  }
}
