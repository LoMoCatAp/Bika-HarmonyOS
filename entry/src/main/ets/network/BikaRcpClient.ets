import { rcp } from '@kit.RemoteCommunicationKit';
import { BIKA_API_HOST } from '../common/Constants';

/**
 * rcp 版网络客户端 —— 用 Remote Communication Kit 替换 @ohos.net.http。
 *
 * 哔咔在 Cloudflare 层按 TLS ClientHello 指纹限流：@ohos.net.http 的 OpenSSL 系
 * 指纹恒被 1023；rcp 是另一套独立 TLS 实现，指纹不同。
 *
 * 同时 rcp 支持 StaticDnsRule（域名→IP 静态映射），做到与 BIKA okhttp 完全同构：
 *   URL 保持真实域名（SNI/Host/证书校验全自动），DNS 层映射到直连 IP
 *   （BIKA DirectDns 同款效果，且绕开运营商 DNS 污染）。
 */
export interface RcpResponse {
  responseCode: number;
  body: string;
}

export class BikaRcpClient {
  private static session: rcp.Session | null = null;
  /** 直连 IP 池：BIKA 默认 + init 实测 + DoH 当前真实解析 */
  private static readonly IP_POOL: string[] = [
    '104.21.20.188',
    '104.19.53.76',
    '104.20.42.9',
    '172.66.173.71'
  ];

  private static getSession(): rcp.Session {
    if (!BikaRcpClient.session) {
      let rules: rcp.StaticDnsRule[] = [
        {
          host: BIKA_API_HOST,
          port: 443,
          ipAddresses: BikaRcpClient.IP_POOL
        }
      ];
      let config: rcp.SessionConfiguration = {
        requestConfiguration: {
          transfer: {
            timeout: { connectMs: 10000, transferMs: 10000 },
            autoRedirect: false
          },
          dns: {
            dnsRules: rules
            // 多个规则对同域名生效（happy eyeballs），无需开启
          }
        }
      };
      let sess = rcp.createSession(config);
      // rcp Session 自带连接池，后续请求自动复用连接
      BikaRcpClient.session = sess;
      console.info('[BikaRcpClient] rcp session created, dns rules: ' + JSON.stringify(rules));
    }
    return BikaRcpClient.session;
  }

  /**
   * 发起请求（GET/POST），url 使用真实域名（DNS 由静态规则映射到直连 IP）
   */
  static async request(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string | null
  ): Promise<RcpResponse> {
    let sess = BikaRcpClient.getSession();
    let req = new rcp.Request(url, method, headers, body ?? undefined);
    let resp = await sess.fetch(req);
    let text = resp.toString();
    return {
      responseCode: resp.statusCode,
      body: text ?? ''
    };
  }
}
