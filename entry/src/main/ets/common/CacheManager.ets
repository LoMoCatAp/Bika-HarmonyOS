import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { AuthCredentials, CredentialStore } from './CredentialStore';

export interface ChapterUpdateChapter {
  id: string;
  order: number;
}

interface ChapterUpdateState {
  epsCount: number;
  /** 尚未拿到完整章节列表的新增段，按列表位置记录；-1 表示已解析。 */
  pendingFromCount: number;
  /** 已解析的未读更新，按章节 ID 保存，避免把话数当成列表下标。 */
  chapters: ChapterUpdateChapter[];
  /** 完整章节快照用于识别补发/插入章节；缺省兼容只有章节数的旧记录。 */
  knownChapterIds?: string[];
}

interface FollowChapterSnapshot {
  comicId: string;
  epsCount: number;
}

interface FollowChapterState {
  snapshots: FollowChapterSnapshot[];
}

/**
 * 本地缓存管理器
 * 普通缓存使用 Preferences，登录凭据使用 Asset Store Kit。
 *
 * 缓存策略：
 * - 凭据：安全资产中的 Token、邮箱、密码（自动登录用）；兼容旧版无损迁移
 * - 分类列表：带 TTL 缓存
 * - 首页漫画：按 分类+排序 分 key 缓存，带 TTL
 * - 章节图片列表：长期缓存
 * - 用户偏好：分类、排序选择、阅读进度
 */
export class CacheManager {
  private static PREF_NAME = 'BikaCache';
  private static TTL_CATEGORY = 60 * 60 * 1000; // 分类列表 1 小时
  private static TTL_COMICS = 30 * 60 * 1000; // 漫画列表 30 分钟

  private static instance: CacheManager | null = null;
  private prefs: preferences.Preferences | null = null;
  private lastAuthSnapshot: AuthCredentials | null = null;

  private constructor() {
  }

  static async getInstance(ctx?: Context): Promise<CacheManager> {
    if (CacheManager.instance === null) {
      CacheManager.instance = new CacheManager();
    }
    if (CacheManager.instance.prefs === null) {
      // getContext() 全局函数仅在 UI 组件上下文可用；
      // 非 UI 场景（如 EntryAbility）必须显式传入 AbilityContext
      let context: Context = ctx ?? getContext();
      CacheManager.instance.prefs = await preferences.getPreferences(context, CacheManager.PREF_NAME);
    }
    return CacheManager.instance;
  }

  /**
   * 同步初始化：用 preferences.getPreferencesSync 打开偏好库并持有句柄。
   *
   * 必须在「页面首帧之前」调用一次（EntryAbility.onCreate）。
   * 之后 getToken()/getSetting() 等全部 getSync/putSync 路径在任何时刻（含首帧）都可用，
   * 冷启动登录态不再依赖异步 getInstance() 的回调时序。
   *
   * 幂等：实例已存在 / 句柄已打开时直接复用，不重复打开，也不影响异步 getInstance()。
   * @returns 同步可用的 CacheManager（句柄可能仍为 null，用 isReady() 判断）
   */
  static initSync(ctx: Context): CacheManager {
    if (CacheManager.instance === null) {
      CacheManager.instance = new CacheManager();
    }
    if (CacheManager.instance.prefs === null) {
      try {
        let options: preferences.Options = { name: CacheManager.PREF_NAME };
        CacheManager.instance.prefs = preferences.getPreferencesSync(ctx, options);
      } catch (err) {
        console.error('[CacheManager] initSync failed: ' + JSON.stringify(err));
      }
    }
    return CacheManager.instance;
  }

  /**
   * 只取「同步已就绪」的单例：句柄未打开时返回 null，绝不触发异步打开，
   * 也绝不调用全局 getContext()。
   *
   * 卡片进程（FormExtensionAbility）没有 UI 上下文，无参 getInstance() 里的
   * getContext() 会抛异常；调用方据此走「无凭据」路径，而不是打印错误日志。
   */
  static getInstanceIfReady(): CacheManager | null {
    let inst: CacheManager | null = CacheManager.instance;
    if (inst !== null && inst.prefs !== null) {
      return inst;
    }
    return null;
  }

  /** 同步句柄是否已就绪（getSync/putSync 可用） */
  isReady(): boolean {
    return this.prefs !== null;
  }

  // ─── 通用方法 ───

  private put(key: string, value: string): void {
    this.prefs?.putSync(key, value);
    this.prefs?.flushSync();
  }

