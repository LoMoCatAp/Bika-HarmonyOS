import { fileIo as fs } from '@kit.CoreFileKit';
import { connection } from '@kit.NetworkKit';
import { ApiService } from '../network/ApiService';
import { ImageLoader } from './ImageLoader';
import { CacheManager } from './CacheManager';
import { buildImageUrl } from '../models/Comic';

/**
 * 下载任务（漫画 + 章节 + 进度）
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
 * 下载管理器：串行队列 + 逐页下载 + 本地文件 + 持久化
 */
export class DownloadManager {
  private static instance: DownloadManager | null = null;
  private tasks: DownloadTask[] = [];
  /** 进行中的任务数（并发控制） */
  private activeCount: number = 0;
  /** 派发锁（防止并发调用重复派发同一任务） */
  private dispatching: boolean = false;
  /** 仅 WiFi 下载 */
  private wifiOnly: boolean = false;
  /** 最大并发数（1~5） */
  private maxConcurrent: number = 1;
  private netListenerRegistered: boolean = false;
  private listeners: Array<(tasks: DownloadTask[]) => void> = [];
  private apiService: ApiService = ApiService.getInstance();

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

  /** 仅 WiFi 下载开关 */
  setWifiOnly(only: boolean): void {
    this.wifiOnly = only;
    AppStorage.setOrCreate('bika_download_wifi_only', only);
    this.notify();
    if (!only) {
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
    this.startNext();
  }

  getMaxConcurrent(): number {
    return this.maxConcurrent;
  }

  /** 当前是否连接 WiFi */
  isWifiNow(): boolean {
    try {
      let net = connection.getDefaultNetSync();
      let caps = connection.getNetCapabilitiesSync(net);
      if (caps && caps.bearerTypes) {
        return caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
      }
    } catch (err) {
      // 无网络或查询失败按非 WiFi 处理
    }
    return false;
  }

  /** WiFi 轮询：开启仅 WiFi 下载后，定时检测网络恢复并自动续传 */
  private startWifiPoll(): void {
    if (this.netListenerRegistered) {
      return;
    }
    this.netListenerRegistered = true;
    setInterval(() => {
      if (this.wifiOnly && this.isWifiNow()) {
        let hasWaiting = this.tasks.some(t => t.status === 'waiting');
        if (hasWaiting) {
          this.startNext();
        }
      }
    }, 10000);
  }

  getTasks(): DownloadTask[] {
    // 返回浅拷贝：确保 @State 引用变化触发 UI 实时刷新
    return this.tasks.slice();
  }

  hasTask(comicId: string, order: number): DownloadTask | undefined {
    return this.tasks.find(t => t.comicId === comicId && t.chapterOrder === order);
  }

  /** 添加下载任务（去重；同步入队，后台串行下载） */
  addTask(comicId: string, title: string, coverUrl: string, description: string, author: string, order: number, chapterTitle: string): void {
    if (this.hasTask(comicId, order)) {
      return;
    }
    let dir = getContext().filesDir + '/bika_download/' + comicId + '/' + order;
    let task: DownloadTask = {
      comicId: comicId,
      comicTitle: title,
      coverUrl: coverUrl,
      coverLocal: getContext().filesDir + '/bika_download/' + comicId + '/cover.jpg',
      description: description,
      author: author,
      chapterOrder: order,
      chapterTitle: chapterTitle,
      status: 'waiting',
      progress: 0,
      total: 0,
      dir: dir,
      sizeBytes: 0
    };
    this.tasks.push(task);
    this.persist();
    this.notify();
    this.startNext();
  }

  /** 删除任务与本地文件 */
  deleteTask(comicId: string, order: number): void {
    let idx = this.tasks.findIndex(t => t.comicId === comicId && t.chapterOrder === order);
    if (idx < 0) {
      return;
    }
    let dir = this.tasks[idx].dir;
    this.tasks.splice(idx, 1);
    this.persist();
    this.notify();
    try {
      fs.rmdirSync(dir);
    } catch (err) {
      console.warn('[DownloadManager] rmdir failed: ' + JSON.stringify(err));
    }
  }

  /** 队列泵：按最大并发数派发等待中的任务（bika 同款并发下载） */
  private async startNext(): Promise<void> {
    if (this.dispatching) {
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
        this.execute(task).finally(() => {
          this.activeCount--;
          this.startNext();
        });
      }
    } finally {
      this.dispatching = false;
    }
  }

