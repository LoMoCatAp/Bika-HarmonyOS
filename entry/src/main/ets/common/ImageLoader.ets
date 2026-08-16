import { image } from '@kit.ImageKit';
import { BikaHttpClient } from '../network/BikaHttpClient';

/**
 * 图片加载器：
 * 1. 用自己的网络栈下载图片字节（UA okhttp/3.8.1，go2778 镜像域名直连），
 *    不再依赖 ArkUI Image 组件的系统网络栈（其 TLS/DNS 行为不可控，导致读图失败）；
 * 2. 字节解码为 PixelMap 供 Image 组件显示；
 * 3. 内存 LRU 缓存 + 单飞去重；
 * 4. 多候选 URL 顺序尝试（镜像回退语义）。
 */
export class ImageLoader {
  private static readonly MAX_CACHE: number = 160;
  private static cache: Map<string, PixelMap> = new Map();
  private static order: string[] = [];
  private static pending: Map<string, Promise<PixelMap>> = new Map();
  /** DNS 优化选中的图片直连 IP（空 = 默认系统解析） */
  private static customImageIps: string[] = [];

  static setCustomImageIps(ips: string[]): void {
    ImageLoader.customImageIps = ips.slice(0);
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
  static async downloadBytes(urls: string[]): Promise<ArrayBuffer> {
    let lastErr: Error = new Error('no valid url');
    for (let url of urls) {
      if (!url || url.length === 0) {
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

  /** 清空内存图片缓存 */
  static clearCache(): void {
    ImageLoader.cache.clear();
    ImageLoader.order = [];
  }
}