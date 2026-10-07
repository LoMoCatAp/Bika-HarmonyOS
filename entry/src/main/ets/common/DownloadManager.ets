import { fileIo as fs } from '@kit.CoreFileKit';
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ApiService } from '../network/ApiService';
import { ImageLoader } from './ImageLoader';
import { CacheManager } from './CacheManager';
import { BikaPageDoc, buildImageUrl } from '../models/Comic';

/** 镜像候选（与项目其它下载路径保持一致） */
const MIRROR_HOSTS: string[] = [
  'https://s3.go2778.com',
  'https://storage-b.go2778.com',
  'https://img.go2778.com'
];

/** 进度通知标题与正文都不含作品名、也不含其它应用名 */
const NOTIFY_TITLE: string = '正在下载';
/** 终态 / 暂停态标题：完成、失败、暂停都要看得出状态，不能一直停在「正在下载」 */
const NOTIFY_DONE_TITLE: string = '下载完成';
const NOTIFY_FAIL_TITLE: string = '下载失败';
const NOTIFY_PAUSE_TITLE: string = '已暂停';
/** 终态通知保留时长（毫秒）：超时由系统自动清除，另留兜底 cancel */
const NOTIFY_FINAL_KEEP_MS: number = 5000;
/** 系统预置的下载进度条模板（进度条由系统按 progressValue 渲染） */
const NOTIFY_TEMPLATE: string = 'downloadTemplate';
/** 同一话的进度通知固定分组：清空下载时一次 cancelGroup 清理干净 */
const NOTIFY_GROUP: string = 'bika_download_chapter';
/** 进度通知重发布节流窗口（毫秒）：避免每页都刷新系统通知 */
const NOTIFY_MIN_INTERVAL: number = 800;
/** 通知 id 偏移，避开系统常驻通知占用的低位 id 段 */
const NOTIFY_ID_BASE: number = 10000;
/** 通知 id 取模范围（保证落在 32 位正整数区间） */
const NOTIFY_ID_RANGE: number = 2000000000;

/** UI 订阅回调与版本号的刷新节流窗口（毫秒）：每页一次的回调合并到约 3 次/秒 */
const UI_NOTIFY_INTERVAL: number = 300;

/** 单页最多尝试次数（含首次），用尽后整话标记失败，等待用户重试 */
const MAX_PAGE_ATTEMPTS: number = 3;

/**
 * 下载任务（漫画 + 章节 + 进度）——一话一条记录，保持既有 download_tasks 存储结构。
 */
export interface DownloadTask {
  comicId: string;
  comicTitle: string;
  coverUrl: string;
  /** 本地封面路径（头图一并下载） */
  coverLocal: string;
  /** 简介（一并保存，离线展示） */
  description: string;
  author: string;
  chapterOrder: number;
  chapterTitle: string;
  status: string;
  progress: number;
  total: number;
  dir: string;
  /** 占用空间（字节，完成后计算） */
  sizeBytes: number;
}

/**
 * 下载管理器（自有下载器 + 一话一条通知 + 长时任务保活）
 *
 * - 一话 = 一条持久化任务记录（download_tasks），进度与每页状态由磁盘实际文件推导；
 * - 下载执行层是应用自有下载器（ImageLoader/BikaHttpClient 取字节流后自己写文件），
 *   不经系统下载服务，因此不会出现「每张图一条系统下载通知」；
 * - 目标路径就是阅读器读取的最终路径
 *   （filesDir/bika_download/<comicId>/<order>/<i>.jpg），零搬运，写完即可离线阅读；
 * - 重启自动续传：启动时按磁盘上「存在且非 0 字节」的文件校正进度，剩余页重新入队；
 * - 并发上限 = 用户设置的最大并发数（话级并发，1~5）；
 * - 仅 WiFi 下载：非 WiFi 时暂停派发，网络恢复后自动续传（需要 GET_NETWORK_INFO 权限）；
 * - 通知：一话一条进度通知（id = comicId+order 的稳定哈希），同 id 重新 publish 原地刷新，
 *   完成 / 失败时 cancel；未授权通知时静默降级为仅应用内进度；
 * - 长时任务：有下载在跑时 startBackgroundRunning(DATA_TRANSFER)，
 *   全部结束 / 失败 / 等待 WiFi 时 stopBackgroundRunning。
 */
export class DownloadManager {
  private static instance: DownloadManager | null = null;
  private tasks: DownloadTask[] = [];
  /** 进行中的任务数（并发控制：同时下载的话数） */
  private activeCount: number = 0;
  /** 派发锁（防止并发调用重复派发同一任务） */
  private dispatching: boolean = false;
  /** 派发期间又有新请求：结束后补一次 */
  private startQueued: boolean = false;
  /** 仅 WiFi 下载 */
  private wifiOnly: boolean = false;
  /** 最大并发数（1~5） */
  private maxConcurrent: number = 1;
  private netListenerRegistered: boolean = false;
  private listeners: Array<(tasks: DownloadTask[]) => void> = [];
  private apiService: ApiService = ApiService.getInstance();

  /** 应用上下文（长时任务与通知授权都需要 UIAbilityContext） */
  private abilityCtx: common.UIAbilityContext | null = null;
  /** EntryAbility 注入上下文后置位：之前只加载数据，不派发、不启长时任务 */
  private ready: boolean = false;
  private loaded: boolean = false;
  private loadTimer: number = -1;
  private pumpTimer: number = -1;
  /** 章节图片列表运行期缓存（comicId#order → 页面文档） */
  private pageCache: Map<string, BikaPageDoc[]> = new Map();

