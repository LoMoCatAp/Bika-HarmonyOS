import { common, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { ApiService } from '../network/ApiService';
import { CacheManager } from './CacheManager';

interface FollowComic {
  comicId: string;
  title: string;
  epsCount: number;
}

interface FollowUpdate extends FollowComic {
  fromCount: number;
}

interface FollowState {
  initialized: boolean;
  checkedAt: number;
  snapshots: FollowComic[];
  pending: FollowUpdate[];
}

const FOLLOW_GROUP: string = 'bika_follow_updates';
const FOLLOW_NOTIFICATION_ID: number = 2100000001;
const FOLLOW_CHECK_INTERVAL: number = 15 * 60 * 1000;

/** 前台检查收藏章节变化，使用 Notification Kit 合并提醒；不启动后台常驻或云端推送。 */
export class FollowUpdateManager {
  private static instance: FollowUpdateManager | null = null;
  private context: common.UIAbilityContext | null = null;
  private generation: number = 0;
  private checking: boolean = false;
  private checkQueued: boolean = false;
  private forceCheckQueued: boolean = false;

  static getInstance(): FollowUpdateManager {
    if (FollowUpdateManager.instance === null) {
      FollowUpdateManager.instance = new FollowUpdateManager();
    }
    return FollowUpdateManager.instance;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /** 仅用户主动开启时申请系统通知权限，不在启动或回前台时弹授权。 */
  async setEnabled(enabled: boolean): Promise<boolean> {
    const generation = ++this.generation;
    const cache = await CacheManager.getInstance();
    if (!enabled) {
      cache.saveSetting('follow_updates', 'false');
      this.checkQueued = false;
      this.forceCheckQueued = false;
      await this.cancelNotifications();
      return false;
    }
    if (this.context === null || !ApiService.getInstance().isLoggedIn()) {
      return false;
    }
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        await notificationManager.requestEnableNotification(this.context);
      }
      if (generation !== this.generation || !await notificationManager.isNotificationEnabled()) {
        return false;
      }
      cache.saveSetting('follow_updates', 'true');
      this.checkForUpdates(true);
      return true;
    } catch (_err) {
      return false;
    }
  }

  /** 登出中止旧请求并清除本功能通知；持久化快照由账号清理统一删除。 */
  reset(): void {
    this.generation++;
    this.checkQueued = false;
    this.forceCheckQueued = false;
    this.cancelNotifications();
  }

  release(): void {
    this.generation++;
    this.checkQueued = false;
    this.forceCheckQueued = false;
    this.context = null;
  }

  private async cancelNotifications(): Promise<void> {
    try {
      await notificationManager.cancelGroup(FOLLOW_GROUP);
    } catch (_err) {
      // 没有已发布的通知时无需处理。
    }
  }

  private isCurrent(cache: CacheManager, generation: number, account: string): boolean {
    return this.context !== null && generation === this.generation
      && cache.getSetting('follow_updates', 'false') === 'true'
      && ApiService.getInstance().isLoggedIn() && cache.getToken().length > 0 && cache.getEmail() === account;
  }

  private readState(cache: CacheManager): FollowState {
    const empty: FollowState = { initialized: false, checkedAt: 0, snapshots: [], pending: [] };
    try {
      const state = JSON.parse(cache.getSetting('follow_update_state', 'null')) as FollowState;
      if (state === null || state.initialized !== true || !Number.isFinite(state.checkedAt)
        || !Array.isArray(state.snapshots) || !Array.isArray(state.pending)) {
        return empty;
      }
      const validComic = (comic: FollowComic): boolean => comic !== null
        && typeof comic.comicId === 'string' && comic.comicId.length > 0
        && typeof comic.title === 'string' && Number.isInteger(comic.epsCount) && comic.epsCount >= 0;
      if (!state.snapshots.every(validComic) || !state.pending.every((update: FollowUpdate): boolean =>
        validComic(update) && Number.isInteger(update.fromCount) && update.fromCount >= 0
          && update.epsCount > update.fromCount)) {
        return empty;
      }
      return state;
    } catch (_err) {
      return empty;
    }
  }

  async checkForUpdates(force: boolean = false): Promise<void> {
    if (this.checking) {
      this.checkQueued = true;
      this.forceCheckQueued = this.forceCheckQueued || force;
      return;
    }
    if (this.context === null) {
      return;
    }
    this.checking = true;
    const generation = this.generation;
    try {
      const cache = await CacheManager.getInstance();
      const account = cache.getEmail();
      if (!this.isCurrent(cache, generation, account) || !await notificationManager.isNotificationEnabled()) {
        return;
      }
      const previous = this.readState(cache);
      const elapsed = Date.now() - previous.checkedAt;
      if (!force && previous.pending.length === 0 && elapsed >= 0 && elapsed < FOLLOW_CHECK_INTERVAL) {
        return;
      }
      const comics = new Map<string, FollowComic>();
      let pages = 1;
      // 必须完整扫描后再提交快照，失败时保留旧状态；串行分页避免突发并发请求。
      for (let page = 1; page <= pages; page++) {
        const result = await ApiService.getInstance().getFavourites('dd', page);
        if (!this.isCurrent(cache, generation, account)) {
          return;
        }
        if (!Number.isInteger(result.pages) || result.pages < 0 || result.pages > 1000) {
          throw new Error('Invalid favourites pagination');
        }
        pages = Math.max(1, result.pages);
        for (const comic of result.comics) {
          const count = Number(comic.epsCount);
          if (!comic._id || typeof comic.title !== 'string' || !Number.isInteger(count) || count < 0) {
            throw new Error('Invalid favourite chapter count');
          }
          const existing = comics.get(comic._id);
          if (existing === undefined || count >= existing.epsCount) {
            comics.set(comic._id, { comicId: comic._id, title: comic.title, epsCount: count });
          }
        }
      }
      const oldComics = new Map<string, FollowComic>();
      previous.snapshots.forEach((comic: FollowComic): void => { oldComics.set(comic.comicId, comic); });
      const pending = new Map<string, FollowUpdate>();
      previous.pending.forEach((update: FollowUpdate): void => {
        if (comics.has(update.comicId)) {
          pending.set(update.comicId, update);
        }
      });
      const snapshots: FollowComic[] = [];
      comics.forEach((comic: FollowComic): void => {
        const old = oldComics.get(comic.comicId);
        if (previous.initialized && old !== undefined && comic.epsCount > old.epsCount) {
          const waiting = pending.get(comic.comicId);
          pending.set(comic.comicId, {
            comicId: comic.comicId, title: comic.title, epsCount: comic.epsCount,
            fromCount: waiting === undefined ? old.epsCount : waiting.fromCount
          });
        }
        // 接口计数暂时减少时保留高水位，避免恢复后把旧章节再次通知。
        snapshots.push({ comicId: comic.comicId, title: comic.title,
          epsCount: old === undefined ? comic.epsCount : Math.max(old.epsCount, comic.epsCount) });
      });
      const state: FollowState = {
        initialized: true, checkedAt: Date.now(), snapshots: snapshots, pending: Array.from(pending.values())
      };
      if (!this.isCurrent(cache, generation, account)) {
        return;
      }
      // 发布失败仍保留待通知条目，下次回前台可重试。
      // 在覆盖上次通知快照前记录新增章节段，通知发送成功也不会清除章节胶囊。
      comics.forEach((comic: FollowComic): void => { cache.recordChapterCount(comic.comicId, comic.epsCount); });
      cache.saveSetting('follow_update_state', JSON.stringify(state));
      if (state.pending.length > 0) {
        await this.publishUpdates(state.pending, cache, generation, account);
        if (!this.isCurrent(cache, generation, account)) {
          await this.cancelNotifications();
          return;
        }
        state.pending = [];
        cache.saveSetting('follow_update_state', JSON.stringify(state));
      }
    } catch (_err) {
      console.warn('[FollowUpdateManager] check failed; retained previous or pending state');
    } finally {
      this.checking = false;
      if (this.checkQueued) {
        const forceQueued = this.forceCheckQueued;
        this.checkQueued = false;
        this.forceCheckQueued = false;
        this.checkForUpdates(forceQueued);
      }
    }
  }

  private async publishUpdates(updates: FollowUpdate[], cache: CacheManager,
    generation: number, account: string): Promise<void> {
    if (this.context === null) {
      return;
    }
    const single = updates.length === 1;
    const first = updates[0];
    const text = single
      ? first.title.substring(0, 60) + ' 新增 ' + (first.epsCount - first.fromCount) + ' 话，现共 ' + first.epsCount + ' 话'
      : updates.length + ' 部收藏有新章节：' + updates.slice(0, 3)
        .map((update: FollowUpdate): string => update.title.substring(0, 20)).join('、')
        + (updates.length > 3 ? '等' : '');
    const agent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: this.context.abilityInfo.bundleName,
        abilityName: this.context.abilityInfo.name,
        parameters: { action: single ? 'open_comic' : 'open_favourites',
          comicId: single ? first.comicId : '', comicTitle: single ? first.title : '' }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: FOLLOW_NOTIFICATION_ID,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    if (!this.isCurrent(cache, generation, account)) {
      return;
    }
    await notificationManager.publish({
      id: FOLLOW_NOTIFICATION_ID,
      groupName: FOLLOW_GROUP,
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: 'Bika · 收藏更新', text: text } },
      wantAgent: agent,
      tapDismissed: true
    });
  }
}
