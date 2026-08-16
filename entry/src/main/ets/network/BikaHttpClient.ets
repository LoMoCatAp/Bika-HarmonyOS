import { http } from '@kit.NetworkKit';
import { DEFAULT_RETRY_TIMES, BIKA_DOH_URL } from '../common/Constants';

/**
 * HTTP 响应结构
 */
export interface BikaHttpResponse {
  responseCode: number;
  body: string;
}

/**
 * 哔咔 HTTP 网络请求客户端
 * 封装 @ohos.net.http，提供超时与网络错误重试
 */
export class BikaHttpClient {
  /** 全局单例 httpRequest：连接池复用。
   *  哔咔按「新 TLS 连接速率」限流（1023 too many requests）——
   *  每请求新建连接（原实现 createHttp+destroy）会把握手速率打满；
   *  单例 + HTTP/2 多路复用后所有请求走同一条连接，握手速率趋近于零。 */
  private static sharedRequest: http.HttpRequest | null = null;

  private static getRequest(): http.HttpRequest {
    if (!BikaHttpClient.sharedRequest) {
      BikaHttpClient.sharedRequest = http.createHttp();
    }
    return BikaHttpClient.sharedRequest;
  }

  /** App 退出时释放共享连接（进程结束会自动回收，此处仅为规范释放） */
  static destroySharedRequest(): void {
    if (BikaHttpClient.sharedRequest) {
      try {
        BikaHttpClient.sharedRequest.destroy();
      } catch (err) {
        console.warn('[BikaHttpClient] destroy shared request failed: ' + (err instanceof Error ? err.message : JSON.stringify(err)));
      }
      BikaHttpClient.sharedRequest = null;
    }
  }

  /**
   * 发起 GET 请求
   * @param url 完整 URL
   * @param headers 完整请求头（已含签名）
   * @param retries 网络错误重试次数
   * @param sniHost 直连 IP 时通过 TLS SNI 指定的真实域名（空串表示无需）
   */
  static async get(
    url: string,
    headers: Record<string, string>,
    retries: number = DEFAULT_RETRY_TIMES,
    sniHost: string = '',
    protocol: http.HttpProtocol = http.HttpProtocol.HTTP2
  ): Promise<BikaHttpResponse> {
    return BikaHttpClient.requestWithRetry(url, http.RequestMethod.GET, null, headers, retries, sniHost, protocol);
  }

  /**
   * 发起 POST 请求
   * @param url 完整 URL
   * @param body JSON 请求体字符串
   * @param headers 完整请求头（已含签名）
   * @param retries 网络错误重试次数
   * @param sniHost 直连 IP 时通过 TLS SNI 指定的真实域名（空串表示无需）
   */
  static async post(
    url: string,
    body: string,
    headers: Record<string, string>,
    retries: number = DEFAULT_RETRY_TIMES,
    sniHost: string = '',
    protocol: http.HttpProtocol = http.HttpProtocol.HTTP2
  ): Promise<BikaHttpResponse> {
    return BikaHttpClient.requestWithRetry(url, http.RequestMethod.POST, body, headers, retries, sniHost, protocol);
  }

