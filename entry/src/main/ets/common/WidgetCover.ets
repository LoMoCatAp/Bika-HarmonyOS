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
 * 约束：
 * - 并发上限 MAX_CONCURRENCY（默认 2），单张超时 TIMEOUT_MS（默认 3s）；
 * - 单张超过 MAX_BYTES（1.5MB，官方单图上限 2MB）直接跳过，失败降级为占位；
 * - fd 不在 updateForm 之后立刻关闭：进程内保留到该卡片下一次刷新 / 卡片被移除，
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
  private mapping: Map<string, string> = new Map();

  /** 记录一个成功下载的封面 */
  put(bizKey: string, memKey: string, fd: number, file: fileIo.File): void {
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
}

export class WidgetCover {
  /**
   * 并发上限：同时最多下载几张封面。
   * FormExtensionAbility 的生命周期预算只有 10s（超时会被系统强杀，
   * 见 AMS extension_running_timeout_monitor），所以这里取 4 让一批下完。
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

  private static readonly FILE_PREFIX: string = 'wcover';
  private static readonly MAX_KEEP_FILES: number = 48;
  private static seq: number = 0;
  /** token → 保持打开的句柄 */
  private static openFiles: Map<string, fileIo.File[]> = new Map();

  /**
   * 并发下载一批封面到沙箱临时目录并打开 fd。
   * 任何单张失败都只影响自己（对应的 coverKey 为空串），绝不抛异常。
   */
  static async prepare(requests: WidgetCoverRequest[], ctx?: Context): Promise<WidgetCoverBundle> {
    let bundle = new WidgetCoverBundle();
    try {
      if (ctx === undefined || ctx === null || requests.length === 0) {
        return bundle;
      }
      let dir: string = ctx.tempDir;
      if (dir === undefined || dir === null || dir.length === 0) {
        return bundle;
      }
      WidgetCover.cleanup(dir);
      let cursor = new WidgetCoverCursor();
      let workers: Promise<void>[] = [];
      let n: number = requests.length < WidgetCover.MAX_CONCURRENCY
        ? requests.length : WidgetCover.MAX_CONCURRENCY;
      for (let i = 0; i < n; i++) {
        workers.push(WidgetCover.worker(requests, cursor, bundle, dir));
      }
      await Promise.all(workers);
    } catch (err) {
      console.warn('[WidgetCover] prepare failed: ' + JSON.stringify(err));
    }
    return bundle;
  }

  /** 单个并发 worker：不断从游标领取下标，直到领完 */
  private static async worker(requests: WidgetCoverRequest[], cursor: WidgetCoverCursor,
    bundle: WidgetCoverBundle, dir: string): Promise<void> {
    while (cursor.value < requests.length) {
      let i: number = cursor.value;
      cursor.value = i + 1;
      let req: WidgetCoverRequest = requests[i];
      if (req === undefined || req === null || req.url.length === 0) {
        continue;
      }
      // 环节 2：按候选 URL 依次尝试（原地址 → 镜像池同路径），任一成功即用
      let candidates: string[] = WidgetCover.candidatesOf(req.url);
      let bytes: ArrayBuffer | null = null;
      for (let ci = 0; ci < candidates.length; ci++) {
        try {
          let buf: ArrayBuffer = await WidgetCover.fetchWithTimeout(candidates[ci], WidgetCover.TIMEOUT_MS);
          if (buf.byteLength > 0) {
            bytes = buf;
            break;
          }
        } catch (err) {
          // 该候选不可用，换下一个
        }
      }
      if (bytes === null) {
        hilog.warn(DOMAIN, TAG, 'download failed biz=%{public}s tried=%{public}d primary=%{public}s',
          req.bizKey, candidates.length, WidgetCover.hostOf(req.url));
        continue;
      }
      if (bytes === null || bytes.byteLength === 0) {
        hilog.warn(DOMAIN, TAG, 'download empty biz=%{public}s url=%{public}s', req.bizKey, WidgetCover.hostOf(req.url));
        continue;
      }
      if (bytes.byteLength > WidgetCover.MAX_BYTES) {
        // 环节 2：超过官方单图上限（2MB）直接放弃，避免整批下发失败
        hilog.warn(DOMAIN, TAG, 'download too large biz=%{public}s bytes=%{public}d',
          req.bizKey, bytes.byteLength);
        continue;
      }
      try {
        WidgetCover.seq++;
        let memKey: string = WidgetCover.FILE_PREFIX + '_' + i + '_' + Date.now() + '_' + WidgetCover.seq;
        let path: string = dir + '/' + memKey;
        let file = fileIo.openSync(path,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(file.fd, bytes);
        bundle.put(req.bizKey, memKey, file.fd, file);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'write failed biz=%{public}s err=%{public}s', req.bizKey, JSON.stringify(err));
      }
    }
  }

  /** 下载单张封面（带超时），失败 / 超时抛异常由调用方降级 */
  private static fetchWithTimeout(url: string, ms: number): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve: (v: ArrayBuffer) => void, reject: (e: Error) => void) => {
      let settled: boolean = false;
      let timer = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('cover timeout'));
        }
      }, ms);
      let headers: Record<string, string> = { 'User-Agent': 'okhttp/3.8.1' };
      BikaHttpClient.downloadBinary(url, headers).then((buf: ArrayBuffer) => {
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
    data.coverToken = token;
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
