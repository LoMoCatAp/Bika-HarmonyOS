import { preferences } from '@kit.ArkData';

/**
 * 本地缓存管理器
 * 基于 Preferences 实现数据持久化，减少网络请求
 *
 * 缓存策略：
 * - 凭据：token、邮箱、密码（自动登录用）
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

  private constructor() {
  }

  static async getInstance(): Promise<CacheManager> {
    if (CacheManager.instance === null) {
      CacheManager.instance = new CacheManager();
    }
    if (CacheManager.instance.prefs === null) {
      CacheManager.instance.prefs = await preferences.getPreferences(getContext(), CacheManager.PREF_NAME);
    }
    return CacheManager.instance;
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

  saveToken(token: string): void {
    this.put('auth_token', token);
  }

  getToken(): string {
    return this.getString('auth_token');
  }

  saveCredentials(email: string, password: string): void {
    this.put('auth_email', email);
    this.put('auth_password', password);
  }

  getEmail(): string {
    return this.getString('auth_email');
  }

  getPassword(): string {
    return this.getString('auth_password');
  }

  clearAuth(): void {
    this.prefs?.deleteSync('auth_token');
    this.prefs?.deleteSync('auth_email');
    this.prefs?.deleteSync('auth_password');
    this.prefs?.flushSync();
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

  saveReadProgress(comicId: string, order: number): void {
    this.put('progress_' + comicId, order.toString());
    this.put('history_time_' + comicId, Date.now().toString());
  }

  getReadProgress(comicId: string): number {
    let val = this.getString('progress_' + comicId);
    return val ? parseInt(val) : 0;
  }

  /** 记录浏览历史条目（含标题） */
  saveHistoryItem(comicId: string, title: string, order: number): void {
    this.put('history_title_' + comicId, title);
    this.put('history_order_' + comicId, order.toString());
    this.put('history_time_' + comicId, Date.now().toString());
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
        timestamp: parseInt(this.getString('history_time_' + id, '0'))
      });
    }
    items.sort((a: HistoryItem, b: HistoryItem) => b.timestamp - a.timestamp);
    return items;
  }
}

/** 浏览历史条目 */
export interface HistoryItem {
  comicId: string;
  title: string;
  order: number;
  timestamp: number;
}

/** 缓存条目 */
interface CacheEntry {
  data: string;
  pages?: number;
  timestamp: number;
}