  private getString(key: string, defVal: string = ''): string {
    return this.prefs?.getSync(key, defVal) as string || defVal;
  }

  private putObject<T>(key: string, obj: T): void {
    this.put(key, JSON.stringify(obj));
  }

  private getObject<T>(key: string, defVal: T | null = null): T | null {
    let raw = this.getString(key, '');
    if (!raw) return defVal;
    try {
      return JSON.parse(raw) as T;
    } catch {
      return defVal;
    }
  }

  // ─── 登录凭据 ───

  getAuthCredentials(): AuthCredentials {
    if (this.prefs === null) {
      throw new Error('登录存储尚未就绪，请稍后重试');
    }
    try {
      const saved = CredentialStore.read(this.prefs);
      this.lastAuthSnapshot = saved;
      return saved;
    } catch (err) {
      // 已成功恢复的会话在临时服务故障期间继续使用内存快照；冷启动无快照时保持未确定。
      if (this.lastAuthSnapshot !== null) {
        return this.lastAuthSnapshot;
      }
      throw err as Error;
    }
  }

  /** 只迁移凭据，不更改阅读、下载、搜索或用户设置等其它数据。 */
  migrateAuthStorage(): boolean {
    return this.prefs !== null && CredentialStore.migrateLegacy(this.prefs);
  }

  isAuthReady(): boolean {
    try {
      this.getAuthCredentials();
      return true;
    } catch (_err) {
      return false;
    }
  }

  /** 完整登录快照一次提交，防止账号、密码和 Token 出现半写入状态。 */
  saveAuth(email: string, password: string, token: string): void {
    if (this.prefs === null) {
      throw new Error('登录存储尚未就绪，请稍后重试');
    }
    const saved: AuthCredentials = { email: email, password: password, token: token, tokenInvalid: false };
    CredentialStore.save(this.prefs, saved);
    this.lastAuthSnapshot = saved;
  }

  saveToken(token: string): void {
    const previous = this.getAuthCredentials();
    this.saveAuth(previous.email, previous.password, token);
  }

  getToken(): string {
    return this.getAuthCredentials().token;
  }

  saveCredentials(email: string, password: string): void {
    this.saveAuth(email, password, this.getAuthCredentials().token);
  }

  getEmail(): string {
    return this.getAuthCredentials().email;
  }

  getPassword(): string {
    return this.getAuthCredentials().password;
  }

  clearAuth(): void {
    if (this.prefs === null) {
      throw new Error('登录存储尚未就绪，请稍后重试');
    }
    CredentialStore.clear(this.prefs);
    this.lastAuthSnapshot = { email: '', password: '', token: '', tokenInvalid: false };
    this.prefs?.deleteSync('auth_token_invalid');
    this.prefs?.flushSync();
  }

  /**
   * 令牌是否已被服务端判定失效（HTTP 401 或业务码 1005，且无法自动重登）。
   * 落盘持久化，供下次冷启动「同步读取 + 本地有效性判定」使用，
   * 避免已知失效的令牌被当成已登录、先渲染已登录再闪回未登录。
   */
  isTokenInvalid(): boolean {
    return this.getAuthCredentials().tokenInvalid;
  }

  /**
   * 标记当前令牌失效：只删令牌（保留邮箱/密码供重新登录回填），并落盘失效标记。
   * 与 clearAuth()（用户主动彻底退出登录）区分开。
   */
  markTokenInvalid(): void {
    const previous = this.getAuthCredentials();
    if (this.prefs !== null) {
      const saved: AuthCredentials = { email: previous.email, password: previous.password, token: '', tokenInvalid: true };
      CredentialStore.save(this.prefs, saved);
      this.lastAuthSnapshot = saved;
    }
  }

