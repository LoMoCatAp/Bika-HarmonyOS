/**
 * 全局常量定义
 * 包含哔咔 API 常量、网络配置与设计语言颜色
 */

// ═══════════════════════ 哔咔 API 常量 ═══════════════════════

/** API 基础地址：哔咔官方国内反代线路（国内 DNS 正常解析） */
export const BIKA_API_BASE: string = 'https://picaapi.go2778.com';

/** API 主域名（Host 头用） */
export const BIKA_API_HOST: string = 'picaapi.picacomic.com';

/** 引导接口主机（BIKA 同款 BOOTSTRAP_HOST，先 HTTPS 再 HTTP 回退） */
export const BIKA_INIT_HOST: string = '68.183.234.72';

/** 默认直连 IP 池（首项 104.21.20.188）。
 *  init 引导在后台异步刷新后追加新地址；默认池本身立即可用，不依赖 init。 */
export const BIKA_FALLBACK_IPS: string[] = ['104.21.20.188'];

/** DoH 解析端点（腾讯 doh.pub，国内可达且返回 picaapi 真实 Cloudflare IP，
 *  绕开运营商 DNS 污染；域名模式下 http 模块用它解析） */
export const BIKA_DOH_URL: string = 'https://doh.pub/dns-query';

/** API Key（哔咔官方客户端内置，所有第三方客户端通用） */
export const BIKA_API_KEY: string = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';

/** HMAC-SHA256 签名密钥 */
export const BIKA_SECRET_KEY: string = '~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';

/** 签名输出编码：'hex'（BIKA 上线客户端同款）| 'base64'（社区广泛流传的签名方式） */
export const SIGN_ENCODING: string = 'hex';

/** Accept 头（哔咔服务端强校验，不能是普通 application/json） */
export const BIKA_ACCEPT: string = 'application/vnd.picacomic.com.v1+json';

/** 伪装的客户端版本信息。
 *  当前服务端接受的值：哔咔对旧版本头 2.2.1.2.3.3 的请求
 *  以 1023 话术拒绝，必须用新版本号。 */
export const APP_CHANNEL: string = '1'; // 1=电信 2=联通 3=移动
export const APP_VERSION: string = '2.2.1.3.3.4';
export const APP_BUILD_VERSION: string = '45';

/** 固定 nonce（服务端不查重） */
export const BIKA_FIXED_NONCE: string = '4ce7a7aa759b40f794d189a88b84aba8';
export const APP_PLATFORM: string = 'android';
export const APP_UUID: string = 'defaultUuid';
export const IMAGE_QUALITY: string = 'original';

/** 默认重试次数 */
export const DEFAULT_RETRY_TIMES: number = 3;

// ═══════════════════════ 图片服务器 ═══════════════════════

/** 图片镜像服务器池（go2778 官方国内镜像优先） */
export const IMAGE_HOST_POOL: string[] = [
  'https://s3.go2778.com',
  'https://storage-b.go2778.com',
  'https://img.go2778.com',
  'https://storage.tipatipa.xyz',
  'https://storage.diwodiwo.xyz'
];

// ═══════════════════════ 首页频道（BIKA DefaultChannels 同构） ═══════════════════════

/** 频道类型：决定列表页使用哪个 API */
export type ChannelKind = 'recommend' | 'leaderboard' | 'recent' | 'random' | 'board' | 'topic';

/** 频道项 */
export interface BikaChannel {
  label: string;
  icon: Resource;
  kind: ChannelKind;
}