  /** 走系统代理的请求（规则模式 VPN：Clash 等开启"系统代理"后按域名分流） */
  static async requestViaSystemProxy(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string | null
  ): Promise<BikaHttpResponse> {
    let httpReq = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: method as http.RequestMethod,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000,
        extraData: body ?? undefined,
        usingProxy: true
      };
      let resp = await httpReq.request(url, options);
      let text = typeof resp.result === 'string' ? resp.result : '';
      return { responseCode: resp.responseCode, body: text };
    } finally {
      httpReq.destroy();
    }
  }

  /** 走系统代理下载二进制（图片等） */
  static async downloadBinaryViaProxy(url: string, headers: Record<string, string>): Promise<ArrayBuffer> {
    let httpReq = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingProxy: true
      };
      let resp = await httpReq.request(url, options);
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode);
      }
      return resp.result as ArrayBuffer;
    } finally {
      httpReq.destroy();
    }
  }

  /** PUT 请求（改密码/更新资料等） */
  static async put(
    url: string,
    body: string,
    headers: Record<string, string>,
    retries: number = DEFAULT_RETRY_TIMES,
    sniHost: string = '',
    protocol: http.HttpProtocol = http.HttpProtocol.HTTP2
  ): Promise<BikaHttpResponse> {
    return BikaHttpClient.requestWithRetry(url, http.RequestMethod.PUT, body, headers, retries, sniHost, protocol);
  }

  /**
   * 带重试的请求（仅网络层错误重试；服务端 4xx/5xx 直接返回由上层处理）
   */
  private static async requestWithRetry(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    headers: Record<string, string>,
    retries: number,
    sniHost: string = '',
    protocol: http.HttpProtocol = http.HttpProtocol.HTTP2
  ): Promise<BikaHttpResponse> {
    let lastErr: Error | null = null;

    for (let i = 0; i < retries; i++) {
      try {
        return await BikaHttpClient.doRequest(url, method, body, headers, sniHost, protocol);
      } catch (err) {
        lastErr = err as Error;
        console.warn(`[BikaHttpClient] request failed (attempt ${i + 1}/${retries}): ${url} err=${err instanceof Error ? err.message : JSON.stringify(err)}`);
        if (i < retries - 1) {
          await BikaHttpClient.sleep(500 * (i + 1));
        }
      }
    }

    throw lastErr || new Error('Request failed after retries');
  }

  /**
   * 实际执行 HTTP 请求
   */
  private static async doRequest(
    url: string,
    method: http.RequestMethod,
    body: string | null,
    headers: Record<string, string>,
    sniHost: string = '',
    protocol: http.HttpProtocol = http.HttpProtocol.HTTP2
  ): Promise<BikaHttpResponse> {
    // 共享单例：连接复用（keep-alive / 多路复用），避免每请求新握手触发 1023
    let request = BikaHttpClient.getRequest();

    let options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      // 默认超时：connect 10s / read 10s
      connectTimeout: 10000,
      readTimeout: 10000,
      usingProtocol: protocol
    };
    if (sniHost && sniHost.length > 0) {
      // 直连 IP + 真实域名 SNI（BIKA DirectDns 同款效果，API 23+）。
      // 证书 SAN 是域名而 URL 是 IP，主机名校验必然不匹配，需跳过
      // （请求仍受 HMAC 签名与服务端 Authorization 保护，且 SNI 保证了连到正确源站）
      options.sniHostName = sniHost;
      options.remoteValidation = 'skip';
    } else {
      // 域名模式：DoH 解析真实 IP（绕开 DNS 污染），SNI/Host/证书校验全自动，
      // 与 BIKA okhttp 的 URL=域名行为完全同构
      options.dnsOverHttps = BIKA_DOH_URL;
    }
    // 强制纯 TLS1.3 + 仅 1.3 套件：ClientHello 指纹与 OpenSSL 默认（1.2/1.3 混合）
    // 完全不同，绕开哔咔对默认指纹的 1023 黑名单
    options.tlsOptions = {
      tlsVersionMin: http.TlsVersion.TLS_V_1_3,
      tlsVersionMax: http.TlsVersion.TLS_V_1_3,
      cipherSuites: [
        'TLS_AES_128_GCM_SHA256',
        'TLS_AES_256_GCM_SHA384',
        'TLS_CHACHA20_POLY1305_SHA256'
      ]
    };
    if (body && body.length > 0) {
      options.extraData = body;
    }

    let response = await request.request(url, options);
    return {
      responseCode: response.responseCode,
      body: (response.result as string) || ''
    };
  }

  /**
   * 下载二进制数据（阅读器图片等）
   * @param url 完整 URL
   * @param headers 额外请求头
   * @param sniHost 直连 IP 时的真实域名（SNI/Host 校验），空 = 域名直连
   * @returns ArrayBuffer
   */
  static async downloadBinary(
    url: string,
    headers: Record<string, string> = {},
    sniHost: string = ''
  ): Promise<ArrayBuffer> {
    // 共享单例：图片请求同样复用连接，避免大量新握手
    let request = BikaHttpClient.getRequest();

    // 跟随重定向（最多 3 跳），镜像站可能 302 到真实存储
    let currentUrl = url;
    for (let hop = 0; hop < 3; hop++) {
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000
      };
      if (sniHost && sniHost.length > 0) {
        // 图片 DNS 优化：直连选中 IP，SNI 指回原域名
        options.sniHostName = sniHost;
        options.remoteValidation = 'skip';
      }
      let response = await request.request(currentUrl, options);

      if (response.responseCode === 200) {
        return response.result as ArrayBuffer;
      }

      if ((response.responseCode === 301 || response.responseCode === 302 || response.responseCode === 307) &&
        response.header) {
        let headerObj = JSON.parse(JSON.stringify(response.header)) as Record<string, string>;
        let loc: string = headerObj['Location'] || '';
        if (!loc || loc.length === 0) {
          throw new Error('HTTP ' + response.responseCode + ': ' + currentUrl);
        }
        if (loc.startsWith('/')) {
          let idx = currentUrl.indexOf('://');
          let schemeEnd = idx + 3;
          let hostEnd = currentUrl.indexOf('/', schemeEnd);
          currentUrl = hostEnd > 0
            ? currentUrl.substring(0, hostEnd) + loc
            : currentUrl + loc;
        } else {
          currentUrl = loc;
        }
        console.info('[BikaHttpClient] 图片重定向: ' + currentUrl);
        continue;
      }

      throw new Error('HTTP ' + response.responseCode + ': ' + currentUrl);
    }

    throw new Error('重定向次数过多: ' + url);
  }
  /**
   * 延迟 Promise
   */
  static sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}