  // ── 通知状态 ──
  /** 0 未知 / 1 已允许 / 2 已拒绝（降级：不发通知，仅应用内进度） */
  private notifyState: number = 0;
  /** 系统下载进度模板支持情况：0 未知 / 1 支持 / 2 不支持 */
  private templateState: number = 0;
  /** 本会话是否已弹过一次通知授权 */
  private notifyAsked: boolean = false;
  /** 进度通知节流 */
  private notifyTimer: number = -1;
  /** 每话的通知世代号：cancel / 终态时自增，用于丢弃「取消后才落地的补发」 */
  private notifyEpoch: Map<string, number> = new Map();
  /**
   * 通知 IPC 串行队列：publish / cancel 都排队执行，
   * 保证「取消」或「终态」一定排在之前的进度 publish 之后，不会被反向覆盖。
   */
  private notifyQueue: Promise<void> = Promise.resolve();

  // ── UI 刷新节流 ──
  private uiNotifyTimer: number = -1;
  private uiNotifyPending: boolean = false;
  private notifyDirty: boolean = false;
  private lastNotifyAt: number = 0;

  // ── 长时任务状态 ──
  private continuousRunning: boolean = false;
  private continuousStarting: boolean = false;
  private wantAgentObj: WantAgent | null = null;

  static getInstance(): DownloadManager {
    if (!DownloadManager.instance) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  private constructor() {
    this.wifiOnly = AppStorage.get<boolean>('bika_download_wifi_only') === true;
    let c: number | undefined = AppStorage.get<number>('bika_download_concurrent');
    if (typeof c === 'number' && c >= 1 && c <= 5) {
      this.maxConcurrent = c;
    }
    this.load();
    this.startWifiPoll();
  }

  // ─────────────── 生命周期 / 上下文 ───────────────

  /** 入口注入应用上下文（EntryAbility 启动时调用），随后加载持久化任务并续传 */
  init(ctx: common.UIAbilityContext): void {
    this.abilityCtx = ctx;
    if (this.ready) {
      return;
    }
    this.ready = true;
    this.load(true).catch((e: Error) => {
      console.warn('[DownloadManager] init load failed: ' + e.message);
    });
  }

  /** 应用上下文（长时任务 / 通知授权需要 UIAbilityContext） */
  private abilityContext(): common.UIAbilityContext | null {
    if (this.abilityCtx) {
      return this.abilityCtx;
    }
    try {
      let c: common.Context = getContext() as common.Context;
      if (c) {
        let u: common.UIAbilityContext = c as common.UIAbilityContext;
        this.abilityCtx = u;
        return u;
      }
    } catch (err) {
      // 非 UI 场景且未注入上下文时不可用
    }
    return null;
  }

  private cacheInstance(): Promise<CacheManager> {
    return CacheManager.getInstance(this.abilityCtx ?? undefined);
  }

  // ─────────────── 设置 ───────────────

  /** 仅 WiFi 下载开关 */
  setWifiOnly(only: boolean): void {
    this.wifiOnly = only;
    AppStorage.setOrCreate('bika_download_wifi_only', only);
    this.cacheInstance().then(c => c.saveSetting('wifi_only', only ? 'true' : 'false')).catch(() => {});
    this.notify();
    if (only && !this.isWifiNow()) {
      this.pauseAllForNetwork();
    } else {
      this.startNext();
    }
  }

  getWifiOnly(): boolean {
    return this.wifiOnly;
  }

  /** 最大并发数（1~5） */
  setMaxConcurrent(n: number): void {
    this.maxConcurrent = Math.min(5, Math.max(1, n));
    AppStorage.setOrCreate('bika_download_concurrent', this.maxConcurrent);
    this.cacheInstance().then(c => c.saveSetting('concurrent', String(this.maxConcurrent))).catch(() => {});
    this.notify();
    this.startNext();
  }

  getMaxConcurrent(): number {
    return this.maxConcurrent;
  }

  /** 当前是否连接 WiFi（需要 ohos.permission.GET_NETWORK_INFO，否则抛 201 恒为 false） */
  isWifiNow(): boolean {
    try {
      let net = connection.getDefaultNetSync();
      let caps = connection.getNetCapabilitiesSync(net);
      if (caps && caps.bearerTypes) {
        return caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
      }
    } catch (err) {
      // 无网络 / 无权限 / 查询失败一律按非 WiFi 处理
    }
    return false;
  }

  /** WiFi 轮询：仅 WiFi 下载时，网络恢复后自动续传；断开时暂停派发 */
  private startWifiPoll(): void {
    if (this.netListenerRegistered) {
      return;
    }
    this.netListenerRegistered = true;
    setInterval(() => {
      if (!this.wifiOnly) {
        return;
      }
      if (this.isWifiNow()) {
        let hasWaiting = this.tasks.some(t => t.status === 'waiting');
        if (hasWaiting) {
          this.startNext();
        }
      } else {
        this.pauseAllForNetwork();
      }
    }, 10000);
  }

  // ─────────────── 查询 / 订阅 ───────────────

  getTasks(): DownloadTask[] {
    // 返回浅拷贝：确保 @State 引用变化触发 UI 实时刷新
    return this.tasks.slice();
  }

  hasTask(comicId: string, order: number): DownloadTask | undefined {
    return this.tasks.find(t => t.comicId === comicId && t.chapterOrder === order);
  }

  subscribe(cb: (tasks: DownloadTask[]) => void): void {
    // 去重：同一回调重复订阅（页面反复进出）不叠加，避免重复刷新与监听泄漏
    if (this.listeners.indexOf(cb) < 0) {
      this.listeners.push(cb);
    }
    cb(this.tasks.slice());
  }

  unsubscribe(cb: (tasks: DownloadTask[]) => void): void {
    let idx = this.listeners.indexOf(cb);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /**
   * 通知 UI：长时任务状态立即对齐，订阅回调与 AppStorage 版本号走节流。
   *
   * 节流采用「前缘立即 + 尾缘补发」：
   * - 第一次变化立即回调，加入任务 / 完成 / 失败 / 删除等瞬时状态不延迟；
   * - 窗口内的后续变化合并，窗口结束时补发一次最新状态，
   *   保证最后一页的进度不会被吞掉（下载页进度条能走到 100%）。
   */
  notify(): void {
    this.syncContinuousTask();
    this.scheduleUiNotify();
  }

  /** UI 刷新节流调度（回调可能每页触发一次，节流到 UI_NOTIFY_INTERVAL） */
  private scheduleUiNotify(): void {
    if (this.uiNotifyTimer >= 0) {
      this.uiNotifyPending = true;
      return;
    }
    this.emitUiNotify();
    this.uiNotifyTimer = setTimeout(() => {
      this.uiNotifyTimer = -1;
      if (this.uiNotifyPending) {
        this.uiNotifyPending = false;
        this.scheduleUiNotify();
      }
    }, UI_NOTIFY_INTERVAL);
  }

  /** 真正把最新任务快照推给订阅者 */
  private emitUiNotify(): void {
    let copy = this.tasks.slice();
    for (let cb of this.listeners) {
      try {
        cb(copy);
      } catch (err) {
        console.warn('[DownloadManager] listener error: ' + JSON.stringify(err));
      }
    }
    AppStorage.set('download_revision', Date.now());
  }

  // ─────────────── 路径（与旧版本一致，保证阅读器与已下载数据兼容） ───────────────

  private filesDir(): string {
    let c = this.abilityContext();
    return c ? c.filesDir : '';
  }

  private comicDir(comicId: string): string {
    return this.filesDir() + '/bika_download/' + comicId;
  }

  private chapterDir(comicId: string, order: number): string {
    return this.comicDir(comicId) + '/' + order;
  }

  private coverPath(comicId: string): string {
    return this.comicDir(comicId) + '/cover.jpg';
  }

  /** 页面最终路径（就是阅读器读取的路径） */
  private pagePath(dir: string, pageIndex: number): string {
    return dir + '/' + pageIndex + '.jpg';
  }

  /** 递归建目录：filesDir/bika_download 可能整体不存在，非递归 mkdir 会报 13900002 */
  private ensureDir(dir: string): void {
    if (dir.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (err) {
      try {
        fs.mkdirSync(dir, true);
      } catch (err2) {
        console.warn('[DownloadManager] mkdir failed: ' + JSON.stringify(err2));
      }
    }
  }

  private exists(path: string): boolean {
    try {
      return path.length > 0 && fs.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  /**
   * 页面是否已完整落盘。
   * 应用被强杀时可能留下 0 字节文件，必须按「存在且非空」判定，
   * 否则会误认为已下载，阅读器读到空图。
   */
  private pageDone(path: string): boolean {
    try {
      if (path.length === 0 || !fs.accessSync(path)) {
        return false;
      }
      return fs.statSync(path).size > 0;
    } catch (err) {
      return false;
    }
  }

  private pageKey(comicId: string, order: number): string {
    return comicId + '#' + order;
  }

  // ─────────────── 入队 / 删除 / 重试 ───────────────

  /** 添加下载任务（去重；同步入队，后台按并发上限逐话下载） */
  addTask(comicId: string, title: string, coverUrl: string, description: string, author: string,
    order: number, chapterTitle: string): void {
    if (this.hasTask(comicId, order)) {
      return;
    }
    let task: DownloadTask = {
      comicId: comicId,
      comicTitle: title,
      coverUrl: coverUrl,
      coverLocal: this.coverPath(comicId),
      description: description,
      author: author,
      chapterOrder: order,
      chapterTitle: chapterTitle,
      status: 'waiting',
      progress: 0,
      total: 0,
      dir: this.chapterDir(comicId, order),
      sizeBytes: 0
    };
    this.tasks.push(task);
    this.persist();
    this.notify();
    this.startNext();
  }

  /** 重试失败任务：取消旧通知，按剩余文件续传 */
  retryTask(comicId: string, order: number): void {
    let task = this.tasks.find(t => t.comicId === comicId && t.chapterOrder === order);
    if (!task) {
      return;
    }
    this.cancelProgress(task);
    task.status = 'waiting';
    task.progress = this.countExistingPages(task);
    if (task.total > 0 && task.progress === task.total) {
      task.status = 'completed';
      task.sizeBytes = this.calcDirSize(task.dir);
    }
    this.persist();
    this.notify();
    this.startNext();
  }

  /** 删除任务与本地文件（同时取消该话通知） */
  deleteTask(comicId: string, order: number): void {
    let idx = this.tasks.findIndex(t => t.comicId === comicId && t.chapterOrder === order);
    if (idx < 0) {
      return;
    }
    let dir = this.tasks[idx].dir;
    this.cancelProgress(this.tasks[idx]);
    this.tasks.splice(idx, 1);
    this.persist();
    this.notify();
    this.removeDirRecursive(dir);
  }

  /** 清空全部下载任务与本地文件（一次 cancelGroup 清掉所有话进度通知） */
  clearAll(): void {
    for (let t of this.tasks) {
      this.removeDirRecursive(t.dir);
    }
    this.tasks = [];
    this.cancelAllProgress();
    this.persist();
    this.notify();
  }

  /** 递归删除目录（rmdirSync 只能删空目录，章节目录含图片文件） */
  private removeDirRecursive(dir: string): void {
    try {
      let files = fs.listFileSync(dir);
      for (let name of files) {
        let path = dir + '/' + name;
        try {
          let stat = fs.statSync(path);
          if (stat.isDirectory()) {
            this.removeDirRecursive(path);
          } else {
            fs.unlinkSync(path);
          }
        } catch (err) {
          console.warn('[DownloadManager] remove failed: ' + path);
        }
      }
      fs.rmdirSync(dir);
    } catch (err) {
      console.warn('[DownloadManager] removeDirRecursive failed');
    }
  }

  // ─────────────── 目录统计 ───────────────

  /** 计算目录占用空间（字节） */
  private calcDirSize(dir: string): number {
    let total = 0;
    try {
      let files = fs.listFileSync(dir);
      for (let name of files) {
        try {
          total += fs.statSync(dir + '/' + name).size;
        } catch (err) {
        }
      }
    } catch (err) {
    }
    return total;
  }

  /** 下载总占用（字节，实时统计目录大小） */
  getTotalSizeBytes(): number {
    let total = 0;
    for (let t of this.tasks) {
      try {
        total += this.calcDirSize(t.dir);
      } catch (err) {
      }
    }
    return total;
  }

  /** 统计已完整落盘的页数（用于修正 progress / 续传） */
  private countExistingPages(task: DownloadTask): number {
    if (task.total <= 0) {
      return 0;
    }
    let n = 0;
    for (let i = 0; i < task.total; i++) {
      if (this.pageDone(this.pagePath(task.dir, i))) {
        n++;
      }
    }
    return n;
  }

  /** 第一章尚未完整下载的页号；全部完成返回 -1 */
  private firstPendingIndex(task: DownloadTask): number {
    for (let i = 0; i < task.total; i++) {
      if (!this.pageDone(this.pagePath(task.dir, i))) {
        return i;
      }
    }
    return -1;
  }

  // ─────────────── 队列泵 ───────────────

  /** startNext 节流：多次触发合并为一次 */
  private scheduleStart(): void {
    if (this.pumpTimer >= 0) {
      return;
    }
    this.pumpTimer = setTimeout(() => {
      this.pumpTimer = -1;
      this.startNext();
    }, 150);
  }

  /**
   * 队列泵：按最大并发数派发等待中的话。
   * 并发粒度是「话」：一话内部的页串行下载，避免瞬时打满连接。
   */
  private async startNext(): Promise<void> {
    if (this.dispatching) {
      this.startQueued = true;
      return;
    }
    if (!this.ready || !this.abilityContext()) {
      return;
    }
    this.dispatching = true;
    try {
      while (true) {
        if (this.activeCount >= this.maxConcurrent) {
          break;
        }
        let task = this.tasks.find(t => t.status === 'waiting');
        if (!task) {
          break;
        }
        // 仅 WiFi 限制：非 WiFi 时暂停派发（连上 WiFi 后自动续传）
        if (this.wifiOnly && !this.isWifiNow()) {
          break;
        }
        this.activeCount++;
        this.execute(task).then(() => {
          this.activeCount--;
          this.notify();
          this.startNext();
        }).catch((err: Error) => {
          this.activeCount--;
          console.warn('[DownloadManager] execute error: ' + err.message);
          this.notify();
          this.startNext();
        });
      }
    } finally {
      this.dispatching = false;
      if (this.startQueued) {
        this.startQueued = false;
        this.scheduleStart();
      }
    }
  }

  /** 暂停派发（仅 WiFi 开关在非 WiFi 下开启时调用）：在跑的话跑完当前页后停下 */
  private pauseAllForNetwork(): void {
    let changed = false;
    for (let task of this.tasks) {
      if (task.status !== 'downloading') {
        continue;
      }
      task.status = 'waiting';
      // 暂停时通知改文案，不能继续显示「正在下载」
      this.publishPaused(task);
      changed = true;
    }
    if (changed) {
      this.persist();
      this.notify();
    } else {
      // 即使没有在跑的任务，长时任务也要按「没有可派发工作」停掉
      this.syncContinuousTask();
    }
  }

  // ─────────────── 下载执行 ───────────────

  /**
   * 执行一话：取章节页文档 → 逐页取字节流写文件。
   * 已存在的非空文件直接跳过（重启续传 / 重试都走这里）。
   */
  private async execute(task: DownloadTask): Promise<void> {
    task.status = 'downloading';
    task.progress = this.countExistingPages(task);
    this.notify();
    // 一话开始：发布进度通知（同 id 会原地刷新）
    this.publishProgress(task, true);
    try {
      await this.ensureCover(task);
      let pages = await this.loadPages(task);
      if (!pages || pages.length === 0) {
        throw new Error('chapter pages unavailable');
      }
      task.total = pages.length;
      task.progress = this.countExistingPages(task);
      this.ensureDir(this.comicDir(task.comicId));
      this.ensureDir(task.dir);
      this.persist();
      this.notify();
      this.publishProgress(task, true);

      let done: number = task.progress;
      for (let i = 0; i < pages.length; i++) {
        // 任务被删除 / 被暂停（仅 WiFi 断开）：停止继续写盘
        if (this.tasks.indexOf(task) < 0) {
          return;
        }
        if (task.status !== 'downloading') {
          this.persist();
          this.notify();
          return;
        }
        if (this.pageDone(this.pagePath(task.dir, i))) {
          continue;
        }
        let urls: string[] = this.buildUrls(pages, i);
        if (urls.length === 0) {
          throw new Error('no image url for page');
        }
        let bytes: ArrayBuffer | null = null;
        let lastError: Error = new Error('download failed');
        for (let attempt = 0; attempt < MAX_PAGE_ATTEMPTS && bytes === null; attempt++) {
          try {
            bytes = await ImageLoader.downloadBytes(urls);
          } catch (err) {
            lastError = err as Error;
          }
        }
        if (bytes === null) {
          throw lastError;
        }
        let file = fs.openSync(this.pagePath(task.dir, i),
          fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, bytes);
        fs.closeSync(file.fd);
        done++;
        task.progress = done > task.total ? task.total : done;
        this.notify();
        // 进度通知节流刷新
        this.publishProgress(task, false);
        // 节流持久化：每 5 页落盘一次，中断后可按磁盘恢复进度
        if (i % 5 === 0 || i === pages.length - 1) {
          this.persist();
        }
      }
      if (task.status !== 'downloading') {
        this.persist();
        this.notify();
        return;
      }
      task.status = 'completed';
      task.progress = task.total;
      task.sizeBytes = this.calcDirSize(task.dir);
      // 一话完成：同一条通知更新为「下载完成」，几秒后自动消失
      this.publishFinal(task, NOTIFY_DONE_TITLE);
    } catch (err) {
      task.status = 'failed';
      let e = err as Error;
      console.warn('[DownloadManager] chapter download failed: ' + e.message);
      // 一话失败：同一条通知更新为「下载失败」，几秒后自动消失
      this.publishFinal(task, NOTIFY_FAIL_TITLE);
    }
    this.persist();
    this.notify();
  }

  /** 章节页文档：优先复用缓存（阅读器也写同一份缓存），失败回退网络 */
  private async loadPages(task: DownloadTask): Promise<BikaPageDoc[] | null> {
    let key = this.pageKey(task.comicId, task.chapterOrder);
    let cached = this.pageCache.get(key);
    if (cached && cached.length > 0) {
      return cached;
    }
    try {
      let cache = await this.cacheInstance();
      let raw = cache.loadChapterPages(task.comicId, task.chapterOrder);
      if (raw) {
        try {
          let docs = JSON.parse(raw) as BikaPageDoc[];
          if (docs && docs.length > 0) {
            this.pageCache.set(key, docs);
            return docs;
          }
        } catch (e0) {
          // 缓存解析失败：走网络
        }
      }
      let pages = await this.apiService.getChapterPages(task.comicId, task.chapterOrder);
      if (pages && pages.length > 0) {
        this.pageCache.set(key, pages);
        cache.saveChapterPages(task.comicId, task.chapterOrder, JSON.stringify(pages));
        return pages;
      }
    } catch (err) {
      let e = err as Error;
      console.warn('[DownloadManager] chapter pages failed: ' + e.message);
    }
    return null;
  }

  /** 构造候选 URL（主地址 + 镜像） */
  private buildUrls(pages: BikaPageDoc[], pageIndex: number): string[] {
    let urls: string[] = [];
    if (pageIndex >= pages.length) {
      return urls;
    }
    let primary = buildImageUrl(pages[pageIndex].media);
    if (primary.length === 0) {
      return urls;
    }
    urls.push(primary);
    let idx = primary.indexOf('/static/');
    if (idx > 0) {
      let pathPart = primary.substring(idx);
      for (let host of MIRROR_HOSTS) {
        let u = host + pathPart;
        if (u !== primary && urls.indexOf(u) < 0) {
          urls.push(u);
        }
      }
    }
    return urls;
  }

  /** 下载头图到本地（一次，失败忽略；不阻塞章节下载） */
  private async ensureCover(task: DownloadTask): Promise<void> {
    try {
      if (!task.coverLocal || task.coverLocal.length === 0) {
        task.coverLocal = this.coverPath(task.comicId);
      }
      if (this.exists(task.coverLocal) || !task.coverUrl || task.coverUrl.length === 0) {
        return;
      }
      this.ensureDir(this.comicDir(task.comicId));
      let urls: string[] = [task.coverUrl];
      let idx = task.coverUrl.indexOf('/static/');
      if (idx > 0) {
        let pathPart = task.coverUrl.substring(idx);
        for (let host of MIRROR_HOSTS) {
          let u = host + pathPart;
          if (u !== task.coverUrl && urls.indexOf(u) < 0) {
            urls.push(u);
          }
        }
      }
      let bytes = await ImageLoader.downloadBytes(urls);
      let file = fs.openSync(task.coverLocal, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes);
      fs.closeSync(file.fd);
    } catch (err) {
      console.warn('[DownloadManager] cover failed');
    }
  }

  // ─────────────── 一话一条进度通知 ───────────────

  /** 通知 id：comicId + order 的稳定哈希（保证同一话始终是同一条通知） */
  private notifyId(comicId: string, order: number): number {
    let s: string = comicId + '#' + order;
    let h: number = 0;
    for (let i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) % 2147483647;
    }
    return NOTIFY_ID_BASE + (h % NOTIFY_ID_RANGE);
  }

  /**
   * 是否允许发通知：
   * - 已允许 → true；
   * - 未允许且本会话没弹过 → requestEnableNotification 弹一次；
   * - 用户拒绝 / 弹窗失败 → 置为降级态，之后只走应用内进度，不再报错、不崩溃。
   */
  private async ensureNotifyAllowed(): Promise<boolean> {
    if (this.notifyState === 1) {
      return true;
    }
    if (this.notifyState === 2) {
      return false;
    }
    try {
      if (await notificationManager.isNotificationEnabled()) {
        this.notifyState = 1;
        return true;
      }
    } catch (err) {
      // 查询失败按未授权处理
    }
    if (!this.notifyAsked) {
      this.notifyAsked = true;
      let ctx = this.abilityContext();
      if (ctx) {
        try {
          await notificationManager.requestEnableNotification(ctx);
        } catch (err) {
          // 用户拒绝：降级，不抛错、不崩溃
        }
      }
    }
    try {
      if (await notificationManager.isNotificationEnabled()) {
        this.notifyState = 1;
        return true;
      }
    } catch (err) {
      // 仍不可用：降级
    }
    this.notifyState = 2;
    console.info('[DownloadManager] notification disabled, in-app progress only');
    return false;
  }

  /** 系统下载进度模板是否可用（模板由系统渲染进度条） */
  private async templateSupported(): Promise<boolean> {
    if (this.templateState === 1) {
      return true;
    }
    if (this.templateState === 2) {
      return false;
    }
    try {
      let ok: boolean = await notificationManager.isSupportTemplate(NOTIFY_TEMPLATE);
      this.templateState = ok ? 1 : 2;
      return ok;
    } catch (err) {
      this.templateState = 2;
      return false;
    }
  }

  /** 一话通知正文：'第 N 话 x/y'（不含作品名） */
  private notifyText(task: DownloadTask): string {
    let total: number = task.total > 0 ? task.total : 0;
    let current: number = task.progress > 0 ? task.progress : 0;
    if (total > 0 && current > total) {
      current = total;
    }
    let text: string = '第 ' + task.chapterOrder + ' 话';
    if (total > 0) {
      text = text + ' ' + current + '/' + total;
    }
    return text;
  }

  /**
   * 通知请求体（同一话固定 id，重新 publish 即原地刷新）。
   *
   * 文案：title + '第 N 话 x/y'，不含作品名与其它应用名。
   * 进度条：系统预置的 downloadTemplate（progressValue 为百分比），
   * 这是三方应用可用的进度渲染通道；NotificationBasicContent 上的
   * progress(maxValue/currentValue/isPercentage) 只存在于 systemLiveView 内容里，
   * 而三方应用不能直接创建实况窗通知，故不采用。
   * autoDeleteMs > 0 时写 autoDeletedTime：终态通知展示几秒后自动消失。
   */
  private buildNotification(task: DownloadTask, withTemplate: boolean,
    title: string = NOTIFY_TITLE, autoDeleteMs: number = 0): notificationManager.NotificationRequest {
    let text: string = this.notifyText(task);
    let normal: notificationManager.NotificationBasicContent = {
      title: title,
      text: text
    };
    let content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: normal
    };
    let request: notificationManager.NotificationRequest = {
      id: this.notifyId(task.comicId, task.chapterOrder),
      groupName: NOTIFY_GROUP,
      content: content
    };
    if (autoDeleteMs > 0) {
      request.autoDeletedTime = Date.now() + autoDeleteMs;
    }
    if (withTemplate && task.total > 0) {
      let percent: number = Math.round(task.progress * 100 / task.total);
      if (percent < 0) {
        percent = 0;
      }
      if (percent > 100) {
        percent = 100;
      }
      let data: Record<string, Object> = {
        'title': title,
        'fileName': text,
        'progressValue': percent
      };
      let template: notificationManager.NotificationTemplate = {
        name: NOTIFY_TEMPLATE,
        data: data
      };
      request.template = template;
    }
    return request;
  }

  /** 通知 IPC 串行队列：cancel / 终态一定排在之前的进度 publish 之后 */
  private enqueueNotify(op: () => Promise<void>): void {
    this.notifyQueue = this.notifyQueue.then(op).catch(() => {});
  }

  /**
   * 发布 / 刷新一话的进度通知。
   * force=true 用于「开始 / 拿到总页数」，其余进度更新走节流，
   * 避免每下载一页就刷一次系统通知。
   */
  private publishProgress(task: DownloadTask, force: boolean): void {
    let now = Date.now();
    if (!force && now - this.lastNotifyAt < NOTIFY_MIN_INTERVAL) {
      this.notifyDirty = true;
      if (this.notifyTimer < 0) {
        this.notifyTimer = setTimeout(() => {
          this.notifyTimer = -1;
          this.flushProgressNotify();
        }, NOTIFY_MIN_INTERVAL);
      }
      return;
    }
    this.lastNotifyAt = now;
    this.notifyDirty = false;
    this.doPublish(task);
  }

  /** 节流窗口到期：把当前仍在下载的话各刷新一条 */
  private flushProgressNotify(): void {
    if (!this.notifyDirty) {
      return;
    }
    this.notifyDirty = false;
    this.lastNotifyAt = Date.now();
    for (let t of this.tasks) {
      if (t.status === 'downloading') {
        this.doPublish(t);
      }
    }
  }

  private doPublish(task: DownloadTask): void {
    // 已完成 / 已失败 / 已删除的话不再补发（节流回调可能晚于状态变更）
    if (this.tasks.indexOf(task) < 0 || task.status !== 'downloading') {
      return;
    }
    let key = this.pageKey(task.comicId, task.chapterOrder);
    let epoch = this.notifyEpoch.get(key) ?? 0;
    this.ensureNotifyAllowed().then((allowed: boolean) => {
      if (!allowed) {
        return;
      }
      this.templateSupported().then((withTemplate: boolean) => {
        this.enqueueNotify(() => {
          // 轮到执行时再校验：异步等待期间该话已完成 / 已取消 / 已删除就丢弃，
          // 否则会在取消或终态之后又补一条「正在下载」的残留通知
          if ((this.notifyEpoch.get(key) ?? 0) !== epoch
            || this.tasks.indexOf(task) < 0 || task.status !== 'downloading') {
            return Promise.resolve();
          }
          let request = this.buildNotification(task, withTemplate);
          return notificationManager.publish(request).then(() => {
            // 只打话数与页数：不含作品名等敏感信息
            console.info('[DownloadManager] progress notify chapter=' + task.chapterOrder
              + ' ' + task.progress + '/' + task.total + ' template=' + withTemplate
              + ' id=' + request.id);
          }).catch((err: BusinessError) => {
            console.warn('[DownloadManager] publish notification failed: code=' + err.code);
            // 发布失败（权限被回收等）：下次重新探测授权状态
            this.notifyState = 0;
          });
        });
      }).catch(() => {});
    }).catch(() => {});
  }

  /**
   * 终态通知：一话完成 / 失败时把同一条通知更新为「下载完成 / 下载失败」，
   * 并在 NOTIFY_FINAL_KEEP_MS 后自动消失（另留兜底 cancel），
   * 不再停留在「正在下载」。
   */
  private publishFinal(task: DownloadTask, title: string): void {
    let key = this.pageKey(task.comicId, task.chapterOrder);
    // 世代号 +1：作废所有在途的进度补发，避免终态被「正在下载」反向覆盖
    let epoch = (this.notifyEpoch.get(key) ?? 0) + 1;
    this.notifyEpoch.set(key, epoch);
    this.enqueueNotify(() => {
      if ((this.notifyEpoch.get(key) ?? 0) !== epoch) {
        return Promise.resolve();
      }
      return this.ensureNotifyAllowed().then((allowed: boolean) => {
        if (!allowed) {
          return;
        }
        return this.templateSupported().then((withTemplate: boolean) => {
          let request = this.buildNotification(task, withTemplate, title, NOTIFY_FINAL_KEEP_MS);
          return notificationManager.publish(request).then(() => {
            console.info('[DownloadManager] notify final chapter=' + task.chapterOrder
              + ' ' + task.progress + '/' + task.total + ' id=' + request.id);
          }).catch((err: BusinessError) => {
            console.warn('[DownloadManager] publish final notification failed: code=' + err.code);
          });
        });
      });
    });
    // 兜底：系统未按 autoDeletedTime 清除时再主动撤掉
    // （期间若有新动作会改世代号，此时不动它）
    this.scheduleAutoCancel(task, NOTIFY_FINAL_KEEP_MS + 2000, epoch);
  }

  /** 暂停态通知（仅 WiFi 断开等暂停场景）：保留进度、不自动消失 */
  private publishPaused(task: DownloadTask): void {
    let key = this.pageKey(task.comicId, task.chapterOrder);
    let epoch = this.notifyEpoch.get(key) ?? 0;
    this.enqueueNotify(() => {
      if ((this.notifyEpoch.get(key) ?? 0) !== epoch) {
        return Promise.resolve();
      }
      return this.ensureNotifyAllowed().then((allowed: boolean) => {
        if (!allowed) {
          return;
        }
        return this.templateSupported().then((withTemplate: boolean) => {
          let request = this.buildNotification(task, withTemplate, NOTIFY_PAUSE_TITLE, 0);
          return notificationManager.publish(request).then(() => {
            console.info('[DownloadManager] notify paused chapter=' + task.chapterOrder);
          }).catch((err: BusinessError) => {
            // 忽略：暂停提示失败不影响续传
          });
        });
      });
    });
  }

  /** 定时兜底取消：仅当期间没有新的发布 / 取消（世代号未变）时才执行 */
  private scheduleAutoCancel(task: DownloadTask, delayMs: number, epoch: number): void {
    let key = this.pageKey(task.comicId, task.chapterOrder);
    setTimeout(() => {
      if ((this.notifyEpoch.get(key) ?? 0) !== epoch) {
        return;
      }
      this.notifyEpoch.set(key, epoch + 1);
      this.enqueueCancel(task);
    }, delayMs);
  }

  /** 撤掉一话的通知（删除 / 重试 / 兜底收尾） */
  private cancelProgress(task: DownloadTask): void {
    let key = this.pageKey(task.comicId, task.chapterOrder);
    this.notifyEpoch.set(key, (this.notifyEpoch.get(key) ?? 0) + 1);
    this.enqueueCancel(task);
  }

  private enqueueCancel(task: DownloadTask): void {
    let id = this.notifyId(task.comicId, task.chapterOrder);
    this.enqueueNotify(() => {
      return notificationManager.cancel(id).then(() => {
        console.info('[DownloadManager] notify cancelled chapter=' + task.chapterOrder);
      }).catch((err: BusinessError) => {
        // 通知可能已被用户清掉：忽略
      });
    });
  }

  /** 清空所有话的通知（清空下载 / 应用启动清理上次残留） */
  private cancelAllProgress(): void {
    this.notifyEpoch.clear();
    this.enqueueNotify(() => {
      return notificationManager.cancelGroup(NOTIFY_GROUP).then(() => {
        console.info('[DownloadManager] notify group cleared');
      }).catch((err: BusinessError) => {
        // 没有对应分组 / 已清空：忽略
      });
    });
  }

  // ─────────────── 长时任务（DATA_TRANSFER） ───────────────

  /** 是否应该保持长时任务：有在跑的话，或有可派发的等待话 */
  private shouldKeepRunning(): boolean {
    if (this.activeCount > 0) {
      return true;
    }
    if (this.tasks.some(t => t.status === 'downloading')) {
      return true;
    }
    if (this.wifiOnly && !this.isWifiNow()) {
      return false;
    }
    return this.tasks.some(t => t.status === 'waiting');
  }

  /** 按当前任务状态对齐长时任务：有下载启，全部结束 / 失败 / 等待 WiFi 停 */
  private syncContinuousTask(): void {
    if (!this.ready) {
      return;
    }
    if (this.shouldKeepRunning()) {
      if (!this.continuousRunning && !this.continuousStarting) {
        this.startContinuousTask();
      }
    } else if (this.continuousRunning) {
      this.stopContinuousTask();
    }
  }

  /** 构造长时任务通知点击后要跳转的目标（系统据此生成常驻通知） */
  private async buildWantAgent(ctx: common.UIAbilityContext): Promise<WantAgent | null> {
    if (this.wantAgentObj) {
      return this.wantAgentObj;
    }
    try {
      let info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: ctx.abilityInfo.bundleName,
            abilityName: ctx.abilityInfo.name
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      let agent: WantAgent = await wantAgent.getWantAgent(info);
      this.wantAgentObj = agent;
      return agent;
    } catch (err) {
      let be = err as BusinessError;
      console.warn('[DownloadManager] getWantAgent failed: code=' + be.code);
      return null;
    }
  }

  private startContinuousTask(): void {
    let ctx = this.abilityContext();
    if (!ctx) {
      return;
    }
    this.continuousStarting = true;
    this.buildWantAgent(ctx).then((agent: WantAgent | null) => {
      if (!agent) {
        this.continuousStarting = false;
        return;
      }
      backgroundTaskManager.startBackgroundRunning(ctx,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent).then(() => {
        this.continuousRunning = true;
        console.info('[DownloadManager] continuous task started');
      }).catch((err: BusinessError) => {
        console.warn('[DownloadManager] continuous task start failed: code=' + err.code);
      }).finally(() => {
        this.continuousStarting = false;
      });
    }).catch(() => {
      this.continuousStarting = false;
    });
  }

  private stopContinuousTask(): void {
    this.continuousRunning = false;
    let ctx = this.abilityContext();
    if (!ctx) {
      return;
    }
    backgroundTaskManager.stopBackgroundRunning(ctx).then(() => {
      console.info('[DownloadManager] continuous task stopped');
    }).catch((err: BusinessError) => {
      console.warn('[DownloadManager] continuous task stop failed: code=' + err.code);
    });
  }

  // ─────────────── 持久化 ───────────────

  private persist(): void {
    this.cacheInstance().then(cache => {
      cache.saveDownloadTasks(JSON.stringify(this.tasks));
    }).catch(() => {});
  }

  private async load(reset: boolean = false): Promise<void> {
    if (this.loaded) {
      return;
    }
    if (!this.abilityContext()) {
      // 上下文尚不可用：稍后重试（init 注入后也会再调用一次）
      if (this.loadTimer < 0) {
        this.loadTimer = setTimeout(() => {
          this.loadTimer = -1;
          this.load();
        }, 300);
      }
      return;
    }
    this.loaded = true;
    if (reset) {
      this.tasks = [];
    }
    try {
      let cache = await this.cacheInstance();
      let raw = cache.loadDownloadTasks();
      if (raw) {
        try {
          let loaded = JSON.parse(raw) as DownloadTask[];
          // 合并：不覆盖运行中新增的任务（竞态保护）
          for (let t of loaded) {
            let existing = this.tasks.find(x => x.comicId === t.comicId && x.chapterOrder === t.chapterOrder);
            if (existing) {
              continue;
            }
            // 旧版本任务补齐新字段
            t.coverLocal = t.coverLocal ?? '';
            t.description = t.description ?? '';
            t.author = t.author ?? '';
            t.sizeBytes = t.sizeBytes ?? 0;
            t.progress = t.progress ?? 0;
            t.total = t.total ?? 0;
            // 目录字段缺失 / 为空的老数据按旧命名规则补齐
            if (!t.dir || t.dir.length === 0) {
              t.dir = this.chapterDir(t.comicId, t.chapterOrder);
            }
            if (!t.coverLocal || t.coverLocal.length === 0) {
              t.coverLocal = this.coverPath(t.comicId);
            }
            // 中断态一律回队列续传
            if (t.status === 'downloading' || t.status === 'failed') {
              t.status = 'waiting';
            }
            if (t.status === 'completed' && t.total > 0) {
              // 按磁盘实际情况校正；被清理 / 0 字节的按未完成处理
              let done = this.countExistingPages(t);
              if (done >= t.total) {
                t.progress = t.total;
                t.sizeBytes = this.calcDirSize(t.dir);
              } else {
                t.status = 'waiting';
                t.progress = done;
              }
            }
            this.tasks.push(t);
          }
        } catch (e) {
          // 解析失败保留现有任务
        }
      }
      // 设置恢复：仅 WiFi / 并发数从持久化读回
      this.wifiOnly = cache.getSetting('wifi_only', 'false') === 'true';
      AppStorage.setOrCreate('bika_download_wifi_only', this.wifiOnly);
      let savedConcurrent = parseInt(cache.getSetting('concurrent', '1'));
      if (savedConcurrent >= 1 && savedConcurrent <= 5) {
        this.maxConcurrent = savedConcurrent;
      }
      AppStorage.setOrCreate('bika_download_concurrent', this.maxConcurrent);
      // 启动先清掉上次会话残留的进度 / 终态通知（本话续传时会重新发布）
      this.cancelAllProgress();
      // 启动恢复：未完成的任务重新入队（按剩余文件续传）
      this.notify();
      this.startNext();
    } catch (err) {
      let e = err as Error;
      console.warn('[DownloadManager] load failed: ' + e.message);
    }
  }
}
