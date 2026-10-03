import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { ApiService } from '../network/ApiService';
import { BikaComicSummary, buildImageUrl } from '../models/Comic';
import { WidgetCover, WidgetCoverBundle, WidgetCoverFormData, WidgetCoverRequest } from './WidgetCover';
import { WidgetData } from './WidgetData';

/**
 * Bika 桌面卡片扩展数据层：排行榜 / 我的收藏 / 为你推荐
 *
 * 定位：与 common/WidgetData.ets 平行的「新卡片」数据层，
 * 由 FormExtensionAbility（EntryFormAbility）按卡片名分派调用。
 *
 * 真实数据来源（不写死任何示例数据）：
 * - 排行榜：ApiService.getLeaderboard('D7')      → GET comics/leaderboard?tt=D7&ct=VC
 * - 我的收藏：ApiService.getFavourites('dd', 1)  → GET users/favourite?page=1&s=dd（需登录）
 * - 为你推荐：ApiService.getCollections()        → GET collections（推荐分区）
 *              为空时回退 ApiService.getRandomComics() → GET comics/random
 *
 * 统一约束：
 * - 所有网络请求 5 秒超时，超时立即返回安全默认值；
 * - 未登录（preferences 里没有 auth_token）不发任何网络请求，直接读本地缓存；
 * - 所有异常都被吞掉并返回安全默认值（空列表 / 上次缓存），绝不向上抛异常；
 * - 网络失败时回退到本类写入的本地缓存（setting_widget_extra_*_json）；
 * - 封面走 common/WidgetCover.ets：下载到沙箱 → fd → formImages，
 *   卡片侧用 Image('memory://' + coverKey) 渲染；
 * - 是否显示真实内容 / 封面统一由 WidgetData 的两个开关决定
 *   （widget_show_real_data / widget_show_cover），与 2*2、4*4 卡片完全一致。
 */

/** 卡片列表项（数据层内部使用） */
export class WidgetExtraItem {
  id: string = '';
  title: string = '';
  /** 原始 http(s) 封面地址；只在数据层内部使用，不下发给卡片 */
  cover: string = '';
  /** 榜单名次（1 起）；非榜单卡片恒为 0 */
  rank: number = 0;
  /** formImages 的 key；空串表示本次没有成功下发的封面 */
  coverKey: string = '';
}

/** 下发给卡片的列表项：只保留卡片需要的字段（不含 http 封面地址） */
interface WidgetExtraCardRow {
  id: string;
  title: string;
  coverKey: string;
  rank: number;
}

/** 排行榜卡片绑定数据（2*4） */
export class WidgetRankFormData extends WidgetCoverFormData {
  rankTitle: string = '排行榜';
  rankJson: string = '[]';
  extraShowCover: string = 'true';
}

/** 收藏夹卡片绑定数据（2*4） */
export class WidgetFavoritesFormData extends WidgetCoverFormData {
  favTitle: string = '我的收藏';
  favJson: string = '[]';
  extraShowCover: string = 'true';
}

/** 推荐卡片绑定数据（4*4） */
export class WidgetRecommendFormData extends WidgetCoverFormData {
  recTitle: string = '为你推荐';
  recJson: string = '[]';
  extraShowCover: string = 'true';
}

export class WidgetExtraData {
  private static readonly PREF_NAME: string = 'BikaCache';
  private static readonly KEY_TOKEN: string = 'auth_token';
  private static readonly PREFIX_SETTING: string = 'setting_';

  /** 本地列表缓存 key（写入 setting_ 前缀下） */
  private static readonly CACHE_RANK: string = 'widget_extra_rank_json';
  private static readonly CACHE_FAV: string = 'widget_extra_fav_json';
  private static readonly CACHE_REC: string = 'widget_extra_rec_json';