  /**
   * 退出登录：清空卡片（桌面小组件）在离线降级时会读到的本账号数据快照。
   *
   * 卡片取数失败会回落到下列本地键；若不清空，退出登录后桌面仍显示上一账号
   * 的作品名 / 阅读进度 / 封面 / 收藏（隐私泄漏）。
   *
   * 只删与账号阅读数据有关的键；setting_ 前缀下与卡片无关的用户设置
   * （颜色模式、材质、DNS、代理、动画、卡片两个显示开关、预热节流时间戳等）
   * 以及 widget_form_name_<formId> 这类设备级映射一律保留。
   */
  clearWidgetUserData(): void {
    if (this.prefs === null) {
      return;
    }
    try {
      let all = this.prefs.getAllSync();
      let keys = Object.keys(all);
      for (let k of keys) {
        let hit = k === 'history_ids'
          || k.startsWith('history_title_')
          || k.startsWith('history_order_')
          || k.startsWith('history_time_')
          || k.startsWith('history_cover_')
          || k.startsWith('progress_')
          || k.startsWith('read_chapters_')
          || k.startsWith('chapter_updates_')
          || k === 'setting_follow_update_state'
          || k.startsWith('page_')
          || k === 'setting_widget_recent_json'
          || k === 'setting_widget_extra_rank_json'
          || k === 'setting_widget_extra_fav_json'
          || k === 'setting_widget_extra_rec_json';
        if (hit) {
          this.prefs.deleteSync(k);
        }
      }
      this.prefs.flushSync();
    } catch (err) {
      console.warn('[CacheManager] clearWidgetUserData failed: ' + JSON.stringify(err));
    }
  }

  // ─── 分类列表缓存 ───

  saveCategories(categoriesJson: string): void {
    let entry: CacheEntry = {
      data: categoriesJson,
      timestamp: Date.now()
    };
    this.putObject('categories', entry);
  }

  loadCategories(): string | null {
    let entry = this.getObject<CacheEntry>('categories');
    if (!entry) return null;
    if (Date.now() - entry.timestamp > CacheManager.TTL_CATEGORY) {
      return null;
    }
    return entry.data;
  }

  // ─── 首页漫画列表缓存 ───

  saveComicsPage(category: string, sort: string, page: number, comicsJson: string, pages: number): void {
    let key = `comics_${category}_${sort}`;
    let entry: CacheEntry = {
      data: comicsJson,
      pages: pages,
      timestamp: Date.now()
    };
    this.putObject(`${key}_p${page}`, entry);
  }

  loadComicsPage(category: string, sort: string, page: number): CacheEntry | null {
    let entry = this.getObject<CacheEntry>(`comics_${category}_${sort}_p${page}`);
    if (!entry) return null;
    if (Date.now() - entry.timestamp > CacheManager.TTL_COMICS) {
      return null;
    }
    return entry;
  }

  clearComicsCache(): void {
    // 无实际分页索引可枚举，此处仅作占位：页缓存通过 TTL 自然过期
    this.put('comics_cache_version', Date.now().toString());
  }

  /** 清理图片相关缓存（章节图片列表 + 列表页缓存 + 分类），返回清除的键数 */
  clearImageCache(): number {
    if (this.prefs === null) {
      return 0;
    }
    let count = 0;
    try {
      let all = this.prefs.getAllSync();
      let keys = Object.keys(all);
      for (let k of keys) {
        if (k.startsWith('chapter_') || k.startsWith('comics_') || k === 'categories') {
          this.prefs.deleteSync(k);
          count++;
        }
      }
      this.prefs.flushSync();
    } catch (err) {
      console.warn('[CacheManager] clearImageCache failed: ' + JSON.stringify(err));
    }
    return count;
  }

  // ─── 章节图片地址缓存 ───

  saveChapterPages(comicId: string, order: number, pagesJson: string): void {
    this.put(`chapter_${comicId}_${order}`, pagesJson);
  }

  loadChapterPages(comicId: string, order: number): string | null {
    return this.getString(`chapter_${comicId}_${order}`) || null;
  }

  // ─── 下载任务 ───

  saveDownloadTasks(tasksJson: string): void {
    this.put('download_tasks', tasksJson);
  }

  loadDownloadTasks(): string {
    return this.getString('download_tasks');
  }

  // ─── 屏蔽标签 ───

  saveBlockedTags(tags: string[]): void {
    this.put('blocked_tags', JSON.stringify(tags));
  }

  loadBlockedTags(): string[] {
    let raw = this.getString('blocked_tags', '[]');
    try {
      return JSON.parse(raw) as string[];
    } catch {
      return [];
    }
  }

  // ─── 搜索历史 ───

  saveSearchHistory(keyword: string): void {
    const value = keyword.trim();
    if (value.length === 0) {
      return;
    }
    let arr = this.loadSearchHistory();
    let idx = arr.indexOf(value);
    if (idx >= 0) {
      arr.splice(idx, 1);
    }
    arr.unshift(value);
    if (arr.length > 20) {
      arr = arr.slice(0, 20);
    }
    this.put('search_history', JSON.stringify(arr));
  }

