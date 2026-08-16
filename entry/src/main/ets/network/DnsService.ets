import { http, socket } from '@kit.NetworkKit';

/**
 * DNS 分流线路服务：
 * 1. 从 macapi1 / macapi2 双源拉取 API 域名与图片域名的分流线路 IP；
 * 2. TCP 443 握手测速（2 秒超时），供「应用最低延迟」与线路选择使用。
 */

/** 单条 IP 条目 */
export interface DnsIpEntry {
  ip: string;
  line: string;
  domain: string;
  /** -2 未测；-1 超时/失败；>=0 握手毫秒数 */
  latency: number;
  selected: boolean;
}

interface DnsResolveData {
  domain: string;
  lines?: Record<string, DnsLineData>;
}

interface DnsResolveEnvelope {
  code: number;
  message: string;
  data?: DnsResolveData;
}

interface DnsLineData {
  ips: string[];
  status: string;
}

export class DnsService {
  /** 拉取两个域名的分流线路（按线路分组返回） */
  static async fetchLines(selectedApi: string[], selectedImage: string[]): Promise<Map<string, DnsIpEntry[]>> {
    let sources: Array<[string, string]> = [
      ['picaapi.picacomic.com', 'https://macapi1.com/app/picacomic/dns/resolve?domain=picaapi.picacomic.com'],
      ['picacomic.com', 'https://macapi2.com/app/picacomic/dns/resolve?domain=picacomic.com']
    ];
    let map = new Map<string, DnsIpEntry[]>();
    for (let s of sources) {
      let entries = await DnsService.fetchOne(s[1], s[0]);
      for (let e of entries) {
        e.selected = e.domain === 'picacomic.com'
          ? selectedImage.indexOf(e.ip) >= 0
          : selectedApi.indexOf(e.ip) >= 0;
        let list = map.get(e.line);
        if (list === undefined) {
          list = [];
          map.set(e.line, list);
        }
        list.push(e);
      }
    }
    return map;
  }

  private static async fetchOne(url: string, domain: string): Promise<DnsIpEntry[]> {
    let request = http.createHttp();
    try {
      let response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      if (response.responseCode !== 200) {
        return [];
      }
      let envelope = JSON.parse(response.result as string) as DnsResolveEnvelope;
      if (!envelope.data || !envelope.data.lines) {
        return [];
      }
      let out: DnsIpEntry[] = [];
      let lineKeys = Object.keys(envelope.data.lines);
      for (let line of lineKeys) {
        let lineData = envelope.data.lines[line];
        if (!lineData || !lineData.ips) {
          continue;
        }
        for (let ip of lineData.ips) {
          out.push({ ip: ip, line: line, domain: domain, latency: -2, selected: false });
        }
      }
      return out;
    } catch (err) {
      console.warn('[DnsService] fetch failed: ' + (err instanceof Error ? err.message : JSON.stringify(err)));
      return [];
    } finally {
      request.destroy();
    }
  }

  /** TCP 443 握手延迟（毫秒；-1 = 超时/失败） */
  static async testLatency(ip: string): Promise<number> {
    let tcp = socket.constructTCPSocketInstance();
    let start = Date.now();
    try {
      await tcp.connect({ address: { address: ip, port: 443 }, timeout: 2000 });
      await tcp.close();
      return Date.now() - start;
    } catch (err) {
      try {
        await tcp.close();
      } catch (e2) {
      }
      return -1;
    }
  }
}