  /** 所有网络请求超时（毫秒）：FormExtensionAbility 生命周期只有 10s */
  private static readonly NET_TIMEOUT_MS: number = 3500;
  /** 每张卡片最多下发的条目数 */
  private static readonly MAX_ITEMS: number = 4;
  /** 排行榜时间窗：H24 / D7 / D30 */
  private static readonly LEADERBOARD_TT: string = 'D7';
  /** 收藏排序：dd 最新 */
  private static readonly FAVORITES_SORT: string = 'dd';

  private static syncPrefs: preferences.Preferences | null = null;

  // ═══════════════ 初始化与本地读取 ═══════════════

  /** FormExtensionAbility 启动时调用一次：缓存 preferences 句柄，之后可全同步读取 */
  static init(ctx: Context): void {
    try {
      let options: preferences.Options = { name: WidgetExtraData.PREF_NAME };
      WidgetExtraData.syncPrefs = preferences.getPreferencesSync(ctx, options);
    } catch (err) {
      console.warn('[WidgetExtraData] init failed: ' + JSON.stringify(err));
    }
  }

  private static openPrefsSync(ctx?: Context): preferences.Preferences | null {
    if (WidgetExtraData.syncPrefs !== null) {
      return WidgetExtraData.syncPrefs;
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
      let options: preferences.Options = { name: WidgetExtraData.PREF_NAME };
      WidgetExtraData.syncPrefs = preferences.getPreferencesSync(context, options);
      return WidgetExtraData.syncPrefs;
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

  /** 登录令牌（空串 = 未登录，任何网络请求都不发） */
  private static readToken(ctx?: Context): string {
    try {
      let prefs = WidgetExtraData.openPrefsSync(ctx);
      if (prefs === null) {
        return '';
      }
      return WidgetExtraData.readString(prefs, WidgetExtraData.KEY_TOKEN, '');
    } catch (err) {
      return '';
    }
  }

  /** 是否允许卡片显示真实内容（与 2*2 / 4*4 卡片共用同一开关，默认开启） */
  static isRealDataEnabled(ctx?: Context): boolean {
    return WidgetData.isRealDataEnabled(ctx);
  }

  /** 是否允许下发封面（与 2*2 / 4*4 卡片共用同一开关，默认开启） */
  static isCoverEnabled(ctx?: Context): boolean {
    return WidgetData.isCoverEnabled(ctx);
  }

  // ═══════════════ 取数：排行榜 / 收藏 / 推荐 ═══════════════

  /**
   * 排行榜 Top N（名次 + 标题 + 封面）。
   * 未登录 / 超时 / 异常 → 本地缓存；再无 → 空数组。
   */
  static async loadRankItems(ctx?: Context): Promise<WidgetExtraItem[]> {
    return WidgetExtraData.loadItems(WidgetExtraData.CACHE_RANK,
      (): Promise<WidgetExtraItem[]> => WidgetExtraData.fetchLeaderboard(), ctx);
  }

  /**
   * 我的收藏 Top N。
   * 需要登录：未登录不发请求，直接返回本地缓存快照。
   * 说明：工程内收藏只有网络来源（GET users/favourite），没有独立的本地收藏表；
   * 本类在每次成功取数后写一份本地快照（setting_widget_extra_fav_json）作为离线降级。
   */
  static async loadFavoriteItems(ctx?: Context): Promise<WidgetExtraItem[]> {
    return WidgetExtraData.loadItems(WidgetExtraData.CACHE_FAV,
      (): Promise<WidgetExtraItem[]> => WidgetExtraData.fetchFavorites(), ctx);
  }

  /** 推荐 Top N（公开推荐分区，仍按统一约束：未登录不发请求） */
  static async loadRecommendItems(ctx?: Context): Promise<WidgetExtraItem[]> {
    return WidgetExtraData.loadItems(WidgetExtraData.CACHE_REC,
      (): Promise<WidgetExtraItem[]> => WidgetExtraData.fetchRecommend(), ctx);
  }

  private static async loadItems(cacheKey: string, fetcher: () => Promise<WidgetExtraItem[]>,
    ctx?: Context): Promise<WidgetExtraItem[]> {
    try {
      if (!WidgetExtraData.isRealDataEnabled(ctx)) {
        return [];
      }
      let token: string = WidgetExtraData.readToken(ctx);
      if (token.length === 0) {
        // 未登录：不发请求
        return WidgetExtraData.readCachedItems(cacheKey, ctx);
      }
      // 卡片进程里 ApiService 构造函数拿不到令牌，这里显式注入
      ApiService.getInstance().injectToken(token);
      let list = await WidgetExtraData.withTimeout(fetcher(), WidgetExtraData.NET_TIMEOUT_MS);
      if (list.length > 0) {
        WidgetExtraData.cacheItems(cacheKey, list, ctx);
        return list;
      }
      return WidgetExtraData.readCachedItems(cacheKey, ctx);
    } catch (err) {
      console.info('[WidgetExtraData] network fallback to cache: ' + JSON.stringify(err));
      return WidgetExtraData.readCachedItems(cacheKey, ctx);
    }
  }

  private static async fetchLeaderboard(): Promise<WidgetExtraItem[]> {
    let api = ApiService.getInstance();
    let comics = await api.getLeaderboard(WidgetExtraData.LEADERBOARD_TT);
    return WidgetExtraData.toItems(comics, true);
  }

  private static async fetchFavorites(): Promise<WidgetExtraItem[]> {
    let api = ApiService.getInstance();
    let res = await api.getFavourites(WidgetExtraData.FAVORITES_SORT, 1);
    return WidgetExtraData.toItems(res.comics, false);
  }

  private static async fetchRecommend(): Promise<WidgetExtraItem[]> {
    let api = ApiService.getInstance();
    try {
      let collections = await api.getCollections();
      if (collections && collections.length > 0) {
        return WidgetExtraData.toItems(collections, false);
      }
    } catch (err) {
      console.info('[WidgetExtraData] collections failed, try random: ' + JSON.stringify(err));
    }
    let randoms = await api.getRandomComics();
    return WidgetExtraData.toItems(randoms, false);
  }

  /** 接口返回值 → 卡片列表项（跳过无标题项，最多 MAX_ITEMS 条） */
  private static toItems(comics: BikaComicSummary[], withRank: boolean): WidgetExtraItem[] {
    let list: WidgetExtraItem[] = [];
    if (!comics) {
      console.info('[WidgetExtraData] api returned null list');
      return list;
    }
    // 环节 1：确认接口确实返回了条目、且封面对应的原始字段取到了值
    let firstThumb: string = '';
    if (comics.length > 0 && comics[0] && comics[0].thumb) {
      firstThumb = comics[0].thumb.path;
    }
    console.info('[WidgetExtraData] api items=' + comics.length + ' thumb.path=' + firstThumb);
    for (let i = 0; i < comics.length && list.length < WidgetExtraData.MAX_ITEMS; i++) {
      let c: BikaComicSummary = comics[i];
      if (!c || !c.title || c.title.length === 0) {
        continue;
      }
      let item = new WidgetExtraItem();
      item.id = c._id ? c._id : '';
      item.title = c.title;
      item.cover = buildImageUrl(c.thumb);
      // 名次用原始榜单下标（跳过无标题项也保持真实排名）
      item.rank = withRank ? (i + 1) : 0;
      item.coverKey = '';
      list.push(item);
    }
    return list;
  }

  // ═══════════════ 绑定数据：同步（onAddForm） ═══════════════

  /** 同步组装排行榜绑定数据：只读上次缓存，不含封面（onAddForm 用） */
  static buildRankFormSync(ctx?: Context): WidgetRankFormData {
    let data = new WidgetRankFormData();
    try {
      if (!WidgetExtraData.isRealDataEnabled(ctx)) {
        return data;
      }
      data.extraShowCover = WidgetExtraData.isCoverEnabled(ctx) ? 'true' : 'false';
      data.rankJson = WidgetExtraData.toCardJson(WidgetExtraData.readCachedItems(WidgetExtraData.CACHE_RANK, ctx));
    } catch (err) {
      data.rankJson = '[]';
    }
    return data;
  }

  /** 同步组装收藏绑定数据 */
  static buildFavoritesFormSync(ctx?: Context): WidgetFavoritesFormData {
    let data = new WidgetFavoritesFormData();
    try {
      if (!WidgetExtraData.isRealDataEnabled(ctx)) {
        return data;
      }
      data.extraShowCover = WidgetExtraData.isCoverEnabled(ctx) ? 'true' : 'false';
      data.favJson = WidgetExtraData.toCardJson(WidgetExtraData.readCachedItems(WidgetExtraData.CACHE_FAV, ctx));
    } catch (err) {
      data.favJson = '[]';
    }
    return data;
  }

  /** 同步组装推荐绑定数据 */
  static buildRecommendFormSync(ctx?: Context): WidgetRecommendFormData {
    let data = new WidgetRecommendFormData();
    try {
      if (!WidgetExtraData.isRealDataEnabled(ctx)) {
        return data;
      }
      data.extraShowCover = WidgetExtraData.isCoverEnabled(ctx) ? 'true' : 'false';
      data.recJson = WidgetExtraData.toCardJson(WidgetExtraData.readCachedItems(WidgetExtraData.CACHE_REC, ctx));
    } catch (err) {
      data.recJson = '[]';
    }
    return data;
  }

  // ═══════════════ 绑定数据：异步（onUpdateForm / onAddForm 后二次刷新） ═══════════════

  /** 取真实排行榜 + 并发下载封面，返回可直接交给 formBindingData 的绑定数据 */
  static async refreshRankForm(ctx?: Context): Promise<WidgetRankFormData> {
    let data = new WidgetRankFormData();
    try {
      let items = await WidgetExtraData.loadRankItems(ctx);
      let bundle = await WidgetExtraData.prepareCovers(items, ctx);
      data.rankJson = WidgetExtraData.toCardJson(items);
      data.extraShowCover = WidgetExtraData.isCoverEnabled(ctx) ? 'true' : 'false';
      WidgetCover.attach(data, bundle);
    } catch (err) {
      console.warn('[WidgetExtraData] refreshRankForm failed: ' + JSON.stringify(err));
      data.rankJson = '[]';
    }
    return data;
  }

  static async refreshFavoritesForm(ctx?: Context): Promise<WidgetFavoritesFormData> {
    let data = new WidgetFavoritesFormData();
    try {
      let items = await WidgetExtraData.loadFavoriteItems(ctx);
      let bundle = await WidgetExtraData.prepareCovers(items, ctx);
      data.favJson = WidgetExtraData.toCardJson(items);
      data.extraShowCover = WidgetExtraData.isCoverEnabled(ctx) ? 'true' : 'false';
      WidgetCover.attach(data, bundle);
    } catch (err) {
      console.warn('[WidgetExtraData] refreshFavoritesForm failed: ' + JSON.stringify(err));
      data.favJson = '[]';
    }
    return data;
  }

  static async refreshRecommendForm(ctx?: Context): Promise<WidgetRecommendFormData> {
    let data = new WidgetRecommendFormData();
    try {
      let items = await WidgetExtraData.loadRecommendItems(ctx);
      let bundle = await WidgetExtraData.prepareCovers(items, ctx);
      data.recJson = WidgetExtraData.toCardJson(items);
      data.extraShowCover = WidgetExtraData.isCoverEnabled(ctx) ? 'true' : 'false';
      WidgetCover.attach(data, bundle);
    } catch (err) {
      console.warn('[WidgetExtraData] refreshRecommendForm failed: ' + JSON.stringify(err));
      data.recJson = '[]';
    }
    return data;
  }

  /**
   * 主应用侧预热：把排行榜 / 收藏 / 推荐三份列表刷进本地缓存，
   * 让卡片同步路径一挂上就有真实内容（卡片进程只有 10s 生命周期）。异常全部吞掉。
   */
  static async bootstrapCache(ctx?: Context): Promise<void> {
    try {
      if (!WidgetExtraData.isRealDataEnabled(ctx)) {
        return;
      }
      await WidgetExtraData.loadRankItems(ctx);
      await WidgetExtraData.loadFavoriteItems(ctx);
      await WidgetExtraData.loadRecommendItems(ctx);
    } catch (err) {
      console.info('[WidgetExtraData] bootstrapCache skipped: ' + JSON.stringify(err));
    }
  }

  // ═══════════════ 封面：交给 common/WidgetCover.ets 统一处理 ═══════════════

  /** 把列表项的 http 封面交给 WidgetCover 并发下载，并把 coverKey 写回列表项 */
  private static async prepareCovers(items: WidgetExtraItem[], ctx?: Context): Promise<WidgetCoverBundle> {
    for (let it of items) {
      it.coverKey = '';
    }
    if (!WidgetExtraData.isCoverEnabled(ctx) || ctx === undefined || ctx === null) {
      return new WidgetCoverBundle();
    }
    let requests: WidgetCoverRequest[] = [];
    for (let i = 0; i < items.length; i++) {
      if (items[i].cover.length === 0) {
        continue;
      }
      let req = new WidgetCoverRequest();
      req.bizKey = 'i' + i;
      req.url = items[i].cover;
      requests.push(req);
    }
    let bundle: WidgetCoverBundle = await WidgetCover.prepare(requests, ctx);
    for (let i = 0; i < items.length; i++) {
      items[i].coverKey = bundle.coverKeyOf('i' + i);
    }
    return bundle;
  }

  // ═══════════════ 列表缓存 ═══════════════

  private static cacheItems(key: string, items: WidgetExtraItem[], ctx?: Context): void {
    try {
      let prefs = WidgetExtraData.openPrefsSync(ctx);
      if (prefs === null) {
        return;
      }
      prefs.putSync(WidgetExtraData.PREFIX_SETTING + key, JSON.stringify(items));
      prefs.flushSync();
    } catch (err) {
      console.warn('[WidgetExtraData] cacheItems failed: ' + JSON.stringify(err));
    }
  }

  private static readCachedItems(key: string, ctx?: Context): WidgetExtraItem[] {
    try {
      let prefs = WidgetExtraData.openPrefsSync(ctx);
      if (prefs === null) {
        return [];
      }
      let raw = WidgetExtraData.readString(prefs, WidgetExtraData.PREFIX_SETTING + key, '[]');
      return WidgetExtraData.parseItems(raw);
    } catch (err) {
      return [];
    }
  }

  private static parseItems(json: string): WidgetExtraItem[] {
    let list: WidgetExtraItem[] = [];
    if (json.length === 0) {
      return list;
    }
    try {
      let parsed = JSON.parse(json) as WidgetExtraItem[];
      if (parsed && parsed.length > 0) {
        for (let i = 0; i < parsed.length && list.length < WidgetExtraData.MAX_ITEMS; i++) {
          let it = parsed[i];
          if (!it || !it.title || it.title.length === 0) {
            continue;
          }
          let item = new WidgetExtraItem();
          item.id = it.id ? it.id : '';
          item.title = it.title;
          item.cover = it.cover ? it.cover : '';
          item.rank = it.rank > 0 ? it.rank : 0;
          item.coverKey = '';
          list.push(item);
        }
      }
    } catch (err) {
      list = [];
    }
    return list;
  }

  /** 组装下发给卡片的 JSON：只含 id / title / coverKey / rank */
  private static toCardJson(items: WidgetExtraItem[]): string {
    let rows: WidgetExtraCardRow[] = [];
    for (let it of items) {
      let row: WidgetExtraCardRow = {
        id: it.id,
        title: it.title,
        coverKey: it.coverKey,
        rank: it.rank
      };
      rows.push(row);
    }
    return JSON.stringify(rows);
  }

  // ═══════════════ 超时包装 ═══════════════

  private static withTimeout<T>(task: Promise<T>, ms: number): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (e: Error) => void) => {
      let settled = false;
      let timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('widget extra data timeout'));
        }
      }, ms);
      task.then((value: T) => {
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
}
