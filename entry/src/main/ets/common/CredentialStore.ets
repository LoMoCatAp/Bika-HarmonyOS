import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

export interface AuthCredentials {
  email: string;
  password: string;
  token: string;
  tokenInvalid: boolean;
}

interface AuthManifest {
  schema: number;
  revision: string;
  chunks: number;
}

/** 密码/Token 仅放在 SECRET 中；别名与普通标签不包含账号或凭据。 */
export class CredentialStore {
  private static readonly PREFIX: string = 'bika.auth.v1.';
  private static readonly ACTIVE: string = CredentialStore.PREFIX + 'active';
  private static readonly VERSION_KEY: string = 'auth_asset_version';
  private static readonly CLEARED_KEY: string = 'auth_asset_cleared';
  private static readonly CHUNK_BYTES: number = 1000;
  private static readonly MAX_CHUNKS: number = 256;

  private static empty(): AuthCredentials {
    return { email: '', password: '', token: '', tokenInvalid: false };
  }

  private static text(prefs: preferences.Preferences, key: string): string {
    const value = prefs.getSync(key, '');
    return typeof value === 'string' ? value : '';
  }

  private static encode(value: string): Uint8Array {
    return new util.TextEncoder().encodeInto(value);
  }

  private static decode(value: Uint8Array): string {
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(value);
  }

  private static secret(alias: string): Uint8Array | null {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, CredentialStore.encode(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows = asset.querySync(query);
      if (rows.length === 0) {
        return null;
      }
      const value = rows[0].get(asset.Tag.SECRET);
      if (!(value instanceof Uint8Array)) {
        throw new Error('安全凭据格式异常，请稍后重试');
      }
      return value;
    } catch (err) {
      if ((err as BusinessError).code === 24000002) {
        return null;
      }
      throw err as Error;
    }
  }

  private static putSecret(alias: string, secret: Uint8Array, overwrite: boolean): void {
    const values: asset.AssetMap = new Map();
    values.set(asset.Tag.ALIAS, CredentialStore.encode(alias));
    values.set(asset.Tag.SECRET, secret);
    values.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    values.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
    values.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    values.set(asset.Tag.CONFLICT_RESOLUTION,
      overwrite ? asset.ConflictResolution.OVERWRITE : asset.ConflictResolution.THROW_ERROR);
    asset.addSync(values);
    const actual = CredentialStore.secret(alias);
    if (actual === null || actual.length !== secret.length
      || !actual.every((value: number, index: number): boolean => value === secret[index])) {
      throw new Error('安全凭据写入校验失败，请稍后重试');
    }
  }

  private static parseManifest(raw: Uint8Array): AuthManifest {
    const value = JSON.parse(CredentialStore.decode(raw)) as AuthManifest;
    if (value === null || value.schema !== 1 || typeof value.revision !== 'string'
      || !/^[a-f0-9]{32}$/.test(value.revision) || !Number.isInteger(value.chunks)
      || value.chunks < 1 || value.chunks > CredentialStore.MAX_CHUNKS) {
      throw new Error('安全凭据索引异常，请稍后重试');
    }
    return value;
  }

  private static readVaultOnce(): AuthCredentials | null {
    const raw = CredentialStore.secret(CredentialStore.ACTIVE);
    if (raw === null) {
      return null;
    }
    const manifest = CredentialStore.parseManifest(raw);
    const parts: Uint8Array[] = [];
    let total = 0;
    for (let index = 0; index < manifest.chunks; index++) {
      const part = CredentialStore.secret(CredentialStore.PREFIX + manifest.revision + '.' + index);
      if (part === null || part.length === 0 || part.length > CredentialStore.CHUNK_BYTES) {
        throw new Error('安全凭据读取未完成，请稍后重试');
      }
      parts.push(part);
      total += part.length;
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const part of parts) {
      bytes.set(part, offset);
      offset += part.length;
    }
    const value = JSON.parse(CredentialStore.decode(bytes)) as AuthCredentials;
    if (value === null || typeof value.email !== 'string' || typeof value.password !== 'string'
      || typeof value.token !== 'string' || typeof value.tokenInvalid !== 'boolean') {
      throw new Error('安全凭据内容异常，请稍后重试');
    }
    return value;
  }

  /** 读到旧索引后另一进程恰好完成提交时，重新读取一次完整快照。 */
  private static readVault(): AuthCredentials | null {
    try {
      return CredentialStore.readVaultOnce();
    } catch (_err) {
      return CredentialStore.readVaultOnce();
    }
  }

  private static writeVault(value: AuthCredentials): void {
    const bytes = CredentialStore.encode(JSON.stringify(value));
    const chunks = Math.ceil(bytes.length / CredentialStore.CHUNK_BYTES);
    if (chunks < 1 || chunks > CredentialStore.MAX_CHUNKS) {
      throw new Error('登录凭据过长，原有登录数据已保留');
    }
    const revision = util.generateRandomUUID(true).replace(/-/g, '').toLowerCase();
    for (let index = 0; index < chunks; index++) {
      CredentialStore.putSecret(CredentialStore.PREFIX + revision + '.' + index,
        bytes.slice(index * CredentialStore.CHUNK_BYTES, (index + 1) * CredentialStore.CHUNK_BYTES), false);
    }
    // 所有分片核对成功后才原子替换活动索引，中断时旧快照仍完整可读。
    const manifest: AuthManifest = { schema: 1, revision: revision, chunks: chunks };
    CredentialStore.putSecret(CredentialStore.ACTIVE, CredentialStore.encode(JSON.stringify(manifest)), true);
    const actual = CredentialStore.readVault();
    if (actual === null || actual.email !== value.email || actual.password !== value.password || actual.token !== value.token
      || actual.tokenInvalid !== value.tokenInvalid) {
      throw new Error('安全凭据读回校验失败，原有数据已保留');
    }
    CredentialStore.collectOldChunks(revision);
  }

