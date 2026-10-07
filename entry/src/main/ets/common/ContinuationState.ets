/**
 * 应用接续（手机 ↔ 平板）：源端「当前页面描述符」。
 *
 * 目标：**每个页面都能接续**——在首页 / 频道页 / 作品详情页 / 阅读器 / 我的子页 / 搜索页
 * 触发接续时，目标端落到同一个页面（带上必要参数）；只有描述符为空或解析失败才 REJECT。
 *
 * 载体是 AppStorage 内存态（key = CONTINUATION_ROUTE_KEY，值为 JSON 字符串）：
 *   - 各页面 onPageShow / 进入时 publishContinuationRoute 发布自己；
 *   - 阅读器额外维护实时 page（CONTINUATION_READING_KEY）；
 *   - 页面被覆盖时由上层页面的 onPageShow 重新发布，保证描述符始终对应当前可见页面。
 */

/** AppStorage key：当前阅读位置（阅读器实时维护，兼容旧逻辑） */
export const CONTINUATION_READING_KEY: string = 'bika_current_reading';
/** AppStorage key：当前页面描述符（JSON 字符串） */
export const CONTINUATION_ROUTE_KEY: string = 'bika_continuation_route';
/** AppStorage key：「我的」当前打开的子页标识（'' 表示停留在「我的」根页） */
export const CONTINUATION_PROFILE_SUBPAGE_KEY: string = 'bika_profile_subpage_current';

/** 路由标识 */
export const ROUTE_HOME: string = 'home';
export const ROUTE_CHANNEL_LIST: string = 'ChannelListPage';
export const ROUTE_COMIC_DETAIL: string = 'ComicDetailPage';
export const ROUTE_READER: string = 'ReaderPage';
export const ROUTE_PROFILE_SUBPAGE: string = 'profile_subpage';
export const ROUTE_SEARCH: string = 'SearchPage';
export const ROUTE_SEARCH_RESULT: string = 'SearchResultPage';

/** 当前阅读位置（阅读器实时维护） */
export interface CurrentReadingState {
  comicId: string;
  comicTitle: string;
  order: number;
  page: number;
  coverUrl: string;
  timestamp: number;
}

/** 页面参数（各 route 只填自己需要的最小字段） */
export interface ContinuationRouteParams {
  comicId?: string;
  comicTitle?: string;
  coverUrl?: string;
  order?: number;
  page?: number;
  /** ChannelListPage：频道名与类型 */
  label?: string;
  kind?: string;
  /** profile_subpage：子页标识（favourites/history/settings/...） */
  subpage?: string;
  /** home：页签下标（0 首页 / 1 我的） */
  tab?: number;
  /** SearchResultPage：关键词 */
  keyword?: string;
}

/** 当前页面描述符 */
export interface ContinuationRouteState {
  route: string;
  params: ContinuationRouteParams;
  timestamp: number;
}

/** 发布「当前页面」；所有页面在 onPageShow / 进入时调用 */
export function publishContinuationRoute(route: string, params: ContinuationRouteParams): void {
  try {
    let state: ContinuationRouteState = { route: route, params: params, timestamp: Date.now() };
    AppStorage.setOrCreate(CONTINUATION_ROUTE_KEY, JSON.stringify(state));
    // 便于自测 / 排障：只打 route，不含页面参数与作品信息
    console.info('[Continuation] publish route = ' + route);
  } catch (err) {
    console.error('[Continuation] publish route failed: ' + JSON.stringify(err));
  }
}

/** 清除「当前页面」（离开页面且没有下层页面重新发布时使用） */
export function clearContinuationRoute(): void {
  try {
    AppStorage.setOrCreate(CONTINUATION_ROUTE_KEY, '');
  } catch (err) {
    console.error('[Continuation] clear route failed: ' + JSON.stringify(err));
  }
}

/** 读取「当前页面」；为空 / 解析失败返回 null（源端据此 REJECT） */
export function readContinuationRoute(): ContinuationRouteState | null {
  try {
    let raw: string = AppStorage.get<string>(CONTINUATION_ROUTE_KEY) ?? '';
    if (raw.length === 0) {
      return null;
    }
    let state = JSON.parse(raw) as ContinuationRouteState;
    if (state === null || state === undefined || state.route === undefined || state.route.length === 0) {
      return null;
    }
    return state;
  } catch (err) {
    return null;
  }
}
