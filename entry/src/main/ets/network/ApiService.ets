import { BikaHttpClient, BikaHttpResponse } from './BikaHttpClient';
import { BikaRcpClient } from './BikaRcpClient';
import { BikaSigner } from './BikaSigner';
import { ApiRouteManager } from './ApiRouteManager';
import { CacheManager } from '../common/CacheManager';
import { BIKA_API_HOST, BIKA_API_BASE } from '../common/Constants';
import {
  BikaComicDetail,
  BikaComicSummary,
  BikaEpDoc,
  BikaPageDoc,
  BikaPaged,
  BikaSignInData,
  BikaUserProfile,
  BikaKnightUser,
  BikaComment,
  BikaNotification,
  toNum
} from '../models/Comic';

/**
 * 哔咔 API 服务层
 * 封装所有 PicACG API 调用
 *
 * 参考 BIKA (github.com/shizq123/BIKA) 的 BikaDataSource.kt：
 * - 每个请求携带 HMAC-SHA256 签名头
 * - 响应统一信封 { code, message, data }
 * - token 失效（401）时用存储的凭据自动重登一次
 */

/** 响应信封 */
interface BikaEnvelope<T> {
  code: number | string;
  message: string;
  data: T;
  /** 业务错误码（HTTP 400 时服务端放在 error 字段，如 1019） */
  error?: string;
}

/** 服务器错误码 → 中文提示 */
const ERROR_MESSAGES: Record<string, string> = {
  '1000': '请求头不合法',
  '1004': '账号或密码错误，请检查后重试',
  '1005': '登录已过期，请重新登录',
  '1007': '数据不存在或已被删除',
  '1008': '该邮箱已被注册',
  '1009': '用户名已被占用',
  '1014': '该漫画暂时无法查看（审核中）',
  '1019': '等级不足或评论权限受限，无法发表评论',
  '1031': '等级不足，无法发表评论'
};

/** 列表页结果 */
export interface ComicsPageResult {
  comics: BikaComicSummary[];
  pages: number;
}

/** 注册请求体 */
interface RegisterBody {
  email: string;
  name: string;
  password: string;
  birthday: string;
  gender: string;
  question1: string;
  question2: string;
  question3: string;
  answer1: string;
  answer2: string;
  answer3: string;
}

export class ApiService {
  private static instance: ApiService | null = null;

  private token: string = '';
  private email: string = '';
  private password: string = '';
  /** 401 自动重登的单飞 Promise（并发 401 只触发一次重登） */
  private reloginPromise: Promise<boolean> | null = null;

  /** 频控熔断截止时间戳：服务端返回 too many request 后进入全局冷却，避免反复重试延长封锁 */
  private static rateLimitUntil: number = 0;
  /** 连续触发频控的档位（0=未触发；每次触发 +1，任一请求成功后清零） */
  private static rateLimitLevel: number = 0;
  /** 频控冷却时长档位表：90s → 5min → 10min → 30min → 60min。
   *  实测哔咔封锁窗口可达 30 分钟以上，且窗口内每次重试都会续期，
   *  因此连续触发时逐档加码，最终等待足够长让窗口自然过期。 */
  private static readonly RATE_LIMIT_COOLDOWN_STEPS: number[] = [
    90 * 1000,
    5 * 60 * 1000,
    10 * 60 * 1000,
    30 * 60 * 1000,
    60 * 60 * 1000
  ];

  /** 当前频控熔断剩余秒数（UI 倒计时用） */
  static getRateLimitRemainSec(): number {
    let remain = Math.ceil((ApiService.rateLimitUntil - Date.now()) / 1000);
    return remain > 0 ? remain : 0;
  }

  /** 上次真正发出 API 请求的时间戳。
   *  实测哔咔对同一出口 IP 按「低频窗口」限流：窗口内第 2 个请求起返回 1023。
   *  sign-in 前据此等待，保证登录请求是窗口内第 1 个请求。 */
  private static lastApiRequestAt: number = 0;
  /** sign-in 冷窗口时长：与上一次 API 请求的最小间隔 */
  private static readonly SIGNIN_COOLDOWN_MS: number = 60 * 1000;

  /** 最近一次请求的传输通道信息（诊断：h3 / h3-fail / ip-x） */
  static lastTransport: string = 'none';


  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  static destroyInstance(): void {
    if (ApiService.instance) {
      ApiService.instance = null;
    }
  }