  private static collectOldChunks(revision: string): void {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
      const rows = asset.querySync(query);
      for (const row of rows) {
        const aliasBytes = row.get(asset.Tag.ALIAS);
        if (!(aliasBytes instanceof Uint8Array)) {
          continue;
        }
        const alias = CredentialStore.decode(aliasBytes);
        if (alias.startsWith(CredentialStore.PREFIX) && alias !== CredentialStore.ACTIVE
          && !alias.startsWith(CredentialStore.PREFIX + revision + '.')) {
          const remove: asset.AssetMap = new Map();
          remove.set(asset.Tag.ALIAS, aliasBytes);
          asset.removeSync(remove);
        }
      }
    } catch (_err) {
      // 清理失败不撤销已校验的提交，下次写入/迁移时重试；不输出任何凭据。
      console.warn('[CredentialStore] encrypted orphan cleanup deferred');
    }
  }

  private static legacy(prefs: preferences.Preferences): AuthCredentials {
    return { email: CredentialStore.text(prefs, 'auth_email'), password: CredentialStore.text(prefs, 'auth_password'),
      token: CredentialStore.text(prefs, 'auth_token'),
      tokenInvalid: CredentialStore.text(prefs, 'auth_token_invalid') === 'true' };
  }

  private static finishMigration(prefs: preferences.Preferences): void {
    prefs.putSync(CredentialStore.VERSION_KEY, '1');
    prefs.flushSync();
    prefs.deleteSync('auth_email');
    prefs.deleteSync('auth_password');
    prefs.deleteSync('auth_token');
    prefs.deleteSync('auth_token_invalid');
    prefs.flushSync();
  }

  /** 仅主应用启动/回前台调用；卡片只读，避免多个进程竞争执行迁移。 */
  static migrateLegacy(prefs: preferences.Preferences): boolean {
    try {
      if (CredentialStore.text(prefs, CredentialStore.CLEARED_KEY) === 'true') {
        // 清理上次退出时因服务不可用而延后的安全快照。
        const saved = CredentialStore.readVault();
        if (saved !== null && (saved.email.length > 0 || saved.password.length > 0 || saved.token.length > 0)) {
          CredentialStore.writeVault(CredentialStore.empty());
        }
        CredentialStore.finishMigration(prefs);
        return true;
      }
      const old = CredentialStore.legacy(prefs);
      const saved = CredentialStore.readVault();
      if (saved === null && CredentialStore.text(prefs, CredentialStore.VERSION_KEY) !== '1'
        && (old.email.length > 0 || old.password.length > 0 || old.token.length > 0)) {
        CredentialStore.writeVault(old);
      } else if (saved === null) {
        return true;
      }
      CredentialStore.finishMigration(prefs);
      return true;
    } catch (_err) {
      console.warn('[CredentialStore] migration deferred; original credentials retained');
      return false;
    }
  }

  static read(prefs: preferences.Preferences): AuthCredentials {
    if (CredentialStore.text(prefs, CredentialStore.CLEARED_KEY) === 'true') {
      return CredentialStore.empty();
    }
    try {
      const saved = CredentialStore.readVault();
      if (saved !== null) {
        return saved;
      }
    } catch (err) {
      const old = CredentialStore.legacy(prefs);
      if (CredentialStore.text(prefs, CredentialStore.VERSION_KEY) !== '1'
        && (old.email.length > 0 || old.password.length > 0 || old.token.length > 0)) {
        return old;
      }
      // 临时不可访问不能伪装成空凭据、触发重新登录或覆盖资产。
      throw new Error('安全凭据暂不可访问，请解锁设备后重试');
    }
    return CredentialStore.text(prefs, CredentialStore.VERSION_KEY) === '1'
      ? CredentialStore.empty() : CredentialStore.legacy(prefs);
  }

  static save(prefs: preferences.Preferences, value: AuthCredentials): void {
    CredentialStore.writeVault(value);
    prefs.putSync(CredentialStore.CLEARED_KEY, 'false');
    CredentialStore.finishMigration(prefs);
  }

  static clear(prefs: preferences.Preferences): void {
    // 先持久化退出标记，服务暂不可用时也不能在重启后恢复旧账号。
    prefs.putSync(CredentialStore.CLEARED_KEY, 'true');
    prefs.flushSync();
    CredentialStore.finishMigration(prefs);
    try {
      // 保留不含凭据的活动记录，避免存活的卡片进程回落到旧 Preferences 缓存。
      CredentialStore.writeVault(CredentialStore.empty());
    } catch (_err) {
      console.warn('[CredentialStore] encrypted logout cleanup deferred');
    }
  }

  /** 卡片严格只读安全存储；升级后首次启动主应用之前继续使用本地内容降级。 */
  static readWidgetToken(): string {
    const saved = CredentialStore.readVault();
    return saved === null || saved.tokenInvalid ? '' : saved.token;
  }
}
