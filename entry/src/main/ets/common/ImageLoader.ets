import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BikaHttpClient } from '../network/BikaHttpClient';

/** 磁盘缓存条目 */
interface DiskEntry {
  path: string;
  mtime: number;
  size: number;
}

/**
 * 图片加载器：
 * 1. 用自己的网络栈下载图片字节（UA okhttp/3.8.1，go2778 镜像域名直连），
 *    不再依赖 ArkUI Image 组件的系统网络栈（其 TLS/DNS 行为不可控，导致读图失败）；
 * 2. 字节解码为 PixelMap 供 Image 组件显示；
 * 3. 三级缓存：内存 LRU（160 张）→ 磁盘文件缓存（200MB LRU）→ 网络；
 * 4. 单飞去重 + 多候选 URL 顺序尝试（镜像回退语义）。
 */
export class ImageLoader {
  private static readonly MAX_CACHE: number = 160;
  /** 磁盘缓存上限（字节） */
  private static readonly MAX_DISK_BYTES: number = 200 * 1024 * 1024;
  private static cache: Map<string, PixelMap> = new Map();
  private static order: string[] = [];
  private static pending: Map<string, Promise<PixelMap>> = new Map();
  /** DNS 优化选中的图片直连 IP（空 = 默认系统解析） */
  private static customImageIps: string[] = [];
  /** 磁盘缓存目录 */
  private static diskDir: string = '';
  private static diskReady: boolean = false;

  static setCustomImageIps(ips: string[]): void {
    ImageLoader.customImageIps = ips.slice(0);
  }

  /** 初始化磁盘缓存目录（EntryAbility 注入应用上下文） */
  static initDiskCache(ctx: common.UIAbilityContext): void {
    try {
      let dir = ctx.cacheDir + '/imgcache';
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      ImageLoader.diskDir = dir;
      ImageLoader.diskReady = true;
      ImageLoader.evictDiskIfNeeded();
    } catch (err) {
      console.warn('[ImageLoader] initDiskCache failed: ' + JSON.stringify(err));
    }
  }

  private static hashOf(url: string): string {
    let h = 5381;
    for (let i = 0; i < url.length; i++) {
      h = ((h << 5) + h + url.charCodeAt(i)) >>> 0;
    }
    return h.toString(16);
  }

  private static diskPath(url: string): string {
    return ImageLoader.diskDir + '/' + ImageLoader.hashOf(url);
  }

  /** 图片是否已有磁盘缓存文件（拖拽分享用） */
  static diskFilePath(url: string): string {
    if (!ImageLoader.diskReady || url.length === 0) {
      return '';
    }
    let path = ImageLoader.diskPath(url);
    try {
      return fs.accessSync(path) ? path : '';
    } catch (err) {
      return '';
    }
  }