  private constructor() {
    // 恢复上次登录的凭据（异步，首次请求前生效即可）
    CacheManager.getInstance().then(cache => {
      let self = ApiService.instance;
      if (self === null) {
        return;
      }
      self.token = cache.getToken();
      self.email = cache.getEmail();
      self.password = cache.getPassword();
      if (self.token.length > 0) {
        AppStorage.set('isLoggedIn', true);
      }
    }).catch((err: Error) => {
      console.error(`[ApiService] 恢复凭据失败: ${err.message}`);
    });
  }

  // ═══════════════ 认证 ═══════════════

  getToken(): string {
    return this.token;
  }

  isLoggedIn(): boolean {
    return this.token.length > 0;
  }

  /**
   * 登录
   * POST auth/sign-in，body: {"email","password"}（明文，与 BIKA 客户端一致）
   * @returns token
   */
  async signIn(email: string, password: string): Promise<string> {
    // 冷窗口等待：保证 sign-in 是哔咔低频窗口内第 1 个请求（否则必撞 1023）
    let wait = ApiService.lastApiRequestAt + ApiService.SIGNIN_COOLDOWN_MS - Date.now();
    if (wait > 0) {
      console.info('[ApiService] sign-in 冷窗口等待 ' + Math.ceil(wait / 1000) + 's');
      await this.sleep(wait);
    }
    let body = JSON.stringify({ email: email, password: password });
    let data = await this.request<BikaSignInData>('auth/sign-in', 'POST', body, false);
    if (!data || !data.token) {
      throw new Error('登录响应异常：未返回 token');
    }
    this.token = data.token;
    this.email = email;
    this.password = password;
    let cache = await CacheManager.getInstance();
    cache.saveToken(this.token);
    cache.saveCredentials(email, password);
    AppStorage.set('isLoggedIn', true);
    return this.token;
  }

  /**
   * 退出登录
   */
  async logout(): Promise<void> {
    this.token = '';
    this.email = '';
    this.password = '';
    let cache = await CacheManager.getInstance();
    cache.clearAuth();
    AppStorage.set('isLoggedIn', false);
  }

  /**
   * 401 时用存储的凭据重登（单飞：并发调用共享同一次重登）
   * @returns 是否重登成功
   */
  private ensureRelogin(): Promise<boolean> {
    if (!this.reloginPromise) {
      this.reloginPromise = (async (): Promise<boolean> => {
        try {
          if (this.email.length === 0 || this.password.length === 0) {
            return false;
          }
          console.info('[ApiService] token 失效，自动重新登录');
          let body = JSON.stringify({ email: this.email, password: this.password });
          let data = await this.request<BikaSignInData>('auth/sign-in', 'POST', body, false);
          if (data && data.token) {
            this.token = data.token;
            let cache = await CacheManager.getInstance();
            cache.saveToken(this.token);
            return true;
          }
          return false;
        } catch (err) {
          console.error(`[ApiService] 自动重登失败: ${JSON.stringify(err)}`);
          return false;
        } finally {
          this.reloginPromise = null;
        }
      })();
    }
    return this.reloginPromise;
  }

  // ═══════════════ 业务接口 ═══════════════

  /**
   * 获取用户资料
   * GET users/profile → data.user
   */
  async getUserProfile(): Promise<BikaUserProfile> {
    let data = await this.request<Record<string, Object>>('users/profile', 'GET', null, true);
    return data['user'] as BikaUserProfile;
  }

  /**
   * 获取分类列表
   * GET categories → data.categories: string[]
   */
  async getCategories(): Promise<string[]> {
    let data = await this.request<Record<string, Object>>('categories', 'GET', null, true);
    let categories = data['categories'] as string[];
    return categories || [];
  }

  /**
   * 详情页相关推荐（BIKA getRecommendations）
   * GET comics/{id}/recommendation → data.comics[]
   */
  async getRecommendationsFor(comicId: string): Promise<BikaComicSummary[]> {
    let data = await this.request<Record<string, Object>>('comics/' + comicId + '/recommendation', 'GET', null, true);
    let comics = data['comics'] as BikaComicSummary[];
    return comics || [];
  }

  /**
   * 骑士榜（BIKA getKnightLeaderboard）
   * GET comics/knight-leaderboard → data.users[]
   */
  async getKnightLeaderboard(): Promise<BikaKnightUser[]> {
    let data = await this.request<Record<string, Object>>('comics/knight-leaderboard', 'GET', null, true);
    let users = data['users'] as BikaKnightUser[];
    return users || [];
  }