  loadSearchHistory(): string[] {
    let raw = this.getString('search_history', '[]');
    try {
      const history = JSON.parse(raw) as string[];
      if (!Array.isArray(history)) {
        return [];
      }
      return Array.from(new Set<string>(history.filter((value: string): boolean => typeof value === 'string')
        .map((value: string): string => value.trim()).filter((value: string): boolean => value.length > 0))).slice(0, 20);
    } catch {
      return [];
    }
  }

  clearSearchHistory(): void {
    this.prefs?.deleteSync('search_history');
    this.prefs?.flushSync();
  }

  // ─── 首页频道自定义 ───

  saveChannelsCustom(order: string[], hidden: string[]): void {
    this.put('channels_order', JSON.stringify(order));
    this.put('channels_hidden', JSON.stringify(hidden));
  }

  loadChannelsOrder(): string[] {
    let raw = this.getString('channels_order', '[]');
    try {
      return JSON.parse(raw) as string[];
    } catch {
      return [];
    }
  }

  loadChannelsHidden(): string[] {
    let raw = this.getString('channels_hidden', '[]');
    try {
      return JSON.parse(raw) as string[];
    } catch {
      return [];
    }
  }

  // ─── 通用设置持久化（AppStorage 为内存态，重启后从此恢复） ───

  saveSetting(key: string, value: string): void {
    this.put('setting_' + key, value);
  }

  getSetting(key: string, defVal: string = ''): string {
    return this.getString('setting_' + key, defVal);
  }

  // ─── 用户偏好 ───

  saveLastCategory(category: string): void {
    this.put('pref_category', category);
  }

  getLastCategory(): string {
    return this.getString('pref_category');
  }

  saveLastSort(sort: string): void {
    this.put('pref_sort', sort);
  }

  getLastSort(): string {
    return this.getString('pref_sort', 'dd');
  }

  // ─── 阅读进度 ───

  private loadChapterUpdateState(comicId: string): ChapterUpdateState | null {
    const state = this.getObject<ChapterUpdateState>('chapter_updates_' + comicId);
    if (state === null || !Number.isInteger(state.epsCount) || state.epsCount < 0
      || !Number.isInteger(state.pendingFromCount) || state.pendingFromCount < -1
      || (state.pendingFromCount >= 0 && state.pendingFromCount >= state.epsCount)
      || (state.knownChapterIds !== undefined && (!Array.isArray(state.knownChapterIds)
        || !state.knownChapterIds.every((id: string): boolean => typeof id === 'string' && id.length > 0)))
      || !Array.isArray(state.chapters)
      || !state.chapters.every((chapter: ChapterUpdateChapter): boolean => chapter !== null
        && typeof chapter.id === 'string' && chapter.id.length > 0
        && Number.isInteger(chapter.order) && chapter.order > 0)) {
      return null;
    }
    return state;
  }

  /** 首次启用章节标记时，沿用已有追更检查基线，不把已有收藏全部标为更新。 */
  private previousFollowChapterCount(comicId: string, fallback: number): number {
    try {
      const state = JSON.parse(this.getSetting('follow_update_state', 'null')) as FollowChapterState;
      if (state !== null && Array.isArray(state.snapshots)) {
        const comic = state.snapshots.find((snapshot: FollowChapterSnapshot): boolean =>
          snapshot !== null && snapshot.comicId === comicId);
        if (comic !== undefined && Number.isInteger(comic.epsCount) && comic.epsCount >= 0) {
          return comic.epsCount;
        }
      }
    } catch (_err) {
      // 没有旧版追更快照时，首次成功检查仅建立基线。
    }
    return fallback;
  }

  /** 只按章节数增长生成新增段；计数回退时保留高水位，恢复后不重复标记。 */
  recordChapterCount(comicId: string, count: number): void {
    if (!comicId || !Number.isInteger(count) || count < 0) {
      return;
    }
    const saved = this.loadChapterUpdateState(comicId);
    const state: ChapterUpdateState = saved ?? {
      epsCount: this.previousFollowChapterCount(comicId, count), pendingFromCount: -1, chapters: []
    };
    if (count > state.epsCount) {
      if (state.pendingFromCount < 0) {
        state.pendingFromCount = state.epsCount;
      }
      state.epsCount = count;
    } else if (saved !== null) {
      return;
    }
    this.putObject('chapter_updates_' + comicId, state);
  }