  /** 重试失败任务 */
  retryTask(comicId: string, order: number): void {
    let task = this.tasks.find(t => t.comicId === comicId && t.chapterOrder === order);
    if (task && task.status === 'failed') {
      task.status = 'waiting';
      this.persist();
      this.notify();
      this.startNext();
    }
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

  /** 清空全部下载任务与本地文件 */
  clearAll(): void {
    for (let t of this.tasks) {
      try {
        fs.rmdirSync(t.dir);
      } catch (err) {
        console.warn('[DownloadManager] rmdir failed: ' + JSON.stringify(err));
      }
    }
    this.tasks = [];
    this.persist();
    this.notify();
  }

  /** 下载头图到本地（一次，失败忽略） */
  private async ensureCover(task: DownloadTask): Promise<void> {
    try {
      if (fs.accessSync(task.coverLocal)) {
        return;
      }
      if (!task.coverUrl || task.coverUrl.length === 0) {
        return;
      }
      let comicDir = task.dir.substring(0, task.dir.lastIndexOf('/'));
      this.ensureDir(comicDir);
      let urls: string[] = [task.coverUrl];
      let idx = task.coverUrl.indexOf('/static/');
      if (idx > 0) {
        let pathPart = task.coverUrl.substring(idx);
        for (let host of ['https://s3.go2778.com', 'https://storage-b.go2778.com', 'https://img.go2778.com']) {
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
      console.warn('[DownloadManager] cover failed: ' + JSON.stringify(err));
    }
  }

  /** 执行下载：拉取章节页 → 逐页下载写文件 */
  private async execute(task: DownloadTask): Promise<void> {
    task.status = 'downloading';
    task.progress = 0;
    this.notify();
    try {
      await this.ensureCover(task);
      let pages = await this.apiService.getChapterPages(task.comicId, task.chapterOrder);
      task.total = pages.length;
      this.notify();
      // 逐级创建目录
      let base = getContext().filesDir + '/bika_download';
      let comicDir = base + '/' + task.comicId;
      this.ensureDir(base);
      this.ensureDir(comicDir);
      this.ensureDir(task.dir);

      for (let i = 0; i < pages.length; i++) {
        let media = pages[i].media;
        let primary = buildImageUrl(media);
        let urls: string[] = [primary];
        // 镜像候选
        let idx = primary.indexOf('/static/');
        if (idx > 0) {
          let pathPart = primary.substring(idx);
          for (let host of ['https://s3.go2778.com', 'https://storage-b.go2778.com', 'https://img.go2778.com']) {
            let u = host + pathPart;
            if (u !== primary && urls.indexOf(u) < 0) {
              urls.push(u);
            }
          }
        }
        let bytes = await ImageLoader.downloadBytes(urls);
        let file = fs.openSync(task.dir + '/' + i + '.jpg', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, bytes);
        fs.closeSync(file.fd);
        task.progress = i + 1;
        this.notify();
        // 节流持久化：每 5 页落盘一次，中断后可恢复进度
        if (i % 5 === 0 || i === pages.length - 1) {
          this.persist();
        }
      }
      task.status = 'completed';
      task.sizeBytes = this.calcDirSize(task.dir);
    } catch (err) {
      task.status = 'failed';
      console.error('[DownloadManager] download failed: ' + JSON.stringify(err));
    }
    this.persist();
    this.notify();
  }

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

  private ensureDir(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (err) {
      try {
        fs.mkdirSync(dir);
      } catch (err2) {
        console.warn('[DownloadManager] mkdir failed: ' + JSON.stringify(err2));
      }
    }
  }

  /** 持久化（Preferences JSON） */
  private persist(): void {
    CacheManager.getInstance().then(cache => {
      cache.saveDownloadTasks(JSON.stringify(this.tasks));
    }).catch(() => {});
  }

  private load(): void {
    CacheManager.getInstance().then(cache => {
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
            if (t.status === 'downloading') {
              t.status = 'failed';
            }
            if (t.status === 'completed' && t.total > 0) {
              try {
                if (!fs.accessSync(t.dir + '/' + (t.total - 1) + '.jpg')) {
                  t.status = 'failed';
                }
              } catch (err) {
                t.status = 'failed';
              }
            }
            this.tasks.push(t);
          }
        } catch {
          // 解析失败保留现有任务
        }
      }
      // 启动恢复：上次未完成的任务重新入队（串行启动续传）
      for (let t of this.tasks) {
        if (t.status === 'failed' || t.status === 'downloading') {
          t.status = 'waiting';
        }
      }
      this.notify();
      this.startNext();
    }).catch(() => {});
  }

  /** 订阅任务变化（回调立即获得最新列表） */
  subscribe(cb: (tasks: DownloadTask[]) => void): void {
    this.listeners.push(cb);
    cb(this.tasks.slice());
  }

  unsubscribe(cb: (tasks: DownloadTask[]) => void): void {
    let idx = this.listeners.indexOf(cb);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /** 通知 UI：直接回调订阅者（实时刷新） */
  notify(): void {
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
}