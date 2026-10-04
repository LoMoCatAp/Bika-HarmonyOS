import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Context, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WidgetData } from '../common/WidgetData';
import { WidgetExtraData } from '../common/WidgetExtraData';
import { WidgetCover, WidgetCoverFormData } from '../common/WidgetCover';

const DOMAIN = 0x0000;
const TAG = 'EntryFormAbility';

/** 卡片名，必须与 resources/base/profile/form_config.json 的 name 一一对应 */
const NAME_CONTINUE = 'BikaContinueWidget';
const NAME_RECENT = 'BikaRecentWidget';
const NAME_RANK = 'BikaRankWidget';
const NAME_FAVORITES = 'BikaFavoritesWidget';
const NAME_RECOMMEND = 'BikaRecommendWidget';
/** 未知卡片名（formId 记录丢失 / 复用）的兜底标记：下发超集键 */
const NAME_UNKNOWN = '';
/** 上一次刷新的 fd 延迟释放：卡片渲染服务异步读 memory://，太早 close 只会显示占位块 */
const FD_RELEASE_DELAY_MS = 2000;

/** 从 onAddForm 的 want 里取卡片名 */
function formNameOf(want: Want): string {
  try {
    const params = want.parameters;
    if (params === undefined || params === null) {
      return '';
    }
    const name = params[formInfo.FormParam.NAME_KEY];
    if (name === undefined || name === null) {
      return '';
    }
    return String(name);
  } catch (err) {
    return '';
  }
}

/** 从 onAddForm 的 want 里取 formId（onUpdateForm 只回传 formId，需要靠它分派） */
function formIdOf(want: Want): string {
  try {
    const params = want.parameters;
    if (params === undefined || params === null) {
      return '';
    }
    const id = params[formInfo.FormParam.IDENTITY_KEY];
    if (id === undefined || id === null) {
      return '';
    }
    return String(id);
  } catch (err) {
    return '';
  }
}

/**
 * 未知卡片名时的兜底绑定数据：一次带上五张卡各自认识的 key（超集），
 * 各卡片只取自己认识的字段，不会再出现「榜单卡只收到 recent 键、永远骨架」。
 * formImages / coverToken 由 WidgetCoverFormData 提供。
 */
class WidgetSupersetFormData extends WidgetCoverFormData {
  recentTitle: string = '最近更新';
  continueTitle: string = '';
  continueSubtitle: string = '';
  continueComicId: string = '';
  continueCoverKey: string = '';
  recentJson: string = '[]';
  showCover: string = 'true';
  emptyText: string = '打开 Bika 开始阅读';
  rankTitle: string = '排行榜';
  rankJson: string = '[]';
  favTitle: string = '我的收藏';
  favJson: string = '[]';
  recTitle: string = '为你推荐';
  recJson: string = '[]';
  extraShowCover: string = 'true';
}

/** 未知卡片名兜底：只读本地缓存，组装五张卡需要的全部 key（不发网络，保证快速返回） */
function buildSupersetSync(ctx: Context): WidgetSupersetFormData {
  const out = new WidgetSupersetFormData();
  const recent = WidgetData.buildRecentFormSync(ctx);
  out.recentTitle = recent.recentTitle;
  out.continueTitle = recent.continueTitle;
  out.continueSubtitle = recent.continueSubtitle;
  out.continueComicId = recent.continueComicId;
  out.continueCoverKey = recent.continueCoverKey;
  out.recentJson = recent.recentJson;
  out.showCover = recent.showCover;
  out.emptyText = recent.emptyText;
  out.formImages = recent.formImages;
  out.coverToken = recent.coverToken;
  const rank = WidgetExtraData.buildRankFormSync(ctx);
  out.rankTitle = rank.rankTitle;
  out.rankJson = rank.rankJson;
  out.extraShowCover = rank.extraShowCover;
  const fav = WidgetExtraData.buildFavoritesFormSync(ctx);
  out.favTitle = fav.favTitle;
  out.favJson = fav.favJson;
  const rec = WidgetExtraData.buildRecommendFormSync(ctx);
  out.recTitle = rec.recTitle;
  out.recJson = rec.recJson;
  return out;
}

