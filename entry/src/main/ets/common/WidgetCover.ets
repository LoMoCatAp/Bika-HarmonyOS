import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BikaHttpClient } from '../network/BikaHttpClient';
import { IMAGE_HOST_POOL } from './Constants';

const DOMAIN = 0x0000;
const TAG = 'WidgetCover';

/**
 * 桌面卡片封面下发（formImages）统一实现
 *
 * 官方依据（OpenHarmony Form Kit / 刷新本地图片和网络图片）：
 * - ArkTS 卡片 Image 组件不支持 http(s) 直连图片，必须由 FormExtensionAbility
 *   把图片下载到应用沙箱并打开 fd，再通过 formBindingData.createFormBindingData
 *   的顶层 formImages 字段下发：{ formImages: { key1: fd1, key2: fd2 } }；
 * - 卡片侧按官方约定用 Image('memory://' + key) 渲染；
 * - 官方注意事项：Image 组件以入参字符串是否变化来决定是否刷新，
 *   所以每次刷新生成的 key 必须不同 —— 本类用 前缀 + 下标 + 时间戳 + 自增序号 保证唯一。
 *
 * 约束（与实现严格一致）：
 * - 全局并发上限 MAX_CONCURRENCY = 4：五张卡共享同一个闸门，任意时刻最多 4 张封面在下载；
 * - 单次尝试超时 TIMEOUT_MS = 1000ms，同一路径最多尝试 MAX_CANDIDATES = 2 个镜像；
 * - 整批下载总预算 BATCH_BUDGET_MS = 3000ms：到点立即收尾，超预算的结果直接丢弃，
 *   保证 FormExtensionAbility 远早于 10s 生命周期上限结束；
 * - 原生请求超时收进 1~2 秒（NATIVE_CONNECT_TIMEOUT_MS / NATIVE_READ_TIMEOUT_MS），
 *   避免 JS 已放弃而底层 connect 30s / read 60s 还挂着；
 * - 同一封面 URL 命中沙箱缓存后不再重复下载（缓存文件名 = URL 稳定哈希，存放于 cacheDir）；
 * - 单张超过 MAX_BYTES（1.5MB，官方单图上限 2MB）直接跳过，失败降级为占位；
 * - fd 不在 updateForm 之后立刻关闭：进程内保留到该卡片下一次刷新成功后再延迟释放，
 *   避免卡片渲染期间句柄失效；进程退出时由系统统一释放。
 */

/** 单张封面的下载请求 */
export class WidgetCoverRequest {
  /** 业务侧标识（作品 id），用于把结果映射回列表项 */
  bizKey: string = '';
  /** http(s) 封面地址 */
  url: string = '';
}

/** 一批封面的下载结果 */
export class WidgetCoverBundle {
  /** 交给 createFormBindingData 的 formImages：memory:// key → 文件 fd */
  images: Record<string, number> = {};
  /** 已打开的文件句柄（保持打开直到 release） */
  files: fileIo.File[] = [];
  /** 批次已收尾（超预算 / 已废弃）：迟到的下载结果必须立刻关闭 fd，不能再挂到卡片上 */
  closed: boolean = false;
  private mapping: Map<string, string> = new Map();

  /** 记录一个成功下载的封面；批次已收尾时立刻关闭 fd，避免泄漏 */
  put(bizKey: string, memKey: string, fd: number, file: fileIo.File): void {
    if (this.closed) {
      try {
        fileIo.closeSync(file);
      } catch (err) {
        // 已关闭 / 句柄失效：忽略
      }
      return;
    }
    this.images[memKey] = fd;
    this.mapping.set(bizKey, memKey);
    this.files.push(file);
  }

  /** 业务 key → memory:// key；没有则返回空串（卡片显示占位） */
  coverKeyOf(bizKey: string): string {
    let v: string | undefined = this.mapping.get(bizKey);
    return v === undefined ? '' : v;
  }

  hasFiles(): boolean {
    return this.files.length > 0;
  }
}

/**
 * 带封面的绑定数据基类。
 * formImages 必须是被交给 formBindingData.createFormBindingData 的对象的顶层字段且不可改名。
 */
