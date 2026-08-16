import { image } from '@kit.ImageKit';
import { BikaHttpClient } from '../network/BikaHttpClient';

/**
 * 图片加载器 —— 严格复刻 BIKA 的 Coil + OkHttp 链路：
 * 1. 用自己的网络栈下载图片字节（UA okhttp/3.8.1 与 BIKA 一致，go2778 镜像域名直连），
 *    不再依赖 ArkUI Image 组件的系统网络栈（其 TLS/DNS 行为不可控，导致读图失败）；
 * 2. 字节解码为 PixelMap 供 Image 组件显示；
 * 3. 内存 LRU 缓存 + 单飞去重；
 * 4. 多候选 URL 顺序尝试（BIKA DomainFallbackInterceptor 的镜像回退语义）。
 */
export class ImageLoader {
  private static readonly MAX_CACHE: number = 160;
  private static cache: Map<string, PixelMap> = new Map();
  private static order: string[] = [];
  private static pending: Map<string, Promise<PixelMap>> = new Map();

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

  /** 下载原始字节（供下载器写本地文件；含镜像回退） */
  static async downloadBytes(urls: string[]): Promise<ArrayBuffer> {
    let lastErr: Error = new Error('no valid url');
    for (let url of urls) {
      if (!url || url.length === 0) {
        continue;
      }
      try {
        return await BikaHttpClient.downloadBinary(url, { 'User-Agent': 'okhttp/3.8.1' });
      } catch (err) {
        lastErr = err as Error;
        console.warn('[ImageLoader] downloadBytes failed ' + url + ': ' + lastErr.message);
      }
    }
    throw lastErr;
  }

  /** 下载并解码为 PixelMap */
  private static async download(url: string): Promise<PixelMap> {
    let bytes = await BikaHttpClient.downloadBinary(url, { 'User-Agent': 'okhttp/3.8.1' });
    let source = image.createImageSource(bytes);
    return await source.createPixelMap();
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
}