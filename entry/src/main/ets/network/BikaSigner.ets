import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import {
  BIKA_API_KEY,
  BIKA_SECRET_KEY,
  BIKA_ACCEPT,
  SIGN_ENCODING,
  APP_CHANNEL,
  APP_VERSION,
  APP_BUILD_VERSION,
  APP_PLATFORM,
  APP_UUID,
  IMAGE_QUALITY,
  BIKA_FIXED_NONCE
} from '../common/Constants';

/**
 * 哔咔请求签名器
 *
 * 每个请求需要携带 HMAC-SHA256 签名头：
 *   raw = (path + time + nonce + method + apiKey).toLowerCase()
 *   signature = HMAC-SHA256(secretKey, raw)
 *
 * 参考实现：BIKA (github.com/shizq123/BIKA) BikaSignatureAuth.kt
 */
export class BikaSigner {
  private static textEncoder: util.TextEncoder = new util.TextEncoder();
  private static base64Helper: util.Base64Helper = new util.Base64Helper();

  /**
   * 生成 nonce（32 位小写十六进制）。
   * 对齐 haka_comic：固定值即可（服务端不查重），避免真机随机源异常引入差异。
   */
  static generateNonce(): string {
    return BIKA_FIXED_NONCE;
  }

  /**
   * 获取当前 Unix 时间戳（秒）
   */
  static currentTime(): string {
    return Math.floor(Date.now() / 1000).toString();
  }

  /**
   * 计算 HMAC-SHA256 签名
   * @param path 请求路径（不含域名，如 "auth/sign-in"；GET 请求需包含查询串）
   * @param time 时间戳字符串
   * @param nonce 随机串
   * @param method "GET" | "POST" | "PUT"
   * @returns 签名（hex 或 base64，由 SIGN_ENCODING 决定）
   */
  static async sign(path: string, time: string, nonce: string, method: string): Promise<string> {
    let raw = (path + time + nonce + method + BIKA_API_KEY).toLowerCase();
    let rawBytes = BikaSigner.textEncoder.encodeInto(raw);
    let keyBytes = BikaSigner.textEncoder.encodeInto(BIKA_SECRET_KEY);

    let mac = cryptoFramework.createMac('SHA256');
    let keyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    let symKey = await keyGenerator.convertKey({ data: keyBytes });
    await mac.init(symKey);
    await mac.update({ data: rawBytes });
    let out = await mac.doFinal();

    if (SIGN_ENCODING === 'base64') {
      return BikaSigner.base64Helper.encodeToStringSync(out.data);
    }
    return BikaSigner.toHexString(out.data);
  }

  /**
   * 构建带签名的完整请求头
   * @param path 请求路径（GET 含查询串）
   * @param method 请求方法
   * @param token 登录令牌（未登录传空串）
   */
  static async buildHeaders(path: string, method: string, token: string): Promise<Record<string, string>> {
    let time = BikaSigner.currentTime();
    let nonce = BikaSigner.generateNonce();
    let signature = await BikaSigner.sign(path, time, nonce, method);

    let headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=UTF-8',
      'api-key': BIKA_API_KEY,
      'accept': BIKA_ACCEPT,
      'app-channel': APP_CHANNEL,
      'time': time,
      'nonce': nonce,
      'signature': signature,
      'app-version': APP_VERSION,
      'app-uuid': APP_UUID,
      'app-platform': APP_PLATFORM,
      'app-build-version': APP_BUILD_VERSION,
      'image-quality': IMAGE_QUALITY,
      'User-Agent': 'okhttp/3.8.1'
    };

    if (token && token.length > 0) {
      // 哔咔的 Authorization 头携带裸 token，无 Bearer 前缀
      headers['Authorization'] = token;
    }
    return headers;
  }

  /**
   * 字节数组转小写十六进制字符串
   */
  private static toHexString(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      let b = bytes[i] as number;
      hex += (b < 16 ? '0' : '') + b.toString(16);
    }
    return hex;
  }
}