export class WidgetCoverFormData {
  formImages: Record<string, number> = {};
  /** fd 句柄令牌；由 WidgetCover.attach 写入，之后用 releaseFormData 释放 */
  coverToken: string = '';
}

/** 并发游标（ArkTS 里跨 worker 共享可变状态需要对象包一层） */
class WidgetCoverCursor {
  value: number = 0;
  /** 批次是否已废弃（超预算）：worker 见到后立即收尾 */
  aborted: boolean = false;
  /** 命中沙箱缓存（未重复下载）的数量 */
  cacheHits: number = 0;
  /** 真正发起下载并成功的数量 */
  downloads: number = 0;
}

/** 单次下载尝试：候选 URL + 是否强制 HTTP/1.1（P2-2 降级重试） */
class WidgetCoverAttempt {
  url: string = '';
  http1: boolean = false;
}

export class WidgetCover {
  /**
   * 全局并发上限：五张卡共享同一个闸门，任意时刻最多 4 张封面在下载，
   * 避免 20 张封面同时抢同一个 HTTP 客户端。FormExtensionAbility 生命周期只有 10s，
   * 超过预算的部分由 BATCH_BUDGET_MS 强制收尾。
   */
  static readonly MAX_CONCURRENCY: number = 4;
  /** 单张封面的单次尝试超时（毫秒）：必须给「取数 + 下载 + updateForm」留足余量 */
  static readonly TIMEOUT_MS: number = 1000;
  /**
   * 同一路径最多尝试几个镜像站。
   * 实测不同接口给出的 fileServer 不一定都能直连（合辑/收藏返回的是裸文件名 + 另一个存储域），
   * 必须像主应用 ImageLoader 那样按镜像池回退，否则封面永远下不来。
   */
  static readonly MAX_CANDIDATES: number = 2;
  /** 单张封面大小上限（官方单图 2MB，这里留安全余量） */
  static readonly MAX_BYTES: number = 1500 * 1024;
  /** 一批封面下载的总预算（毫秒）：到点立即返回，保证扩展远早于 10s 结束 */
  static readonly BATCH_BUDGET_MS: number = 3000;
  /** 卡片专用原生 connect 超时（毫秒）：JS 层 1s 就放弃，底层不能挂着 30s */
  static readonly NATIVE_CONNECT_TIMEOUT_MS: number = 1500;
  /** 卡片专用原生 read 超时（毫秒） */
  static readonly NATIVE_READ_TIMEOUT_MS: number = 2000;
  /** 进程内保留的 fd 令牌上限：超过按插入顺序（最旧优先）释放，兜底防泄漏 */
  static readonly MAX_OPEN_TOKENS: number = 16;

  private static readonly FILE_PREFIX: string = 'wcover';
  private static readonly MAX_KEEP_FILES: number = 48;
  private static seq: number = 0;
  /** token → 保持打开的句柄 */
  private static openFiles: Map<string, fileIo.File[]> = new Map();
  /** token 插入顺序，用于超出上限时按最旧优先释放 */
  private static openOrder: string[] = [];
  /** 全局并发闸：正在下载的数量 */
  private static activeDownloads: number = 0;
  /** 全局并发闸：等待槽位的 worker */
  private static waitingSlots: (() => void)[] = [];

