import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Context, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WidgetData, WidgetRecentFormData } from '../common/WidgetData';
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
  // 「继续阅读」2*2 与「最近更新」4*4 共用同一份绑定数据（key 为超集）
  return WidgetData.buildRecentFormSync(ctx);
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
  /** formId → 上一次刷新保留的封面 fd 令牌，下一次刷新 / 卡片移除时释放 */
  private coverTokens: Map<string, string> = new Map();
  /** 正在刷新中的 formId：系统会并发触发多次 onUpdateForm，这里做去重 */
  private inFlight: Set<string> = new Set();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const name: string = formNameOf(want);
    const formId: string = formIdOf(want);
    hilog.info(DOMAIN, TAG, 'onAddForm name=%{public}s formId=%{public}s', name, formId);
    // 卡片添加时必须同步返回：先缓存 preferences 句柄，让同步读取可用
    WidgetData.init(this.context);
    WidgetExtraData.init(this.context);
    if (formId.length > 0 && name.length > 0) {
      WidgetData.rememberFormName(formId, name, this.context);
    }
    const sync = buildSyncData(name, this.context);
    if (formId.length > 0) {
      // 异步二次下发（真实数据 + 封面）
      this.scheduleRefresh(formId, name);
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
    WidgetData.forgetFormName(formId, this.context);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ═══════════════ 内部实现 ═══════════════

  /** onUpdateForm 只给 formId：优先看 wantParams，其次查本进程缓存与持久化记录 */
  private resolveName(formId: string, wantParams?: Record<string, Object>): string {
    try {
      if (wantParams !== undefined && wantParams !== null) {
        const name = wantParams[formInfo.FormParam.NAME_KEY];
        if (name !== undefined && name !== null && String(name).length > 0) {
          WidgetData.rememberFormName(formId, String(name), this.context);
          return String(name);
        }
      }
    } catch (err) {
      // 忽略：继续走持久化记录
    }
    const saved: string = WidgetData.recallFormName(formId, this.context);
    if (saved.length > 0) {
      return saved;
    }
    hilog.warn(DOMAIN, TAG, 'unknown form name for %{public}s, fallback to recent', formId);
    return NAME_RECENT;
  }

  /** 异步刷新：取数 → 下载封面 → updateForm → 释放上一次的 fd */
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
    let data: WidgetCoverFormData = new WidgetCoverFormData();
    hilog.info(DOMAIN, TAG, 'refresh start formId=%{public}s name=%{public}s', formId, name);
    if (name === NAME_RANK) {
      data = await WidgetExtraData.refreshRankForm(this.context);
    } else if (name === NAME_FAVORITES) {
      data = await WidgetExtraData.refreshFavoritesForm(this.context);
    } else if (name === NAME_RECOMMEND) {
      data = await WidgetExtraData.refreshRecommendForm(this.context);
    } else {
      data = await WidgetData.refreshRecentForm(this.context);
    }
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
      hilog.info(DOMAIN, TAG, 'updateForm ok formId=%{public}s name=%{public}s covers=%{public}d',
        formId, name, Object.keys(data.formImages).length);
      hilog.info(DOMAIN, TAG, 'push detail name=%{public}s %{public}s', name, EntryFormAbility.describe(data));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}s', JSON.stringify(err as BusinessError));
      return;
    }
    // 关键：**不要在这里关闭上一次的 fd**。
    // 卡片渲染服务是异步读取 memory:// 图片的，一旦提前 closeSync，
    // 正在解码的那一帧就会失败 —— 现象正是「只显示占位块」。
    // 官方 onAddForm 示例同样把 fd 交给系统、由 FormExtensionAbility 进程退出时统一释放
    // （本进程生命周期只有 ~10s，fd 不会长时间泄漏）。
    this.coverTokens.set(formId, data.coverToken);
  }

  /** 排障用：把下发的关键字段拼成一行短日志 */
  private static describe(data: WidgetCoverFormData): string {
    let detail: string = 'keys=' + Object.keys(data).join(',');
    if (data instanceof WidgetRecentFormData) {
      detail += ' showCover=' + data.showCover + ' continueCoverKey=' + data.continueCoverKey +
        ' continueComicId=' + data.continueComicId + ' recentJson=' + data.recentJson;
    }
    let json: string = JSON.stringify(data);
    detail += ' raw=' + json;
    return detail.length > 900 ? detail.substring(0, 900) : detail;
  }

  /** 卡片被移除时释放本进程为它保留的 fd（渲染期绝不能提前释放） */
  private releasePrevious(formId: string): void {
    const token: string | undefined = this.coverTokens.get(formId);
    if (token !== undefined) {
      WidgetCover.release(token);
      this.coverTokens.delete(formId);
    }
  }
};
