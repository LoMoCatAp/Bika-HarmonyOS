import { http } from '@kit.NetworkKit';
import { ImageLoader } from '../common/ImageLoader';
import {
  BIKA_API_HOST,
  BIKA_INIT_HOST,
  BIKA_FALLBACK_IPS
} from '../common/Constants';
import { isAllowedDirectAddress, shouldTryPlaintextBootstrap } from '../models/RouteGuard';

/**
 * API 直连路由管理器：
 *
 * 1. 默认直连 IP 池（首项 104.21.20.188），App 启动立即可用，完全不依赖 init 引导。
 * 2. init 引导（https://68.183.234.72/init，所有直连候选失败后才回退 HTTP）在后台异步
 *    拉取，成功后把合法地址追加进池（「池 ∪ init 地址」语义，默认 IP 保持首位）。
 * 3. 一次请求内按池顺序逐个 IP 尝试连接，全部失败才报网络错误。
 *
 * HarmonyOS 平台等价说明：@ohos.net.http 没有自定义 DNS 钩子，因此 URL 采用
 * https://{ip}/{path}，同时通过 sniHostName 携带真实域名 SNI、Host 头指回真实
 * 域名，到达与「URL=域名 + DNS 层替换 IP + 正常证书校验」相同的源站
 * （SNI 相同、Host 相同）；因 URL 是 IP，证书主机名校验需跳过。
 */

/** init 接口响应 */
interface InitResponse {
  status: string;
  addresses: string[];
}

export class ApiRouteManager {
  private static instance: ApiRouteManager | null = null;

  /** 直连 IP 池（默认 = BIKA DEFAULT_DNS_IP，init 后台刷新后追加） */
  private ipPool: string[] = [];
  /** init 后台刷新的单飞 Promise */
  private refreshPromise: Promise<void> | null = null;
  /** 上次刷新成功时间（节流：1 小时内不重复刷） */
  private lastRefreshAt: number = 0;
  private lastHttpBootstrapAt: number = 0;
  private poolExhausted: boolean = false;

  static getInstance(): ApiRouteManager {
    if (!ApiRouteManager.instance) {
      ApiRouteManager.instance = new ApiRouteManager();
    }
    return ApiRouteManager.instance;
  }

  private constructor() {
    // 默认池立即生效，不等 init
    this.ipPool = BIKA_FALLBACK_IPS.slice(0);
  }

  /**
   * 请求前调用：默认池已可用，仅触发一次后台 init 刷新（单飞、非阻塞）。
   * 启动即同步刷新（单飞、非阻塞）。
   */
  ensureInitialized(): void {
    if (this.refreshPromise === null && Date.now() - this.lastRefreshAt > 60 * 60 * 1000) {
      this.refreshPromise = this.doRefresh().finally(() => {
        this.refreshPromise = null;
      });
    }
  }

  /** 强制刷新直连 IP 池（忽略 1 小时节流，设置页手动触发） */
  forceRefresh(): void {
    if (this.refreshPromise !== null) {
      return;
    }
    this.refreshPromise = this.doRefresh().finally(() => {
      this.refreshPromise = null;
    });
  }

  notifyCandidatesExhausted(): void {
    this.poolExhausted = true;
  }

  /** 恢复默认 IP 池 */
  resetToDefault(): void {
    this.ipPool = BIKA_FALLBACK_IPS.slice(0);
    this.lastRefreshAt = 0;
  }

  /** 当前生效的 API 直连 IP */
  getApiDnsIps(): string[] {
    return this.ipPool.slice(0);
  }

  /** 应用 DNS 选择：API IP 列表 + 图片 IP 列表（空数组恢复默认） */
  applyCustomDns(apiIps: string[], imageIps: string[]): void {
    if (apiIps.length > 0) {
      this.ipPool = apiIps.slice(0);
    } else {
      this.ipPool = BIKA_FALLBACK_IPS.slice(0);
    }
    this.lastRefreshAt = 0;
    ImageLoader.setCustomImageIps(imageIps);
  }

  /**
   * 后台拉取 init 引导配置。
   * 首选 HTTPS。直连候选耗尽且冷却结束后，才尝试 HTTP。
   */
  private async doRefresh(): Promise<void> {
    if (await this.fetchBootstrap('https')) {
      return;
    }

    const now = Date.now();
    if (!shouldTryPlaintextBootstrap(this.poolExhausted, this.lastHttpBootstrapAt, now)) {
      return;
    }

    this.lastHttpBootstrapAt = now;
    if (await this.fetchBootstrap('http')) {
      console.warn('[ApiRouteManager] 已使用明文引导通道（最后手段）刷新直连池');
    }
  }

  private async fetchBootstrap(scheme: string): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(scheme + '://' + BIKA_INIT_HOST + '/init', {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      });
      if (response.responseCode !== 200) {
        console.warn('[ApiRouteManager] init ' + scheme + ' 响应异常: HTTP ' + response.responseCode);
        return false;
      }
      if (typeof response.result !== 'string' || !this.mergeInitAddresses(response.result)) {
        console.warn('[ApiRouteManager] init ' + scheme + ' 未返回可用地址');
        return false;
      }
      return true;
    } catch (err) {
      console.warn('[ApiRouteManager] init ' + scheme + ' 失败: ' + (err instanceof Error ? err.message : JSON.stringify(err)));
      return false;
    } finally {
      request.destroy();
    }
  }

  private mergeInitAddresses(responseText: string): boolean {
    const init = JSON.parse(responseText) as InitResponse;
    if (!init || !Array.isArray(init.addresses)) {
      return false;
    }

    const validated = init.addresses.filter((address: string): boolean =>
      typeof address === 'string' && isAllowedDirectAddress(address));
    if (validated.length === 0) {
      return false;
    }

    // 保留已有候选的优先级，将新地址按响应顺序去重追加。
    for (const address of validated) {
      if (this.ipPool.indexOf(address) < 0) {
        this.ipPool.push(address);
      }
    }
    this.lastRefreshAt = Date.now();
    this.poolExhausted = false;
    console.info('[ApiRouteManager] init 刷新成功，直连池: ' + JSON.stringify(this.ipPool));
    this.probeEgressIp();
    return true;
  }

  /**
   * 一次性出口 IP 诊断：日志回显本机公网出口，用于对比哔咔 1023 拉黑维度
   */
  private probeEgressIp(): void {
    let req = http.createHttp();
    req.request('http://myip.ipip.net', {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 6000,
      readTimeout: 6000
    }).then(r => {
      console.info('[ApiRouteManager][diag] 出口IP: ' + (r.result as string).substring(0, 120));
    }).catch((e: Error) => {
      console.warn('[ApiRouteManager][diag] 出口IP探测失败: ' + e.message);
    }).finally(() => req.destroy());
  }

  /**
   * 当前直连 IP 候选列表（按池顺序返回快照）。
   * 调用方按顺序逐个尝试，任一连接成功即用。
   */
  getCandidates(): string[] {
    return this.ipPool.slice(0);
  }

  /** 池摘要（日志用） */
  describe(): string {
    return this.ipPool.join('|');
  }
}

/** 直连请求构造参数（IP URL + 真实域名 SNI + 真实域名 Host） */
export interface RouteInfo {
  url: string;
  hostHeader: string;
  sniHost: string;
}

/** 按单个 IP 构造直连路由信息（供 HTTP 客户端使用） */
export function buildDirectRoute(ip: string): RouteInfo {
  return {
    url: 'https://' + ip,
    hostHeader: BIKA_API_HOST,
    sniHost: BIKA_API_HOST
  };
}
