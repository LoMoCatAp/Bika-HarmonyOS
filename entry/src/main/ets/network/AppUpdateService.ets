import { rcp } from '@kit.RemoteCommunicationKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface AppRelease {
  version: string;
  body: string;
  url: string;
}

interface UpdateResponse {
  status: number;
  body: string;
  headers: Record<string, Object>;
}

const RELEASE_API: string = 'https://api.github.com/repos/LoMoCatAp/Bika-HarmonyOS/releases/latest';
const RELEASE_PAGE: string = 'https://github.com/LoMoCatAp/Bika-HarmonyOS/releases/tag/';

/** 更新检查独立联网，不复用哔咔的签名、凭据、固定 IP、DNS 或 TLS 配置。 */
export class AppUpdateService {
  private static rateLimitUntil: number = 0;

  private static headers(): Record<string, string> {
    return { 'Accept': 'application/vnd.github+json', 'User-Agent': 'Bika-HarmonyOS',
      'X-GitHub-Api-Version': '2026-03-10' };
  }

  private static versionParts(value: string): number[] {
    const text = value.trim().replace(/^[vV]/, '');
    if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(text)) {
      return [];
    }
    const parts = text.split('.').map((part: string): number => Number(part));
    return parts.every((part: number): boolean => Number.isSafeInteger(part)) ? parts : [];
  }

  static isNewer(candidate: string, current: string): boolean {
    const next = AppUpdateService.versionParts(candidate);
    const local = AppUpdateService.versionParts(current);
    if (local.length === 0) {
      throw new Error('无法读取当前版本，请重启应用后重试');
    }
    if (next.length === 0) {
      throw new Error('更新版本信息异常，请稍后重试');
    }
    for (let index = 0; index < 3; index++) {
      if (next[index] !== local[index]) {
        return next[index] > local[index];
      }
    }
    return false;
  }

  private static header(headers: Record<string, Object>, name: string): string {
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === name) {
        return String(headers[key]);
      }
    }
    return '';
  }

  private static parse(response: UpdateResponse): AppRelease {
    const limited = response.status === 429 || (response.status === 403
      && (AppUpdateService.header(response.headers, 'x-ratelimit-remaining') === '0'
      || /rate limit/i.test(response.body)));
    if (limited) {
      const now = Date.now();
      const retry = Number(AppUpdateService.header(response.headers, 'retry-after'));
      const reset = Number(AppUpdateService.header(response.headers, 'x-ratelimit-reset')) * 1000;
      const wait = Number.isFinite(retry) && retry > 0 ? retry * 1000
        : Number.isFinite(reset) && reset > now ? reset - now : 60000;
      AppUpdateService.rateLimitUntil = now + Math.min(24 * 60 * 60 * 1000, Math.max(60000, wait));
      throw new Error('GitHub 请求过于频繁，请稍后再检查更新');
    }
    if (response.status === 404) {
      throw new Error('暂无可用的正式发布版本，请稍后重试');
    }
    if (response.status !== 200) {
      throw new Error('GitHub 更新服务暂不可用（HTTP ' + response.status + '），请稍后重试');
    }
    let data: Record<string, Object>;
    try {
      data = JSON.parse(response.body) as Record<string, Object>;
    } catch (_err) {
      throw new Error('更新服务返回内容异常，请检查网络或代理后重试');
    }
    if (data === null || typeof data !== 'object' || Array.isArray(data)
      || typeof data['tag_name'] !== 'string' || data['draft'] !== false || data['prerelease'] !== false) {
      throw new Error('更新信息不完整，请稍后重试');
    }
    const tag = (data['tag_name'] as string).trim();
    if (AppUpdateService.versionParts(tag).length === 0) {
      throw new Error('更新版本信息异常，请稍后重试');
    }
    return { version: tag.replace(/^[vV]/, ''),
      body: typeof data['body'] === 'string' ? data['body'] as string : '',
      url: RELEASE_PAGE + encodeURIComponent(tag) };
  }

  private static async viaRcp(systemProxy: boolean): Promise<UpdateResponse> {
    const session = rcp.createSession({ requestConfiguration: {
      proxy: systemProxy ? 'system' : 'no-proxy',
      transfer: { timeout: { connectMs: 8000, transferMs: 10000 }, autoRedirect: false }
    } });
    try {
      const response = await session.fetch(new rcp.Request(RELEASE_API, 'GET', AppUpdateService.headers()));
      return { status: response.statusCode, body: response.toString() ?? '',
        headers: response.headers as Record<string, Object> };
    } finally {
      session.close();
    }
  }

  private static async viaHttp(systemProxy: boolean): Promise<UpdateResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(RELEASE_API, { method: http.RequestMethod.GET,
        header: AppUpdateService.headers(), expectDataType: http.HttpDataType.STRING,
        usingProxy: systemProxy, connectTimeout: 8000, readTimeout: 10000 });
      return { status: response.responseCode, body: typeof response.result === 'string' ? response.result : '',
        headers: response.header as Record<string, Object> };
    } finally {
      request.destroy();
    }
  }

  static async latest(systemProxy: boolean): Promise<AppRelease> {
    if (Date.now() < AppUpdateService.rateLimitUntil) {
      throw new Error('GitHub 请求过于频繁，请稍后再检查更新');
    }
    let response: UpdateResponse | undefined = undefined;
    let lastCode = 0;
    try {
      response = await AppUpdateService.viaRcp(systemProxy);
    } catch (err) {
      lastCode = Number((err as BusinessError).code) || 0;
      console.warn('[AppUpdateService] rcp connection failed, code=' + lastCode);
    }
    if (response !== undefined) {
      return AppUpdateService.parse(response);
    }
    try {
      response = await AppUpdateService.viaHttp(systemProxy);
    } catch (err) {
      lastCode = Number((err as BusinessError).code) || 0;
      console.warn('[AppUpdateService] http connection failed, code=' + lastCode);
    }
    if (response !== undefined) {
      return AppUpdateService.parse(response);
    }
    if (systemProxy) {
      // VPN 接管网络但没有 HTTP 系统代理时，最后按普通域名连接重试一次。
      try {
        response = await AppUpdateService.viaRcp(false);
      } catch (err) {
        lastCode = Number((err as BusinessError).code) || 0;
        console.warn('[AppUpdateService] direct connection failed, code=' + lastCode);
      }
      if (response !== undefined) {
        return AppUpdateService.parse(response);
      }
    }
    if (lastCode === 2300028 || lastCode === 1007900028) {
      throw new Error('连接 GitHub 超时，请检查网络或代理后重试');
    }
    throw new Error('无法连接 GitHub，请检查网络或代理后重试'
      + (lastCode > 0 ? '（代码 ' + lastCode + '）' : ''));
  }
}