  /** 完整章节列表与详情计数一致才推进基线；未读更新保留到实际阅读。 */
  getUpdatedChapterOrders(comicId: string, chapters: ChapterUpdateChapter[], expectedCount: number): number[] {
    if (!comicId || !Number.isInteger(expectedCount) || expectedCount < 0) {
      return [];
    }
    const ids = new Set<string>();
    const orders = new Set<number>();
    for (const chapter of chapters) {
      if (!chapter.id || !Number.isInteger(chapter.order) || chapter.order <= 0
        || ids.has(chapter.id) || orders.has(chapter.order)) {
        return [];
      }
      ids.add(chapter.id);
      orders.add(chapter.order);
    }
    const sorted = chapters.slice().sort((a: ChapterUpdateChapter, b: ChapterUpdateChapter): number => a.order - b.order);
    const complete = chapters.length === expectedCount;
    if (complete) {
      this.recordChapterCount(comicId, expectedCount);
    }
    const state = this.loadChapterUpdateState(comicId);
    if (state === null) {
      return [];
    }
    const before = JSON.stringify(state);
    const updatedIds = new Set<string>(state.chapters.map((chapter: ChapterUpdateChapter): string => chapter.id));
    if (complete && chapters.length >= state.epsCount && state.pendingFromCount >= 0) {
      const knownIds = state.knownChapterIds === undefined ? undefined : new Set<string>(state.knownChapterIds);
      const added = knownIds === undefined ? sorted.slice(state.pendingFromCount, state.epsCount)
        : sorted.filter((chapter: ChapterUpdateChapter): boolean => !knownIds.has(chapter.id));
      for (const chapter of added) {
        if (!updatedIds.has(chapter.id)) {
          state.chapters.push({ id: chapter.id, order: chapter.order });
          updatedIds.add(chapter.id);
        }
      }
      state.pendingFromCount = -1;
    }
    if (complete && chapters.length >= state.epsCount) {
      state.knownChapterIds = sorted.map((chapter: ChapterUpdateChapter): string => chapter.id);
      state.chapters = state.chapters.filter((chapter: ChapterUpdateChapter): boolean => ids.has(chapter.id));
    }
    const readOrders = this.getReadChapters(comicId);
    state.chapters = state.chapters.filter((chapter: ChapterUpdateChapter): boolean => readOrders.indexOf(chapter.order) < 0);
    if (JSON.stringify(state) !== before) {
      this.putObject('chapter_updates_' + comicId, state);
    }
    const remainingIds = new Set<string>(state.chapters.map((chapter: ChapterUpdateChapter): string => chapter.id));
    return sorted.filter((chapter: ChapterUpdateChapter): boolean => remainingIds.has(chapter.id))
      .map((chapter: ChapterUpdateChapter): number => chapter.order);
  }

  /** 离线只读取已有更新标记，不用不完整目录覆盖追更基线。 */
  getCachedUpdatedChapterOrders(comicId: string): number[] {
    const state = this.loadChapterUpdateState(comicId);
    const read = this.getReadChapters(comicId);
    return (state?.chapters ?? []).filter((chapter: ChapterUpdateChapter): boolean => read.indexOf(chapter.order) < 0)
      .map((chapter: ChapterUpdateChapter): number => chapter.order);
  }

  saveReadProgress(comicId: string, order: number): void {
    if (!comicId || !Number.isInteger(order) || order <= 0) {
      return;
    }
    const chapters: number[] = this.getReadChapters(comicId);
    if (chapters.indexOf(order) < 0) {
      chapters.push(order);
    }
    this.putObject('read_chapters_' + comicId, chapters);
    const updates = this.loadChapterUpdateState(comicId);
    if (updates !== null && updates.chapters.some((chapter: ChapterUpdateChapter): boolean => chapter.order === order)) {
      updates.chapters = updates.chapters.filter((chapter: ChapterUpdateChapter): boolean => chapter.order !== order);
      this.putObject('chapter_updates_' + comicId, updates);
    }
    this.put('progress_' + comicId, order.toString());
    this.put('history_time_' + comicId, Date.now().toString());
  }