  /**
   * 漫画评论（BIKA getComments）
   * GET comics/{id}/comments?page= → data.comments.docs[]
   */
  async getComicComments(comicId: string, page: number): Promise<BikaComment[]> {
    let data = await this.request<Record<string, Object>>(
      'comics/' + comicId + '/comments?page=' + page, 'GET', null, true);
    let comments = data['comments'] as Record<string, Object>;
    if (comments && comments['docs']) {
      return comments['docs'] as BikaComment[];
    }
    return [];
  }

  /**
   * 注册新账号
   * POST auth/register，body: email/name/password/birthday/gender/question1-3/answer1-3
   */
  async register(email: string, password: string, name: string, birthday: string, gender: string,
    questions: string[], answers: string[]): Promise<void> {
    let bodyObj: RegisterBody = {
      email: email,
      name: name,
      password: password,
      birthday: birthday,
      gender: gender,
      question1: questions[0],
      question2: questions[1],
      question3: questions[2],
      answer1: answers[0],
      answer2: answers[1],
      answer3: answers[2]
    };
    await this.request<Record<string, Object>>('auth/register', 'POST', JSON.stringify(bodyObj), false);
  }

  /**
   * 修改密码
   * PUT users/password，body: {old_password, password}
   */
  async changePassword(oldPassword: string, newPassword: string): Promise<void> {
    await this.request<Record<string, Object>>(
      'users/password', 'PUT', JSON.stringify({ old_password: oldPassword, password: newPassword }), true);
  }

  /**
   * 更新个人签名（仅 slogan，与 bika 一致）
   * PUT users/profile
   */
  async updateProfile(slogan: string): Promise<void> {
    await this.request<Record<string, Object>>(
      'users/profile', 'PUT', JSON.stringify({ slogan: slogan }), true);
  }

  /**
   * 签到（BIKA punchIn）
   * POST users/punch-in
   */
  async punchIn(): Promise<void> {
    // 签到接口无请求体（BIKA punchIn 同款）
    await this.request<Record<string, Object>>('users/punch-in', 'POST', null, true);
  }

  /**
   * 搜索关键词推荐（BIKA getKeywords）
   * GET keywords → data.keywords[]
   */
  async getKeywords(): Promise<string[]> {
    let data = await this.request<Record<string, Object>>('keywords', 'GET', null, true);
    let keywords = data['keywords'] as string[];
    return keywords || [];
  }

  /**
   * 高级搜索（BIKA advancedSearch）
   * POST comics/advanced-search?page=，body: {"keyword","sort","categories":[]}
   */
  async advancedSearch(keyword: string, sort: string, page: number): Promise<ComicsPageResult> {
    let body = JSON.stringify({ keyword: keyword, sort: sort, categories: [] });
    let data = await this.request<Record<string, Object>>(
      'comics/advanced-search?page=' + page, 'POST', body, true);
    let paged = data['comics'] as BikaPaged<BikaComicSummary>;
    return {
      comics: paged.docs || [],
      pages: toNum(paged.pages)
    };
  }

  /**
   * 我的收藏（BIKA getFavouriteComics）
   * GET users/favourite?page=&s= → data.comics.paged
   */
  async getFavourites(sort: string, page: number): Promise<ComicsPageResult> {
    let data = await this.request<Record<string, Object>>(
      'users/favourite?page=' + page + '&s=' + encodeURIComponent(sort), 'GET', null, true);
    let paged = data['comics'] as BikaPaged<BikaComicSummary>;
    return {
      comics: paged.docs || [],
      pages: toNum(paged.pages)
    };
  }

  /**
   * 通知列表（BIKA getNotifications）
   * GET users/notifications?page= → data.notifications.docs[]
   */
  async getNotifications(page: number): Promise<BikaNotification[]> {
    let data = await this.request<Record<string, Object>>(
      'users/notifications?page=' + page, 'GET', null, true);
    let notif = data['notifications'] as Record<string, Object>;
    if (notif && notif['docs']) {
      return notif['docs'] as BikaNotification[];
    }
    return [];
  }

  /**
   * 我的评论
   * GET users/my-comments?page= → data.comments.docs[]
   */
  async getMyComments(page: number): Promise<BikaComment[]> {
    let data = await this.request<Record<string, Object>>(
      'users/my-comments?page=' + page, 'GET', null, true);
    let comments = data['comments'] as Record<string, Object>;
    if (comments && comments['docs']) {
      return comments['docs'] as BikaComment[];
    }
    return [];
  }