  /** 从磁盘缓存读字节（未命中返回 null） */
  private static readDisk(url: string): ArrayBuffer | null {
    if (!ImageLoader.diskReady) {
      return null;
    }
    let path = ImageLoader.diskPath(url);
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      let stat = fs.statSync(path);
      let buf = new ArrayBuffer(stat.size);
      let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fs.readSync(file.fd, buf);
      fs.closeSync(file.fd);
      return buf;
    } catch (err) {
      return null;
    }
  }

  /** 写磁盘缓存（后台尽力而为，不阻塞显示） */
  private static writeDisk(url: string, bytes: ArrayBuffer): void {
    if (!ImageLoader.diskReady) {
      return;
    }
    let path = ImageLoader.diskPath(url);
    try {
      if (!fs.accessSync(path)) {
        let file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, bytes);
        fs.closeSync(file.fd);
        ImageLoader.evictDiskIfNeeded();
      }
    } catch (err) {
      // 磁盘缓存失败不影响显示
    }
  }

  /** 超出上限时按修改时间淘汰最旧文件 */
  private static evictDiskIfNeeded(): void {
    if (!ImageLoader.diskReady) {
      return;
    }
    try {
      let files = fs.listFileSync(ImageLoader.diskDir);
      let entries: DiskEntry[] = [];
      let total = 0;
      for (let name of files) {
        let path = ImageLoader.diskDir + '/' + name;
        let stat = fs.statSync(path);
        entries.push({ path: path, mtime: stat.mtime, size: stat.size });
        total += stat.size;
      }
      entries.sort((a, b) => a.mtime - b.mtime);
      for (let e of entries) {
        if (total <= ImageLoader.MAX_DISK_BYTES) {
          break;
        }
        fs.unlinkSync(e.path);
        total -= e.size;
      }
    } catch (err) {
      // 忽略淘汰失败
    }
  }

  /** 磁盘缓存占用字节数 */
  static diskCacheBytes(): number {
    if (!ImageLoader.diskReady) {
      return 0;
    }
    try {
      let files = fs.listFileSync(ImageLoader.diskDir);
      let total = 0;
      for (let name of files) {
        total += fs.statSync(ImageLoader.diskDir + '/' + name).size;
      }
      return total;
    } catch (err) {
      return 0;
    }
  }

  static getCustomImageIps(): string[] {
    return ImageLoader.customImageIps.slice(0);
  }

  /** 生成图片 URL 的 IP 直连变体（保留路径，SNI/Host 指回原域名） */
  private static ipVariants(url: string): string[] {
    if (ImageLoader.customImageIps.length === 0) {
      return [];
    }
    let schemeIdx = url.indexOf('://');
    if (schemeIdx < 0) {
      return [];
    }
    let hostStart = schemeIdx + 3;
    let pathIdx = url.indexOf('/', hostStart);
    if (pathIdx < 0) {
      return [];
    }
    let path = url.substring(pathIdx);
    let out: string[] = [];
    for (let ip of ImageLoader.customImageIps) {
      out.push('https://' + ip + path);
    }
    return out;
  }

  private static hostOf(url: string): string {
    let schemeIdx = url.indexOf('://');
    if (schemeIdx < 0) {
      return '';
    }
    let hostStart = schemeIdx + 3;
    let pathIdx = url.indexOf('/', hostStart);
    return pathIdx < 0 ? url.substring(hostStart) : url.substring(hostStart, pathIdx);
  }

  /** 同步取缓存（供组件首帧使用） */
  static getCached(url: string): PixelMap | null {
    let pm = ImageLoader.cache.get(url);
    return pm ?? null;
  }

  /** 按候选顺序加载，全部失败抛最后一个错误 */
  static async load(urls: string[]): Promise<PixelMap> {
    let lastErr: Error = new Error('no valid url');
    for (let url of urls) {
      if (!url || url.length === 0) {
        continue;
      }
      let cached = ImageLoader.cache.get(url);
      if (cached !== undefined) {
        ImageLoader.touch(url);
        return cached;
      }
      // 磁盘缓存命中：直接解码
      let diskBytes = ImageLoader.readDisk(url);
      if (diskBytes !== null) {
        try {
          let source = image.createImageSource(diskBytes);
          let pm = await source.createPixelMap();
          ImageLoader.put(url, pm);
          return pm;
        } catch (err) {
          console.warn('[ImageLoader] 磁盘缓存解码失败 ' + url);
        }
      }
      let pending = ImageLoader.pending.get(url);
      if (pending !== undefined) {
        return pending;
      }
      let task = ImageLoader.download(url);
      ImageLoader.pending.set(url, task);
      try {
        let pm = await task;
        ImageLoader.put(url, pm);
        return pm;
      } catch (err) {
        lastErr = err as Error;
        console.warn('[ImageLoader] 下载失败 ' + url + ': ' + lastErr.message);
      } finally {
        ImageLoader.pending.delete(url);
      }
    }
    throw lastErr;
  }

  /** 下载原始字节（供下载器写本地文件；含镜像回退与自定义 DNS 直连变体） */
  /** 是否代理模式（规则模式 VPN 系统代理） */
  static proxyMode(): boolean {
    return AppStorage.get<boolean>('bika_use_proxy') ?? false;
  }

  static async downloadBytes(urls: string[]): Promise<ArrayBuffer> {
    let lastErr: Error = new Error('no valid url');
    for (let url of urls) {
      if (!url || url.length === 0) {
        continue;
      }
      // 代理模式：域名直发，由系统代理分流（不走 IP 直连）
      if (ImageLoader.proxyMode()) {
        try {
          let headers: Record<string, string> = { 'User-Agent': 'okhttp/3.8.1' };
          return await BikaHttpClient.downloadBinaryViaProxy(url, headers);
        } catch (err) {
          lastErr = err as Error;
          console.warn('[ImageLoader] proxy downloadBytes failed ' + url + ': ' + lastErr.message);
        }
        continue;
      }
      let host = ImageLoader.hostOf(url);
      let variants = ImageLoader.ipVariants(url);
      let candidates: string[] = [url].concat(variants);
      for (let candidate of candidates) {
        let isIpDirect = candidate !== url;
        try {
          let headers: Record<string, string> = { 'User-Agent': 'okhttp/3.8.1' };
          if (isIpDirect && host.length > 0) {
            headers['Host'] = host;
          }
          return await BikaHttpClient.downloadBinary(candidate, headers, isIpDirect ? host : '');
        } catch (err) {
          lastErr = err as Error;
          console.warn('[ImageLoader] downloadBytes failed ' + candidate + ': ' + lastErr.message);
        }
      }
    }
    throw lastErr;
  }

  /** 下载并解码为 PixelMap（含自定义 DNS 直连变体） */
  private static async download(url: string): Promise<PixelMap> {
    // 代理模式：域名直发，由系统代理分流
    if (ImageLoader.proxyMode()) {
      let headers: Record<string, string> = { 'User-Agent': 'okhttp/3.8.1' };
      let bytes = await BikaHttpClient.downloadBinaryViaProxy(url, headers);
      ImageLoader.writeDisk(url, bytes);
      let source = image.createImageSource(bytes);
      return await source.createPixelMap();
    }
    let host = ImageLoader.hostOf(url);
    let variants = ImageLoader.ipVariants(url);
    let candidates: string[] = [url].concat(variants);
    let lastErr: Error = new Error('download failed');
    for (let candidate of candidates) {
      let isIpDirect = candidate !== url;
      try {
        let headers: Record<string, string> = { 'User-Agent': 'okhttp/3.8.1' };
        if (isIpDirect && host.length > 0) {
          headers['Host'] = host;
        }
        let bytes = await BikaHttpClient.downloadBinary(candidate, headers, isIpDirect ? host : '');
        // 成功字节先落盘（失败不影响显示）
        ImageLoader.writeDisk(url, bytes);
        let source = image.createImageSource(bytes);
        return await source.createPixelMap();
      } catch (err) {
        lastErr = err as Error;
      }
    }
    throw lastErr;
  }

  private static put(url: string, pm: PixelMap): void {
    ImageLoader.cache.set(url, pm);
    ImageLoader.order.push(url);
    if (ImageLoader.order.length > ImageLoader.MAX_CACHE) {
      let oldest = ImageLoader.order.shift();
      if (oldest !== undefined) {
        ImageLoader.cache.delete(oldest);
      }
    }
  }

  private static touch(url: string): void {
    let idx = ImageLoader.order.indexOf(url);
    if (idx >= 0) {
      ImageLoader.order.splice(idx, 1);
    }
    ImageLoader.order.push(url);
  }

  /** 当前内存缓存张数 */
  static cachedCount(): number {
    return ImageLoader.cache.size;
  }

  /** 清空内存 + 磁盘图片缓存 */
  static clearCache(): void {
    ImageLoader.cache.clear();
    ImageLoader.order = [];
    if (ImageLoader.diskReady) {
      try {
        let files = fs.listFileSync(ImageLoader.diskDir);
        for (let name of files) {
          fs.unlinkSync(ImageLoader.diskDir + '/' + name);
        }
      } catch (err) {
        console.warn('[ImageLoader] clearDisk failed');
      }
    }
  }
}