  /** 逐章已读记录；旧版本只迁移有页级记录的章节与最后阅读章节，不推断前面的章节。 */
  getReadChapters(comicId: string): number[] {
    if (!comicId) {
      return [];
    }
    const saved = this.getObject<number[]>('read_chapters_' + comicId);
    if (saved !== null && Array.isArray(saved)) {
      return saved.filter((order: number, index: number): boolean =>
        Number.isInteger(order) && order > 0 && saved.indexOf(order) === index);
    }
    const chapters: number[] = [];
    const last = this.getReadProgress(comicId);
    if (Number.isInteger(last) && last > 0) {
      chapters.push(last);
    }
    if (this.prefs !== null) {
      const prefix = 'page_' + comicId + '_';
      for (const key of Object.keys(this.prefs.getAllSync())) {
        if (key.startsWith(prefix)) {
          const order = Number(key.substring(prefix.length));
          if (Number.isInteger(order) && order > 0 && chapters.indexOf(order) < 0) {
            chapters.push(order);
          }
        }
      }
      this.putObject('read_chapters_' + comicId, chapters);
    }
    return chapters;
  }

  /** 页级进度：某话读到第几页 */
  savePageProgress(comicId: string, order: number, pageIndex: number): void {
    this.put('page_' + comicId + '_' + order, pageIndex.toString());
  }

  getPageProgress(comicId: string, order: number): number {
    let val = this.getString('page_' + comicId + '_' + order);
    return val ? parseInt(val) : 0;
  }

  getReadProgress(comicId: string): number {
    let val = this.getString('progress_' + comicId);
    return val ? parseInt(val) : 0;
  }

  /** 记录浏览历史条目（含标题与封面） */
  saveHistoryItem(comicId: string, title: string, order: number, coverUrl: string = ''): void {
    this.put('history_title_' + comicId, title);
    this.put('history_order_' + comicId, order.toString());
    this.put('history_time_' + comicId, Date.now().toString());
    if (coverUrl.length > 0) {
      this.put('history_cover_' + comicId, coverUrl);
    }
    let ids = this.getString('history_ids', '[]');
    let arr: string[] = [];
    try {
      arr = JSON.parse(ids) as string[];
    } catch {
      arr = [];
    }
    if (arr.indexOf(comicId) < 0) {
      arr.push(comicId);
      this.put('history_ids', JSON.stringify(arr));
    }
  }

  /** 读取浏览历史（按时间倒序） */
  loadHistory(): HistoryItem[] {
    let ids = this.getString('history_ids', '[]');
    let arr: string[] = [];
    try {
      arr = JSON.parse(ids) as string[];
    } catch {
      return [];
    }
    let items: HistoryItem[] = [];
    for (let id of arr) {
      let title = this.getString('history_title_' + id);
      if (title.length === 0) {
        continue;
      }
      items.push({
        comicId: id,
        title: title,
        order: parseInt(this.getString('history_order_' + id, '0')),
        timestamp: parseInt(this.getString('history_time_' + id, '0')),
        coverUrl: this.getString('history_cover_' + id, '')
      });
    }
    items.sort((a: HistoryItem, b: HistoryItem) => b.timestamp - a.timestamp);
    return items;
  }

  /** 删除单条历史 */
  deleteHistoryItem(comicId: string): void {
    if (this.prefs === null) {
      return;
    }
    this.prefs.deleteSync('history_title_' + comicId);
    this.prefs.deleteSync('history_order_' + comicId);
    this.prefs.deleteSync('history_time_' + comicId);
    this.prefs.deleteSync('history_cover_' + comicId);
    let ids = this.getString('history_ids', '[]');
    let arr: string[] = [];
    try {
      arr = JSON.parse(ids) as string[];
    } catch {
      arr = [];
    }
    let idx = arr.indexOf(comicId);
    if (idx >= 0) {
      arr.splice(idx, 1);
      this.put('history_ids', JSON.stringify(arr));
    }
    this.prefs.flushSync();
  }

  /** 清空全部历史 */
  clearHistory(): void {
    if (this.prefs === null) {
      return;
    }
    let ids = this.getString('history_ids', '[]');
    let arr: string[] = [];
    try {
      arr = JSON.parse(ids) as string[];
    } catch {
      arr = [];
    }
    for (let id of arr) {
      this.prefs.deleteSync('history_title_' + id);
      this.prefs.deleteSync('history_order_' + id);
      this.prefs.deleteSync('history_time_' + id);
      this.prefs.deleteSync('history_cover_' + id);
    }
    this.prefs.deleteSync('history_ids');
    this.prefs.flushSync();
  }
}

/** 浏览历史条目 */
export interface HistoryItem {
  comicId: string;
  title: string;
  order: number;
  timestamp: number;
  /** 封面图 URL（用于历史列表缩略图） */
  coverUrl: string;
}

/** 缓存条目 */
interface CacheEntry {
  data: string;
  pages?: number;
  timestamp: number;
}