  /**
   * 并发下载一批封面到沙箱临时目录并打开 fd。
   * 任何单张失败都只影响自己（对应的 coverKey 为空串），绝不抛异常。
   */
  static async prepare(requests: WidgetCoverRequest[], ctx?: Context): Promise<WidgetCoverBundle> {
    let bundle = new WidgetCoverBundle();
    try {
      if (ctx === undefined || ctx === null) {
        return bundle;
      }
      let dir: string = WidgetCover.workDirOf(ctx);
      if (dir.length === 0) {
        return bundle;
      }
      // P2-5：无论本次是否需要下载封面，刷新入口都清理一次缓存目录
      WidgetCover.cleanup(dir);
      if (requests.length === 0) {
        return bundle;
      }
      let cursor = new WidgetCoverCursor();
      let workers: Promise<void>[] = [];
      let n: number = requests.length < WidgetCover.MAX_CONCURRENCY
        ? requests.length : WidgetCover.MAX_CONCURRENCY;
      for (let i = 0; i < n; i++) {
        workers.push(WidgetCover.worker(requests, cursor, bundle, dir));
      }
      // P0-1(c)：整批总预算。到点把批次标记为已废弃并立即返回，
      // 迟到的下载结果由 put 关闭 fd，不会再挂到卡片上。
      let timerId: number = -1;
      let budget: Promise<void> = new Promise<void>((resolve: () => void) => {
        timerId = setTimeout(() => {
          cursor.aborted = true;
          bundle.closed = true;
          hilog.warn(DOMAIN, TAG, 'cover batch budget exceeded covers=%{public}d',
            Object.keys(bundle.images).length);
          resolve();
        }, WidgetCover.BATCH_BUDGET_MS);
      });
      await Promise.race([Promise.all(workers), budget]);
      if (timerId >= 0) {
        clearTimeout(timerId);
      }
      hilog.info(DOMAIN, TAG, 'cover batch reqs=%{public}d hits=%{public}d downloads=%{public}d covers=%{public}d',
        requests.length, cursor.cacheHits, cursor.downloads, Object.keys(bundle.images).length);
    } catch (err) {
      console.warn('[WidgetCover] prepare failed: ' + JSON.stringify(err));
    }
    return bundle;
  }

  /**
   * 封面缓存目录。
   * 关键：**不能用 ctx.tempDir** —— FormExtensionAbility 的 tempDir 是每次进程启动都会变化的
   * 随机目录（设备上实测形如 temp_useless<随机>），进程结束即被系统清理，
   * URL 到沙箱文件的缓存根本无法跨刷新复用。ctx.cacheDir 稳定（应用升级也保留），
   * 所以封面缓存与清理都放在这里；目录名统一带 wcover 前缀，避免误删其它缓存。
   */
  private static workDirOf(ctx: Context): string {
    let dir: string = ctx.cacheDir;
    if (dir === undefined || dir === null || dir.length === 0) {
      dir = ctx.tempDir;
    }
    if (dir === undefined || dir === null) {
      return '';
    }
    return dir;
  }

  /** 刷新入口调用：无论是否需要下载封面都清理沙箱里的 wcover 缓存文件（P2-5） */
  static cleanupTemp(ctx?: Context): void {
    try {
      if (ctx === undefined || ctx === null) {
        return;
      }
      let dir: string = WidgetCover.workDirOf(ctx);
      if (dir.length === 0) {
        return;
      }
      WidgetCover.cleanup(dir);
    } catch (err) {
      // 目录不可读：忽略，不影响本次刷新
    }
  }

  /** 单个并发 worker：不断从游标领取下标，直到领完 */
  private static async worker(requests: WidgetCoverRequest[], cursor: WidgetCoverCursor,
    bundle: WidgetCoverBundle, dir: string): Promise<void> {
    while (cursor.value < requests.length) {
      if (cursor.aborted) {
        return;
      }
      let i: number = cursor.value;
      cursor.value = i + 1;
      let req: WidgetCoverRequest = requests[i];
      if (req === undefined || req === null || req.url.length === 0) {
        continue;
      }
      // P0-2：先查沙箱缓存（同一 URL 连续刷新不重复下载），命中直接开新 fd + 新 memory key
      let cachePath: string = WidgetCover.cachePathOf(dir, req.url);
      let cached: fileIo.File | null = WidgetCover.openCached(cachePath);
      if (cached !== null) {
        cursor.cacheHits++;
        WidgetCover.remember(cursor, bundle, req.bizKey, i, cached);
        continue;
      }
      // 环节 2：原地址 → 镜像池同路径 → 原地址强制 HTTP/1.1 重试一次（P2-2）
      let attempts: WidgetCoverAttempt[] = WidgetCover.attemptsOf(req.url);
      let bytes: ArrayBuffer | null = null;
      for (let ai = 0; ai < attempts.length; ai++) {
        if (cursor.aborted) {
          return;
        }
        await WidgetCover.acquireSlot();
        if (cursor.aborted) {
          WidgetCover.releaseSlot();
          return;
        }
        try {
          let buf: ArrayBuffer = await WidgetCover.fetchWithTimeout(attempts[ai].url, WidgetCover.TIMEOUT_MS,
            attempts[ai].http1);
          if (buf.byteLength > 0) {
            bytes = buf;
            break;
          }
        } catch (err) {
          // 该次尝试不可用，换下一次
        } finally {
          WidgetCover.releaseSlot();
        }
      }
      if (cursor.aborted) {
        return;
      }
      if (bytes === null) {
        hilog.warn(DOMAIN, TAG, 'download failed biz=%{public}s tried=%{public}d primary=%{public}s',
          req.bizKey, attempts.length, WidgetCover.hostOf(req.url));
        continue;
      }
      if (bytes.byteLength > WidgetCover.MAX_BYTES) {
        // 环节 2：超过官方单图上限（2MB）直接放弃，避免整批下发失败
        hilog.warn(DOMAIN, TAG, 'download too large biz=%{public}s bytes=%{public}d',
          req.bizKey, bytes.byteLength);
        continue;
      }
      WidgetCover.storeBytes(cursor, bundle, req, i, dir, bytes, cachePath);
    }
  }

