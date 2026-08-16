import { IMAGE_HOST_POOL } from '../common/Constants';

/**
 * 图片 URL 管理器
 *
 * 哔咔图片服务器（fileServer）不稳定，加载失败时按镜像池切换重试。
 * 参考 BIKA 的 DomainFallbackInterceptor：记住最近成功的镜像站，后续优先使用。
 *
 * 图片 URL 规则：{fileServer}/static/{path}
 */
export class ImageUrlManager {
  private static instance: ImageUrlManager | null = null;
  /** 记住最近成功的镜像站（按原始 host 记忆） */
  private preferredHost: string = '';

  static getInstance(): ImageUrlManager {
    if (!ImageUrlManager.instance) {
      ImageUrlManager.instance = new ImageUrlManager();
    }
    return ImageUrlManager.instance;
  }

  /**
   * 根据媒体信息构造候选图片 URL 列表（原始服务器优先，其后是镜像池）
   * @param fileServer 服务端返回的文件服务器地址
   * @param path 图片路径
   */
  buildCandidateUrls(fileServer: string, path: string): string[] {
    let origin = ImageUrlManager.normalizeServer(fileServer);
    let urls: string[] = [`${origin}/static/${path}`];
    // 记忆的优选镜像插到第二位
    if (this.preferredHost.length > 0 && this.preferredHost !== origin) {
      urls.push(`${this.preferredHost}/static/${path}`);
    }
    for (let host of IMAGE_HOST_POOL) {
      if (host !== origin && host !== this.preferredHost) {
        urls.push(`${host}/static/${path}`);
      }
    }
    return urls;
  }

  /**
   * 上报成功加载的 URL，记忆其镜像站
   */
  reportSuccess(url: string): void {
    let host = ImageUrlManager.extractHost(url);
    if (host.length > 0 && host !== this.preferredHost) {
      this.preferredHost = host;
      console.info(`[ImageUrlManager] 记忆优选镜像: ${host}`);
    }
  }

  /**
   * 归一化服务器地址：强制 https、去末尾斜杠
   */
  static normalizeServer(server: string): string {
    let s = (server || 'https://s3.picacomic.com').trim();
    if (s.startsWith('http://')) {
      s = 'https://' + s.substring('http://'.length);
    } else if (!s.startsWith('https://')) {
      s = 'https://' + s;
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    // 复刻 haka_comic：go2778 官方国内镜像（picacomic → go2778）
    s = s.replace('picacomic', 'go2778');
    return s;
  }

  /**
   * 从 URL 提取 origin（scheme://host）
   */
  static extractHost(url: string): string {
    let idx = url.indexOf('://');
    if (idx < 0) {
      return '';
    }
    let rest = url.substring(idx + 3);
    let slash = rest.indexOf('/');
    return slash > 0 ? url.substring(0, idx + 3 + slash) : url;
  }
}
