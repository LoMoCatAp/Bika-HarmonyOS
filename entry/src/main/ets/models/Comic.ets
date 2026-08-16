import { IMAGE_HOST_POOL } from '../common/Constants';

/**
 * 哔咔数据模型
 * 原始接口（Bika* 前缀，对应服务端 JSON 字段，snake_case 保持原样）
 * 与展示视图模型（*ViewModel 后缀，camelCase）
 */

// ═══════════════════════ 原始 API 接口 ═══════════════════════

/** 图片媒体对象（封面、头像、章节图片通用） */
export interface BikaMedia {
  originalName?: string;
  path: string;
  fileServer: string;
}

/** 服务端分页包装（total/limit/page/pages 可能返回字符串，需 Number() 强转） */
export interface BikaPaged<T> {
  docs: T[];
  total: number | string;
  limit: number | string;
  page: number | string;
  pages: number | string;
}

/** 漫画摘要（列表/搜索/收藏等场景通用） */
export interface BikaComicSummary {
  _id: string;
  title: string;
  author: string;
  totalViews: number | string;
  totalLikes: number | string;
  pagesCount: number | string;
  epsCount: number | string;
  finished: boolean;
  categories: string[];
  tags?: string[];
  thumb: BikaMedia;
}

/** 漫画详情 */
export interface BikaComicDetail extends BikaComicSummary {
  description?: string;
  chineseTeam?: string;
  allowDownload?: boolean;
  isFavourite?: boolean;
  isLiked?: boolean;
  created_at?: string;
  updated_at?: string;
}

/** 章节（话） */
export interface BikaEpDoc {
  _id: string;
  title: string;
  order: number;
  updated_at?: string;
}

/** 章节内单页图片 */
export interface BikaPageDoc {
  _id: string;
  media: BikaMedia;
}

/** 分类接口响应 data */
export interface BikaCategoriesData {
  categories: string[];
}

/** 登录响应 data */
export interface BikaSignInData {
  token: string;
}

/** 骑士榜用户 */
export interface BikaKnightUser {
  _id: string;
  name: string;
  gender?: string;
  title?: string;
  slogan?: string;
  level?: number;
  exp?: number;
  avatar?: BikaMedia;
  comicsUploaded?: number;
  role?: string;
  verified?: boolean;
  character?: string;
}

/** 评论 */
export interface BikaComment {
  _id: string;
  content: string;
  likesCount?: number;
  totalComments?: number;
  created_at?: string;
  isLiked?: boolean;
  _user?: BikaCommentUser;
}

/** 通知 */
export interface BikaNotification {
  _id: string;
  content: string;
  created_at?: string;
  title?: string;
  type?: string;
  _comic?: BikaComicSummary;
}

/** 评论用户 */
export interface BikaCommentUser {
  _id?: string;
  name?: string;
  title?: string;
  level?: number;
  avatar?: BikaMedia;
  gender?: string;
}

/** 用户资料（users/profile 响应 data.user） */
export interface BikaUserProfile {
  _id: string;
  name: string;
  email?: string;
  gender?: string;
  title?: string;
  level?: number;
  exp?: number;
  verified?: boolean;
  isPunched?: boolean;
  slogan?: string;
  created_at?: string;
  birthday?: string;
  character?: string;
  avatar?: BikaMedia;
}

// ═══════════════════════ 视图模型 ═══════════════════════

/**
 * 漫画卡片视图模型
 */
export class ComicViewModel {
  id: string = '';
  title: string = '';
  author: string = '';
  coverUrl: string = '';
  categories: string[] = [];
  finished: boolean = false;
  epsCount: number = 0;
  pagesCount: number = 0;
  totalViews: number = 0;
  totalLikes: number = 0;

  static fromSummary(summary: BikaComicSummary): ComicViewModel {
    let vm = new ComicViewModel();
    vm.id = summary._id;
    vm.title = summary.title;
    vm.author = summary.author || '未知作者';
    vm.categories = summary.categories || [];
    vm.finished = !!summary.finished;
    vm.epsCount = toNum(summary.epsCount);
    vm.pagesCount = toNum(summary.pagesCount);
    vm.totalViews = toNum(summary.totalViews);
    vm.totalLikes = toNum(summary.totalLikes);
    vm.coverUrl = buildImageUrl(summary.thumb);
    return vm;
  }
}

/**
 * 漫画详情视图模型
 */
export class ComicDetailViewModel extends ComicViewModel {
  description: string = '';
  chineseTeam: string = '';
  updated_at: string = '';

  static fromDetail(detail: BikaComicDetail): ComicDetailViewModel {
    let vm = new ComicDetailViewModel();
    vm.id = detail._id;
    vm.title = detail.title;
    vm.author = detail.author || '未知作者';
    vm.categories = detail.categories || [];
    vm.finished = !!detail.finished;
    vm.epsCount = toNum(detail.epsCount);
    vm.pagesCount = toNum(detail.pagesCount);
    vm.totalViews = toNum(detail.totalViews);
    vm.totalLikes = toNum(detail.totalLikes);
    vm.coverUrl = buildImageUrl(detail.thumb);
    vm.description = detail.description || '';
    vm.chineseTeam = detail.chineseTeam || '';
    vm.updated_at = detail.updated_at || '';
    return vm;
  }
}

/**
 * 章节视图模型
 */
export class EpViewModel {
  id: string = '';
  title: string = '';
  order: number = 1;

  static fromDoc(doc: BikaEpDoc): EpViewModel {
    let vm = new EpViewModel();
    vm.id = doc._id;
    vm.title = doc.title || `第${doc.order}话`;
    vm.order = toNum(doc.order);
    return vm;
  }
}

/**
 * 阅读页图片项
 */
export interface PageItem {
  id: string;
  imageUrl: string;
  fileServer: string;
  mediaPath: string;
}

// ═══════════════════════ 工具函数 ═══════════════════════

/**
 * 服务端数字字段可能为字符串，统一强转
 */
export function toNum(v: number | string | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  let n = Number(v);
  return isNaN(n) ? 0 : n;
}

/**
 * 根据 media 对象构造图片 URL：{fileServer}/static/{path}
 *
 * 服务端返回的 fileServer 优先（go2778 线路下服务端会返回可用的反代地址）；
 * 仅当 preferMirror=true 时强制使用镜像池首选（img.go2778.com 官方图片反代）。
 * @param preferMirror true 时忽略 fileServer 直接使用镜像池首选
 */
export function buildImageUrl(media: BikaMedia, preferMirror: boolean = false): string {
  if (!media || !media.path) {
    return '';
  }
  let server: string;
  if (preferMirror && IMAGE_HOST_POOL.length > 0) {
    server = IMAGE_HOST_POOL[0];
  } else {
    server = (media.fileServer || IMAGE_HOST_POOL[0]).trim();
    if (server.startsWith('http://')) {
      server = 'https://' + server.substring('http://'.length);
    } else if (!server.startsWith('https://')) {
      server = 'https://' + server;
    }
    if (server.endsWith('/')) {
      server = server.substring(0, server.length - 1);
    }
    // go2778 线路下图片域名 picacomic → go2778（官方国内镜像，
    // s3.go2778.com / storage-b.go2778.com 等，绕开旧域名 DNS 污染）
    server = server.replace('picacomic', 'go2778');
  }
  return server + '/static/' + media.path;
}