/** 首页默认频道清单 */
export const DEFAULT_CHANNELS: BikaChannel[] = [
  { label: '推荐', icon: $r('app.media.ic_bika'), kind: 'recommend' },
  { label: '排行榜', icon: $r('app.media.ic_cat_ranking'), kind: 'leaderboard' },
  { label: '留言板', icon: $r('app.media.ic_cat_message_board'), kind: 'board' },
  { label: '最近更新', icon: $r('app.media.ic_cat_recent'), kind: 'recent' },
  { label: '随机本子', icon: $r('app.media.ic_cat_random'), kind: 'random' },
  { label: '大家都在看', icon: $r('app.media.ic_cat_trending'), kind: 'topic' },
  { label: '大濕推薦', icon: $r('app.media.ic_cat_master_choice'), kind: 'topic' },
  { label: '那年今天', icon: $r('app.media.ic_cat_history'), kind: 'topic' },
  { label: '官方都在看', icon: $r('app.media.ic_cat_staff_pick'), kind: 'topic' },
  { label: '嗶咔漢化', icon: $r('app.media.ic_cat_translated'), kind: 'topic' },
  { label: '全彩', icon: $r('app.media.ic_cat_full_color'), kind: 'topic' },
  { label: '長篇', icon: $r('app.media.ic_cat_long'), kind: 'topic' },
  { label: '同人', icon: $r('app.media.ic_cat_doujin'), kind: 'topic' },
  { label: '短篇', icon: $r('app.media.ic_cat_short'), kind: 'topic' },
  { label: '單行本', icon: $r('app.media.ic_cat_tankoubon'), kind: 'topic' },
  { label: 'CG雜圖', icon: $r('app.media.ic_cat_cg'), kind: 'topic' },
  { label: '英語 ENG', icon: $r('app.media.ic_cat_english'), kind: 'topic' },
  { label: '生肉', icon: $r('app.media.ic_cat_raw'), kind: 'topic' },
  { label: 'WEBTOON', icon: $r('app.media.ic_cat_webtoon'), kind: 'topic' },
  { label: '歐美', icon: $r('app.media.ic_cat_western'), kind: 'topic' },
  { label: 'Cosplay', icon: $r('app.media.ic_cat_cosplay'), kind: 'topic' },
  { label: '純愛', icon: $r('app.media.ic_cat_vanilla'), kind: 'topic' },
  { label: '百合花園', icon: $r('app.media.ic_cat_yuri'), kind: 'topic' },
  { label: '耽美花園', icon: $r('app.media.ic_cat_yaoi'), kind: 'topic' },
  { label: '偽娘哲學', icon: $r('app.media.ic_cat_crossdress'), kind: 'topic' },
  { label: '後宮閃光', icon: $r('app.media.ic_cat_harem'), kind: 'topic' },
  { label: '扶他樂園', icon: $r('app.media.ic_cat_futanari'), kind: 'topic' },
  { label: '姐姐系', icon: $r('app.media.ic_cat_sister_big'), kind: 'topic' },
  { label: '妹妹系', icon: $r('app.media.ic_cat_sister_little'), kind: 'topic' },
  { label: 'SM', icon: $r('app.media.ic_cat_bdsm'), kind: 'topic' },
  { label: '性轉換', icon: $r('app.media.ic_cat_gender_bender'), kind: 'topic' },
  { label: '足の恋', icon: $r('app.media.ic_cat_foot'), kind: 'topic' },
  { label: '人妻', icon: $r('app.media.ic_cat_milf'), kind: 'topic' },
  { label: 'NTR', icon: $r('app.media.ic_cat_ntr'), kind: 'topic' },
  { label: '強暴', icon: $r('app.media.ic_cat_forced'), kind: 'topic' },
  { label: '非人類', icon: $r('app.media.ic_cat_monster'), kind: 'topic' },
  { label: '重口地帶', icon: $r('app.media.ic_cat_hardcore'), kind: 'topic' },
  { label: '圓神領域', icon: $r('app.media.ic_cat_madoka'), kind: 'topic' },
  { label: '碧藍幻想', icon: $r('app.media.ic_cat_granblue'), kind: 'topic' },
  { label: '艦隊收藏', icon: $r('app.media.ic_cat_kancolle'), kind: 'topic' },
  { label: 'Love Live', icon: $r('app.media.ic_cat_lovelive'), kind: 'topic' },
  { label: 'SAO 刀劍神域', icon: $r('app.media.ic_cat_sao'), kind: 'topic' },
  { label: 'Fate', icon: $r('app.media.ic_cat_fate'), kind: 'topic' },
  { label: '東方', icon: $r('app.media.ic_cat_touhou'), kind: 'topic' },
  { label: '禁書目錄', icon: $r('app.media.ic_cat_index'), kind: 'topic' }
];