  /**
   * 评论点赞 / 取消点赞
   * POST comments/{id}/like
   */
  async toggleCommentLike(commentId: string): Promise<void> {
    await this.request<Record<string, Object>>(
      'comments/' + commentId + '/like', 'POST', JSON.stringify({}), true);
  }

  /**
   * 评论的子回复列表
   * GET comments/{id}/childrens?page= → data.comments.docs[]
   */
  async getCommentChildren(commentId: string, page: number): Promise<BikaComment[]> {
    let data = await this.request<Record<string, Object>>(
      'comments/' + commentId + '/childrens?page=' + page, 'GET', null, true);
    let comments = data['comments'] as Record<string, Object>;
    if (comments && comments['docs']) {
      return comments['docs'] as BikaComment[];
    }
    return [];
  }

  /**
   * 发表漫画评论
   * POST comics/{id}/comments，body: {"content": "..."}
   */
  async postComicComment(comicId: string, content: string): Promise<void> {
    await this.request<Record<string, Object>>(
      'comics/' + comicId + '/comments', 'POST', JSON.stringify({ content: content }), true);
  }

  /**
   * 回复某条评论
   * POST comments/{commentId}，body: {"content": "..."}
   */
  async replyToComment(commentId: string, content: string): Promise<void> {
    await this.request<Record<string, Object>>(
      'comments/' + commentId, 'POST', JSON.stringify({ content: content }), true);
  }

  /**
   * 排行榜（BIKA getLeaderboard）
   * GET comics/leaderboard?tt=H24|D7|D30&ct=VC → data.comics[]
   */
  async getLeaderboard(tt: string): Promise<BikaComicSummary[]> {
    let data = await this.request<Record<string, Object>>(
      'comics/leaderboard?tt=' + tt + '&ct=VC', 'GET', null, true);
    let comics = data['comics'] as BikaComicSummary[];
    return comics || [];
  }

  /**
   * 随机本子（BIKA getRandomComics）
   * GET comics/random → data.comics[]
   */
  async getRandomComics(): Promise<BikaComicSummary[]> {
    let data = await this.request<Record<string, Object>>('comics/random', 'GET', null, true);
    let comics = data['comics'] as BikaComicSummary[];
    return comics || [];
  }

  /**
   * 分页获取分类下的漫画列表
   * GET comics?page=&c=&s=
   * @param category 分类名（空串表示全部）
   * @param sort 排序：dd最新/da最旧/ld最多爱心/vd最多观看
   */
  async getComics(category: string, sort: string, page: number): Promise<ComicsPageResult> {
    let query = `page=${page}&s=${encodeURIComponent(sort)}`;
    if (category && category.length > 0) {
      query += `&c=${encodeURIComponent(category)}`;
    }
    let data = await this.request<BikaPaged<BikaComicSummary>>(`comics?${query}`, 'GET', null, true);
    let paged = data as BikaPaged<BikaComicSummary>;
    return {
      comics: paged.docs || [],
      pages: toNum(paged.pages)
    };
  }

  /**
   * 获取漫画详情
   * GET comics/{id}
   */
  async getComicDetail(comicId: string): Promise<BikaComicDetail> {
    let data = await this.request<Record<string, Object>>(`comics/${comicId}`, 'GET', null, true);
    return data['comic'] as BikaComicDetail;
  }

  /**
   * 获取全部章节列表（自动翻页）
   * GET comics/{id}/eps?page=
   */
  async getAllEps(comicId: string): Promise<BikaEpDoc[]> {
    let all: BikaEpDoc[] = [];
    let page = 1;
    let pages = 1;
    do {
      let data = await this.request<Record<string, Object>>(
        `comics/${comicId}/eps?page=${page}`, 'GET', null, true);
      let eps = data['eps'] as BikaPaged<BikaEpDoc>;
      if (eps && eps.docs) {
        all = all.concat(eps.docs);
        pages = toNum(eps.pages);
      } else {
        break;
      }
      page++;
    } while (page <= pages);
    return all;
  }

  /**
   * 切换点赞状态（BIKA toggleComicLike）
   * POST comics/{id}/like
   */
  async toggleLike(comicId: string): Promise<void> {
    await this.request<Record<string, Object>>(
      'comics/' + comicId + '/like', 'POST', JSON.stringify({}), true);
  }