/** 同步文本数据（onAddForm 必须同步返回，此时还没有封面） */
function buildSyncData(name: string, ctx: Context): WidgetCoverFormData {
  if (name === NAME_RANK) {
    return WidgetExtraData.buildRankFormSync(ctx);
  }
  if (name === NAME_FAVORITES) {
    return WidgetExtraData.buildFavoritesFormSync(ctx);
  }
  if (name === NAME_RECOMMEND) {
    return WidgetExtraData.buildRecommendFormSync(ctx);
  }
  if (name === NAME_CONTINUE || name === NAME_RECENT) {
    // 「继续阅读」2*2 与「最近更新」4*4 共用同一份绑定数据（key 为超集）
    return WidgetData.buildRecentFormSync(ctx);
  }
  // P2-4：名字未知时下发超集键，任何卡片都能拿到自己认识的数据
  return buildSupersetSync(ctx);
}

/**
 * 卡片生命周期。
 *
 * 交互方式：五张卡片都是**动态卡片**（form_config.json 里 isDynamic: true），
 * 因此卡片内的点击一律用 postCardAction(this, { action: 'router', ... })，
 * 不能用 FormLink（官方明确 FormLink 仅可用于静态卡片）。
 *
 * 数据下发：
 * - onAddForm 必须同步返回 → 只下发本地文本数据；
 * - 拿到 formId 后异步取真实数据 + 并发下载封面，再 updateForm 二次下发；
 * - onUpdateForm（系统定时刷新）直接走异步路径，一次下发含封面的完整数据。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  /** formId → 上一次刷新保留的封面 fd 令牌，下一次刷新成功后延迟释放 */
  private coverTokens: Map<string, string> = new Map();
  /** 正在刷新中的 formId：系统会并发触发多次 onUpdateForm，这里做去重 */
  private inFlight: Set<string> = new Set();
  /** 本进程内 formId → 卡片名：preferences 记录丢失时的第一优先兜底 */
  private nameCache: Map<string, string> = new Map();
  /** 刷新期间被移除的 formId：in-flight 结果回来时直接丢弃，避免给已移除卡片留 fd */
  private removedForms: Set<string> = new Set();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const name: string = formNameOf(want);
    const formId: string = formIdOf(want);
    hilog.info(DOMAIN, TAG, 'onAddForm name=%{public}s formId=%{public}s', name, formId);
    // 卡片添加时必须同步返回：先缓存 preferences 句柄，让同步读取可用
    WidgetData.init(this.context);
    WidgetExtraData.init(this.context);
    if (formId.length > 0 && name.length > 0) {
      this.nameCache.set(formId, name);
      WidgetData.rememberFormName(formId, name, this.context);
    }
    const sync = buildSyncData(name, this.context);
    if (formId.length > 0) {
      // 异步二次下发（真实数据 + 封面）
      this.scheduleRefresh(formId, name.length > 0 ? name : NAME_UNKNOWN);
    }
    return formBindingData.createFormBindingData(sync);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm: %{public}s', formId);
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const name: string = this.resolveName(formId, wantParams);
    hilog.info(DOMAIN, TAG, 'onUpdateForm formId=%{public}s name=%{public}s', formId, name);
    this.scheduleRefresh(formId, name);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility: %{public}s', JSON.stringify(newStatus));
  }

  onFormEvent(formId: string, message: string): void {
    // 预留：卡片内 message 事件（message 类型 FormLink / postCardAction 会走到这里）
    hilog.info(DOMAIN, TAG, 'onFormEvent: %{public}s %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm: %{public}s', formId);
    this.releasePrevious(formId);
    this.inFlight.delete(formId);
    this.nameCache.delete(formId);
    // P1-1：给正在进行的刷新打丢弃标记，结果回来时不再保留 fd
    this.removedForms.add(formId);
    setTimeout((): void => {
      this.removedForms.delete(formId);
    }, FD_RELEASE_DELAY_MS * 4);
    WidgetData.forgetFormName(formId, this.context);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ═══════════════ 内部实现 ═══════════════

  /** onUpdateForm 只给 formId：wantParams → 本进程缓存 → 持久化记录，都取不到才用超集兜底 */
  private resolveName(formId: string, wantParams?: Record<string, Object>): string {
    try {
      if (wantParams !== undefined && wantParams !== null) {
        const name = wantParams[formInfo.FormParam.NAME_KEY];
        if (name !== undefined && name !== null && String(name).length > 0) {
          const resolved = String(name);
          this.nameCache.set(formId, resolved);
          WidgetData.rememberFormName(formId, resolved, this.context);
          return resolved;
        }
      }
    } catch (err) {
      // 忽略：继续走本进程缓存
    }
    const cached: string | undefined = this.nameCache.get(formId);
    if (cached !== undefined && cached.length > 0) {
      return cached;
    }
    const saved: string = WidgetData.recallFormName(formId, this.context);
    if (saved.length > 0) {
      this.nameCache.set(formId, saved);
      return saved;
    }
    // P2-4：不再兜底到「最近更新」，否则榜单/收藏/推荐卡只会收到 recent 键、永远骨架
    hilog.warn(DOMAIN, TAG, 'unknown form name for %{public}s, fallback to superset keys', formId);
    return NAME_UNKNOWN;
  }

  /** 异步刷新：取数 → 下载封面 → updateForm → 延迟释放上一次的 fd */
  private scheduleRefresh(formId: string, name: string): void {
    if (this.inFlight.has(formId)) {
      hilog.info(DOMAIN, TAG, 'refresh skipped (in flight) formId=%{public}s', formId);
      return;
    }
    this.inFlight.add(formId);
    this.refreshAsync(formId, name).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'refresh failed: %{public}s', JSON.stringify(err));
    }).then(() => {
      this.inFlight.delete(formId);
    });
  }

  private async refreshAsync(formId: string, name: string): Promise<void> {
    // P2-5：刷新入口先清理沙箱临时文件（关闭封面 / 未登录时也要执行）
    WidgetCover.cleanupTemp(this.context);
    let data: WidgetCoverFormData = new WidgetCoverFormData();
    hilog.info(DOMAIN, TAG, 'refresh start formId=%{public}s name=%{public}s', formId, name);
    if (name === NAME_RANK) {
      data = await WidgetExtraData.refreshRankForm(this.context);
    } else if (name === NAME_FAVORITES) {
      data = await WidgetExtraData.refreshFavoritesForm(this.context);
    } else if (name === NAME_RECOMMEND) {
      data = await WidgetExtraData.refreshRecommendForm(this.context);
    } else if (name === NAME_CONTINUE || name === NAME_RECENT) {
      data = await WidgetData.refreshRecentForm(this.context);
    } else {
      // 未知卡片名：只下发本地缓存的超集键，不发网络，保证任何卡片都能拿到数据
      data = buildSupersetSync(this.context);
    }
    // P1-1：卡片在刷新过程中被移除 —— 丢弃本次结果并立刻释放 fd
    if (this.removedForms.has(formId)) {
      WidgetCover.releaseFormData(data);
      hilog.info(DOMAIN, TAG, 'refresh discarded (form removed) formId=%{public}s', formId);
      return;
    }
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
      hilog.info(DOMAIN, TAG, 'updateForm ok formId=%{public}s name=%{public}s covers=%{public}d',
        formId, name, Object.keys(data.formImages).length);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}s', JSON.stringify(err as BusinessError));
      // 下发失败：本次 fd 不会被卡片读到，立即释放
      WidgetCover.releaseFormData(data);
      return;
    }
    const previous: string | undefined = this.coverTokens.get(formId);
    this.coverTokens.set(formId, data.coverToken);
    // P1-1：**不要立刻关闭上一次的 fd**。卡片渲染服务是异步读取 memory:// 图片的，
    // 一旦提前 closeSync，正在解码的那一帧就会失败（现象正是「只显示占位块」）。
    // 这里在下发成功后延迟释放，既保证渲染读完，又不会像以前那样永远不释放。
    if (previous !== undefined && previous.length > 0 && previous !== data.coverToken) {
      setTimeout((): void => {
        WidgetCover.release(previous);
      }, FD_RELEASE_DELAY_MS);
    }
  }

  /** 卡片被移除时释放本进程为它保留的 fd（渲染期绝不提前释放） */
  private releasePrevious(formId: string): void {
    const token: string | undefined = this.coverTokens.get(formId);
    if (token !== undefined) {
      WidgetCover.release(token);
      this.coverTokens.delete(formId);
    }
  }
};