// ═══════════════════════ 排序方式 ═══════════════════════

/** 首页排序选项（s 参数合法值：UA/CA/da/dd/ld/vd） */
export interface SortOption {
  key: string;
  label: string;
}

export const SORT_OPTIONS: SortOption[] = [
  { key: 'dd', label: '最新' },
  { key: 'da', label: '最旧' },
  { key: 'ld', label: '最多爱心' },
  { key: 'vd', label: '最多观看' }
];

// ═══════════════════════ 设计语言颜色（哔咔粉主题，跟随深浅色模式） ═══════════════════════
// 全部使用 $r 资源引用，base/element/color.json + dark/element/color.json 双份定义

/** 主色：哔咔粉 */
export const COLOR_PRIMARY: Resource = $r('app.color.bika_primary');
/** 主色浅底（选中态浅背景、次级按钮） */
export const COLOR_PRIMARY_TINT: Resource = $r('app.color.bika_primary_tint');
/** 主色浅底 2（标签背景） */
export const COLOR_PRIMARY_TINT_2: Resource = $r('app.color.bika_primary_tint2');
/** 主色描边（标签边框） */
export const COLOR_PRIMARY_BORDER: Resource = $r('app.color.bika_primary_border');
/** 主色禁用态 */
export const COLOR_PRIMARY_DISABLED: Resource = $r('app.color.bika_primary_disabled');
/** 已收藏状态背景 */
export const COLOR_FAVORITED_BG: Resource = $r('app.color.bika_favorited_bg');

/** 页面背景 */
export const COLOR_BG: Resource = $r('app.color.bika_bg');
/** 区块背景 */
export const COLOR_BG_SECTION: Resource = $r('app.color.bika_bg_section');
/** 卡片背景 */
export const COLOR_CARD: Resource = $r('app.color.bika_card');
/** 图片占位 */
export const COLOR_PLACEHOLDER: Resource = $r('app.color.bika_placeholder');
/** 输入框背景 */
export const COLOR_INPUT_BG: Resource = $r('app.color.bika_input_bg');
/** 顶部毛玻璃浮层背景 */
export const COLOR_GLASS_TOP: Resource = $r('app.color.bika_glass_top');
/** 分隔线 */
export const COLOR_DIVIDER: Resource = $r('app.color.bika_divider');
/** 白色（按钮文字等，深色模式仍为白） */
export const COLOR_WHITE: Resource = $r('app.color.bika_white');

/** 标题文字 */
export const COLOR_TEXT_TITLE: Resource = $r('app.color.bika_text_title');
/** 次要文字 */
export const COLOR_TEXT_SECONDARY: Resource = $r('app.color.bika_text_secondary');
/** 提示文字 */
export const COLOR_TEXT_HINT: Resource = $r('app.color.bika_text_hint');
/** 禁用文字 */
export const COLOR_TEXT_DISABLED: Resource = $r('app.color.bika_text_disabled');

/** 阅读器暗色背景 */
export const COLOR_READER_BG: Resource = $r('app.color.bika_reader_bg');
/** 阅读器工具栏半透明背景 */
export const COLOR_READER_TOOLBAR_BG: Resource = $r('app.color.bika_reader_toolbar_bg');
/** 阅读器禁用按钮背景 */
export const COLOR_READER_TOOLBAR_DISABLED: Resource = $r('app.color.bika_reader_toolbar_disabled');
/** 阅读器激活按钮背景 */
export const COLOR_READER_TOOLBAR_ACTIVE: Resource = $r('app.color.bika_reader_toolbar_active');
/** 阅读器弱文字 */
export const COLOR_READER_TEXT_MUTED: Resource = $r('app.color.bika_reader_text_muted');