  /**
   * 切换收藏状态
   * POST comics/{id}/favourite，body: {"action":"favourite"|"un_favourite"}
   */
  async toggleFavourite(comicId: string, isFavourited: boolean): Promise<void> {
    let action = isFavourited ? 'un_favourite' : 'favourite';
    await this.request<Record<string, Object>>(
      `comics/${comicId}/favourite`, 'POST', JSON.stringify({ action: action }), true);
  }

  /**
   * 获取某章全部图片（自动翻页）
   * GET comics/{id}/order/{order}/pages?page=
   * @param order 1 起始的话数
   */
  async getChapterPages(comicId: string, order: number): Promise<BikaPageDoc[]> {
    let all: BikaPageDoc[] = [];
    let page = 1;
    let pages = 1;
    do {
      let data = await this.request<Record<string, Object>>(
        `comics/${comicId}/order/${order}/pages?page=${page}`, 'GET', null, true);
      let pagesData = data['pages'] as BikaPaged<BikaPageDoc>;
      if (pagesData && pagesData.docs) {
        all = all.concat(pagesData.docs);
        pages = toNum(pagesData.pages);
      } else {
        break;
      }
      page++;
    } while (page <= pages);
    return all;
  }

  // ═══════════════ 核心请求 ═══════════════

  /**
   * 发起带签名的 API 请求并解信封：
   * - 签名头与 BIKA BikaSignatureAuth 逐字段一致（Host 头指回真实域名）
   * - 一次请求内按 IP 池顺序逐个直连尝试
   * - 连接失败整体重试一次
   * - 401 时 TokenAuthenticator 语义：重登一次并重放请求（sign-in 自身不重登）
   * @param path 请求路径（GET 需含查询串）
   * @param method GET | POST | PUT
   * @param body JSON 字符串或 null
   * @param allowRelogin 401 时是否自动重登重试（sign-in 本身禁止）
   */
  private async request<T>(
    path: string,
    method: string,
    body: string | null,
    allowRelogin: boolean
  ): Promise<T> {
    // 默认直连池立即可用；init 引导后台异步刷新（非阻塞）
    ApiRouteManager.getInstance().ensureInitialized();

    // 频控熔断：冷却期内不再发请求，避免反复重试延长服务端封锁
    if (ApiService.rateLimitUntil > Date.now()) {
      let remain = ApiService.getRateLimitRemainSec();
      let unit = remain >= 60 ? Math.ceil(remain / 60) + ' 分钟' : remain + ' 秒';
      throw new Error('服务器请求过于频繁，请等约 ' + unit + ' 后再试（开关飞行模式更换 IP 可立即恢复）');
    }

    let lastErr: Error | null = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      // 记录真实发请求时间（sign-in 冷窗口依据）
      ApiService.lastApiRequestAt = Date.now();
      let headers = await BikaSigner.buildHeaders(path, method, this.token);
      // 调试：打印签名关键头，用于 PC 重放对比
      console.info('[ApiService][debug] ' + method + ' ' + path +
        ' time=' + headers['time'] + ' nonce=' + headers['nonce'] + ' sig=' + headers['signature']);

      let resp: BikaHttpResponse | null = null;
      let candidates = ApiRouteManager.getInstance().getCandidates();

      // ── 首选通道：rcp（域名 URL + 静态 DNS 映射直连 IP + 独立 TLS 栈，
      //     与 BIKA okhttp 完全同构：SNI/Host/证书校验全自动） ──
      try {
        let r = await BikaRcpClient.request(BIKA_API_BASE + '/' + path, method, headers, body || '');
        resp = { responseCode: r.responseCode, body: r.body };
        ApiService.lastTransport = 'rcp';
      } catch (err) {
        lastErr = err as Error;
        ApiService.lastTransport = 'rcp-fail(' + lastErr.message + ')';
        console.warn('[ApiService] rcp 通道失败: ' + lastErr.message + '，回退 http 模块直连');
      }

      // ── 回退通道：IP 直连 + 真实域名 SNI + Host 头 + HTTP/2 ──
      if (resp === null) {
        // 直连 IP 时必须携带真实域名 Host（BIKA okhttp URL=域名时的同款效果）
        headers['Host'] = BIKA_API_HOST;
        for (let ip of candidates) {
          let url = 'https://' + ip + '/' + path;
          try {
            if (method === 'GET') {
              resp = await BikaHttpClient.get(url, headers, 1, BIKA_API_HOST);
            } else if (method === 'PUT') {
              resp = await BikaHttpClient.put(url, body || '', headers, 1, BIKA_API_HOST);
            } else {
              resp = await BikaHttpClient.post(url, body || '', headers, 1, BIKA_API_HOST);
            }
            ApiService.lastTransport = 'ip-' + ip;
            break;
          } catch (err) {
            lastErr = err as Error;
            ApiService.lastTransport = 'ip-fail(' + ip + ':' + lastErr.message + ')';
            console.warn('[ApiService] 直连 ' + ip + ' 失败: ' + lastErr.message + '，尝试下一个');
          }
        }
      }
      if (resp === null) {
        // 双通道均失败：整体重试一次
        continue;
      }

      // HTTP 401：TokenAuthenticator 语义 —— 重登一次并重放（sign-in 自身不重登）
      if (resp.responseCode === 401 && allowRelogin) {
        let ok = await this.ensureRelogin();
        if (ok && attempt === 0) {
          continue;
        }
        throw new Error(ERROR_MESSAGES['1005']);
      }

      if (resp.body.length === 0) {
        throw new Error('服务端无响应 (HTTP ' + resp.responseCode + ')');
      }

      let envelope: BikaEnvelope<T>;
      try {
        envelope = JSON.parse(resp.body) as BikaEnvelope<T>;
      } catch {
        console.error('[ApiService] 响应解析失败 path=' + path + ' HTTP=' + resp.responseCode + ' body=' + resp.body.substring(0, 200));
        throw new Error('服务端响应解析失败 (HTTP ' + resp.responseCode + ')');
      }

      // 信封内的 code 可能是数字或字符串
      let code = Number(envelope.code);
      if (code === 401 && allowRelogin) {
        let ok = await this.ensureRelogin();
        if (ok && attempt === 0) {
          continue;
        }
      }
      if (code !== 200) {
        let msg = envelope.message || '';
        if (msg.toLowerCase().indexOf('too many') >= 0) {
          // 服务端限流：进入全局熔断，档位逐次递增（窗口内重试只会续期封锁）
          ApiService.rateLimitLevel++;
          if (path.indexOf('auth/sign-in') >= 0 && ApiService.rateLimitLevel < 2) {
            // 登录接口频控更严（防爆破），直接跳到 10 分钟档，避免连点续期
            ApiService.rateLimitLevel = 2;
          }
          let stepIdx = Math.min(ApiService.rateLimitLevel - 1, ApiService.RATE_LIMIT_COOLDOWN_STEPS.length - 1);
          let cooldown = ApiService.RATE_LIMIT_COOLDOWN_STEPS[stepIdx];
          ApiService.rateLimitUntil = Date.now() + cooldown;
          console.warn('[ApiService] 触发频控熔断 档位=' + ApiService.rateLimitLevel +
            ' 冷却=' + (cooldown / 60000) + 'min path=' + path + ' message=' + msg);
          throw new Error('服务器请求过于频繁，请等约 ' + Math.round(cooldown / 60000) +
            ' 分钟后再试（开关飞行模式更换 IP 可立即恢复）[' + ApiService.lastTransport + ']');
        }
        console.error('[ApiService] 请求失败 path=' + path + ' code=' + envelope.code + ' message=' + envelope.message);
        let key = String(envelope.code);
        let friendly = ERROR_MESSAGES[key];
        if (!friendly && envelope.error && envelope.error.length > 0) {
          friendly = ERROR_MESSAGES[String(envelope.error)];
        }
        if (friendly) {
          throw new Error(friendly);
        }
        throw new Error(envelope.message || ('请求失败 (' + code + ')'));
      }

      // 请求成功：清零频控退避档位
      ApiService.rateLimitLevel = 0;
      return envelope.data;
    }

    // 所有 IP 均不可达：家庭宽带直连 IP 即可访问；开 VPN 反而会因机房 IP 被哔咔拉黑而失败
    throw lastErr !== null
      ? new Error('无法连接哔咔服务器：请先关闭手机上的 VPN/加速器（含全局模式），用家庭宽带或手机流量直连后重试 [' + ApiService.lastTransport + ']')
      : new Error('网络连接失败，请检查网络后重试 [' + ApiService.lastTransport + ']');
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>(resolve => setTimeout(resolve, ms));
  }
}