  /** 缓存命中：重新打开一份 fd（memory key 每次必须变化，不能复用文件 fd） */
  private static openCached(path: string): fileIo.File | null {
    try {
      let st = fileIo.statSync(path);
      if (st.size <= 0 || st.size > WidgetCover.MAX_BYTES) {
        return null;
      }
      return fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    } catch (err) {
      // 缓存不存在 / 已损坏：走下载
      return null;
    }
  }

  /** 把一份已打开的封面文件挂到批次上（新 memory key） */
  private static remember(cursor: WidgetCoverCursor, bundle: WidgetCoverBundle,
    bizKey: string, index: number, file: fileIo.File): void {
    if (cursor.aborted) {
      try {
        fileIo.closeSync(file);
      } catch (err) {
        // 忽略
      }
      return;
    }
    WidgetCover.seq++;
    let memKey: string = WidgetCover.FILE_PREFIX + '_' + index + '_' + Date.now() + '_' + WidgetCover.seq;
    bundle.put(bizKey, memKey, file.fd, file);
  }

  /**
   * P1-2：把下载到的字节写进沙箱。
   * file 声明在 try 外，失败路径自己 closeSync + unlinkSync；并校验短写。
   */
  private static storeBytes(cursor: WidgetCoverCursor, bundle: WidgetCoverBundle,
    req: WidgetCoverRequest, index: number, dir: string, bytes: ArrayBuffer, cachePath: string): void {
    let tmpPath: string = dir + '/' + WidgetCover.FILE_PREFIX + '_tmp_' + Date.now() + '_' + WidgetCover.seq;
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(tmpPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      let written: number = fileIo.writeSync(file.fd, bytes);
      if (written !== bytes.byteLength) {
        // 短写会得到截断图片，视为失败并清理
        throw new Error('short write ' + written + '/' + bytes.byteLength);
      }
      // 覆盖缓存：先删旧目录项（已打开的 fd 仍指向旧 inode），再原子改名，避免截断正在渲染的文件
      try {
        fileIo.unlinkSync(cachePath);
      } catch (err) {
        // 旧缓存不存在：忽略
      }
      fileIo.renameSync(tmpPath, cachePath);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'cover write failed biz=%{public}s err=%{public}s',
        req.bizKey, JSON.stringify(err));
      if (file !== null) {
        try {
          fileIo.closeSync(file);
        } catch (e) {
          // 忽略
        }
        file = null;
      }
      try {
        fileIo.unlinkSync(tmpPath);
      } catch (e) {
        // 忽略
      }
      return;
    }
    if (file === null) {
      return;
    }
    if (cursor.aborted) {
      try {
        fileIo.closeSync(file);
      } catch (err) {
        // 忽略
      }
      return;
    }
    WidgetCover.seq++;
    let memKey: string = WidgetCover.FILE_PREFIX + '_' + index + '_' + Date.now() + '_' + WidgetCover.seq;
    cursor.downloads++;
    bundle.put(req.bizKey, memKey, file.fd, file);
  }

  /** 全局并发闸：占用一个槽位（五张卡共享） */
  private static async acquireSlot(): Promise<void> {
    if (WidgetCover.activeDownloads < WidgetCover.MAX_CONCURRENCY) {
      WidgetCover.activeDownloads++;
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      WidgetCover.waitingSlots.push(resolve);
    });
  }

  /** 全局并发闸：释放一个槽位（有等待者时直接转交，不减少计数） */
  private static releaseSlot(): void {
    let next: (() => void) | undefined = WidgetCover.waitingSlots.shift();
    if (next !== undefined) {
      next();
      return;
    }
    if (WidgetCover.activeDownloads > 0) {
      WidgetCover.activeDownloads--;
    }
  }

  /** 下载单张封面（带超时），失败 / 超时抛异常由调用方降级 */
  private static fetchWithTimeout(url: string, ms: number, http1Fallback: boolean): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve: (v: ArrayBuffer) => void, reject: (e: Error) => void) => {
      let settled: boolean = false;
      let timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('cover timeout'));
        }
      }, ms);
      let headers: Record<string, string> = { 'User-Agent': 'okhttp/3.8.1' };
      // 卡片专用短超时：JS 层 1s 就放弃，底层不允许挂 30s/60s
      BikaHttpClient.downloadBinaryWithTimeout(url, headers, '',
        WidgetCover.NATIVE_CONNECT_TIMEOUT_MS, WidgetCover.NATIVE_READ_TIMEOUT_MS, http1Fallback).then((buf: ArrayBuffer) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          resolve(buf);
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
   * 把本次下载的 fd 保留在进程内并写回绑定数据，返回令牌。
   * 调用方在 formProvider.updateForm 完成后用 releaseFormData 释放【上一次】的令牌。
   */
  static attach(data: WidgetCoverFormData, bundle: WidgetCoverBundle): void {
    data.formImages = bundle.images;
    if (!bundle.hasFiles()) {
      data.coverToken = '';
      return;
    }
    WidgetCover.seq++;
    let token: string = WidgetCover.FILE_PREFIX + '_t_' + Date.now() + '_' + WidgetCover.seq;
    WidgetCover.openFiles.set(token, bundle.files);
    WidgetCover.openOrder.push(token);
    WidgetCover.enforceOpenLimit();
    data.coverToken = token;
  }

  /** P1-1：保留令牌超过上限时，按最旧优先释放（兜底防 fd 泄漏） */
  private static enforceOpenLimit(): void {
    while (WidgetCover.openOrder.length > WidgetCover.MAX_OPEN_TOKENS) {
      let oldest: string | undefined = WidgetCover.openOrder.shift();
      if (oldest === undefined) {
        break;
      }
      WidgetCover.release(oldest);
    }
  }

  /** 释放某个令牌持有的全部 fd */
  static release(token: string): void {
    if (token === undefined || token === null || token.length === 0) {
      return;
    }
    let files: fileIo.File[] | undefined = WidgetCover.openFiles.get(token);
    if (files === undefined) {
      return;
    }
    for (let f of files) {
      try {
        fileIo.closeSync(f);
      } catch (err) {
        // 已关闭 / 句柄失效：忽略
      }
    }
    WidgetCover.openFiles.delete(token);
    let idx: number = WidgetCover.openOrder.indexOf(token);
    if (idx >= 0) {
      WidgetCover.openOrder.splice(idx, 1);
    }
  }

  /** 释放绑定数据持有的 fd，并清空令牌（formImages 保留，不影响已推送的数据） */
  static releaseFormData(data: WidgetCoverFormData): void {
    if (data === undefined || data === null) {
      return;
    }
    WidgetCover.release(data.coverToken);
    data.coverToken = '';
  }

  /** 临时目录里本模块产生的文件过多时，按修改时间清理最旧的一批 */
  private static cleanup(dir: string): void {
    try {
      let names: string[] = fileIo.listFileSync(dir);
      let mine: string[] = [];
      for (let n of names) {
        if (n.startsWith(WidgetCover.FILE_PREFIX + '_')) {
          mine.push(n);
        }
      }
      if (mine.length <= WidgetCover.MAX_KEEP_FILES) {
        return;
      }
      mine.sort((a: string, b: string): number => {
        return WidgetCover.mtimeOf(dir, a) - WidgetCover.mtimeOf(dir, b);
      });
      let removeCount: number = mine.length - WidgetCover.MAX_KEEP_FILES;
      for (let i = 0; i < removeCount; i++) {
        try {
          fileIo.unlinkSync(dir + '/' + mine[i]);
        } catch (err) {
          // 文件被占用 / 已删除：忽略
        }
      }
    } catch (err) {
      // 目录不可读：忽略，不影响本次刷新
    }
  }

  /**
   * 生成候选 URL：原地址优先，其后是镜像池里「同路径 + 换 host」的变体。
   * 主应用 ImageLoader 就是这么做的；卡片侧原来只试一个地址，
   * 一旦服务端给的 fileServer 不可直连，封面就永远出不来。
   */
  private static candidatesOf(url: string): string[] {
    let out: string[] = [];
    if (url.length === 0) {
      return out;
    }
    out.push(url);
    let schemeIdx: number = url.indexOf('://');
    if (schemeIdx < 0) {
      return out;
    }
    let hostStart: number = schemeIdx + 3;
    let pathIdx: number = url.indexOf('/', hostStart);
    if (pathIdx < 0) {
      return out;
    }
    let path: string = url.substring(pathIdx);
    for (let host of IMAGE_HOST_POOL) {
      let cand: string = host + path;
      if (out.indexOf(cand) < 0) {
        out.push(cand);
      }
      if (out.length >= WidgetCover.MAX_CANDIDATES) {
        break;
      }
    }
    return out;
  }

  /**
   * 下载尝试序列（P2-2）：
   * 1) 原地址；2) 镜像池同路径；3) 原地址强制 HTTP/1.1 重试一次
   *    （共享连接可能已协商成 HTTP/2，实测偶发 HTTP2 framing 失败，降级 HTTP/1.1）。
   * 次数固定 2~3 次，配合单次 1s 超时与整批 3s 总预算，不会顶破 10s 生命周期。
   */
  private static attemptsOf(url: string): WidgetCoverAttempt[] {
    let candidates: string[] = WidgetCover.candidatesOf(url);
    let out: WidgetCoverAttempt[] = [];
    for (let c of candidates) {
      let a = new WidgetCoverAttempt();
      a.url = c;
      a.http1 = false;
      out.push(a);
    }
    if (candidates.length > 0) {
      let retry = new WidgetCoverAttempt();
      retry.url = candidates[0];
      retry.http1 = true;
      out.push(retry);
    }
    return out;
  }

  /** 同一 URL 的稳定缓存路径：文件名与 memory key 解耦，跨刷新/跨进程复用 */
  private static cachePathOf(dir: string, url: string): string {
    return dir + '/' + WidgetCover.FILE_PREFIX + '_u' + WidgetCover.hashOf(url);
  }

  /** djb2 字符串哈希（32 位无符号，十六进制） */
  private static hashOf(url: string): string {
    let h: number = 5381;
    for (let i = 0; i < url.length; i++) {
      h = ((h * 33) ^ url.charCodeAt(i)) >>> 0;
    }
    return h.toString(16);
  }

  /** 只取 host，日志里不外泄完整图片地址 */
  private static hostOf(url: string): string {
    let idx: number = url.indexOf('://');
    if (idx < 0) {
      return '(relative)';
    }
    let rest: string = url.substring(idx + 3);
    let slash: number = rest.indexOf('/');
    return slash > 0 ? rest.substring(0, slash) : rest;
  }

  private static mtimeOf(dir: string, name: string): number {
    try {
      return fileIo.statSync(dir + '/' + name).mtime;
    } catch (err) {
      return 0;
    }
  }
}
