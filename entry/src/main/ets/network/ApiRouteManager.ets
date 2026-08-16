import { http } from '@kit.NetworkKit';
import {
  BIKA_API_HOST,
  BIKA_INIT_HOST,
  BIKA_FALLBACK_IPS
} from '../common/Constants';

/**
 * API 直连路由管理器 —— 完整复刻 BIKA 的 DirectDns + SyncWorker：
 *
 * 1. 默认直连 IP 池 = BIKA DEFAULT_DNS_IP（104.21.20.188），App 启动立即可用，
 *    完全不依赖 init 引导（BIKA 的 WorkManager 同步失败不影响使用）。
 * 2. init 引导（https://68.183.234.72/init，HTTPS 失败回退 HTTP）在后台异步
 *    拉取，成功后把合法地址追加进池（复刻 BIKA setDns 的「池 ∪ init 地址」语义，
 *    默认 IP 保持首位）。
 * 3. 一次请求内按池顺序逐个 IP 尝试连接（复刻 okhttp 拿到 DNS 列表后的
 *    route 尝试行为），全部失败才报网络错误。
 *
 * HarmonyOS 平台等价说明：@ohos.net.http 没有自定义 DNS 钩子，因此 URL 采用
 * https://{ip}/{path}，同时通过 sniHostName 携带真实域名 SNI、Host 头指回真实
 * 域名 —— 与 BIKA 的「URL=域名 + DNS 层替换 IP + 正常证书校验」到达同一源站
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

  static getInstance(): ApiRouteManager {
    if (!ApiRouteManager.instance) {
      ApiRouteManager.instance = new ApiRouteManager();
    }
    return ApiRouteManager.instance;
  }

  private constructor() {
    // 复刻 BIKA DirectDns：默认池立即生效，不等 init
    this.ipPool = BIKA_FALLBACK_IPS.slice(0);
  }

  /**
   * 请求前调用：默认池已可用，仅触发一次后台 init 刷新（单飞、非阻塞）。
   * 复刻 BIKA startUpSyncWork 的启动即同步行为。
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

  /** 恢复默认 IP 池 */
  resetToDefault(): void {
    this.ipPool = BIKA_FALLBACK_IPS.slice(0);
    this.lastRefreshAt = 0;
  }

  /**
   * 后台拉取 init 引导配置。
   * 复刻 BIKA fetchBootstrapConfig：先 HTTPS 再 HTTP 回退；响应地址严格
   * 校验（ADDRESS_PATTERN 同款），防明文通道中间人注入。
   */
  private async doRefresh(): Promise<void> {
    let responseText: string = '';
    let ok: boolean = false;
    for (let scheme of ['https', 'http']) {
      let request = http.createHttp();
      try {
        let response = await request.request(scheme + '://' + BIKA_INIT_HOST + '/init', {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 5000,
          readTimeout: 5000
        });
        if (response.responseCode === 200) {
          responseText = response.result as string;
          ok = true;
          break;
        }
        console.warn('[ApiRouteManager] init ' + scheme + ' 响应异常: HTTP ' + response.responseCode);
      } catch (err) {
        console.warn('[ApiRouteManager] init ' + scheme + ' 失败: ' + (err instanceof Error ? err.message : JSON.stringify(err)));
      } finally {
        request.destroy();
      }
    }

    if (ok && responseText.length > 0) {
      try {
        let init = JSON.parse(responseText) as InitResponse;
        if (init && init.addresses && init.addresses.length > 0) {
          // 地址合法性校验（BIKA ADDRESS_PATTERN 同款）：仅接受合法 IP/主机名
          let validated = init.addresses.filter((s: string) => /^[0-9a-zA-Z.\-:\[\]]{1,255}$/.test(s));
          // 复刻 BIKA setDns：默认 IP 保持首位，init 返回地址去重追加
          for (let ip of validated) {
            if (this.ipPool.indexOf(ip) < 0) {
              this.ipPool.push(ip);
            }
          }
          this.lastRefreshAt = Date.now();
          console.info('[ApiRouteManager] init 刷新成功，直连池: ' + JSON.stringify(this.ipPool));
          this.probeEgressIp();
        }
      } catch (err) {
        console.warn('[ApiRouteManager] init 响应解析失败: ' + (err instanceof Error ? err.message : JSON.stringify(err)));
      }
    }
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
   * 复刻 okhttp 路由语义：调用方按顺序逐个尝试，任一连接成功即用。
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
