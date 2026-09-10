import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { HostConfig, HostJson } from '../models/HostConfig';
import { HostStore } from './HostStore';
import { ThemeStore, CloudSettingsJson } from './ThemeStore';
import { AuthStore, cloudRequest } from './AuthService';
import { AppSettings } from './AppSettings';

const META_STORE = 'hm_ssh_sync_meta';
const KEY_HOSTS_TS = 'hosts_server_updated_at';
const KEY_SETTINGS_TS = 'settings_server_updated_at';
const KEY_LAST_SYNC = 'last_sync_at';

export interface SyncBlobResult {
  data: Object;
  updatedAt: number;
}

/**
 * 云同步接缝。
 *
 * ## 合并策略（文档）
 * **Last-write-wins（以服务端 `updated_at` 为权威时钟）**：
 * 1. 登录后先 GET hosts / settings。
 * 2. 若服务端 `updated_at` > 本地记录的上次同步时间戳 → 拉取覆盖/合并本地。
 * 3. 主机列表按 `id` 合并：同一 id 取 `updatedAt` 较大者；仅一侧存在的条目保留。
 * 4. 合并后再 PUT 回服务端（使云端与本地一致）。
 * 5. 设置 JSON 整包：服务端较新则整包应用；否则上传本地。
 *
 * ## 机密字段
 * 默认 **不** 将明文 `password` / `privateKey` 上传云端。
 * 开启「同步加密密钥到云端」时上传 `passwordEnc` / `privateKeyEnc`（口令派生）；服务端不剥离这些字段。
 * 合并时若云端明文为空则保留本地机密。
 *
 * HostStore 仍是本地真相源；云同步为 additive，不改变未登录行为。
 */
export interface ICloudSyncService {
  pullAndMergeHosts(): Promise<string>;
  pushHosts(): Promise<string>;
  pullAndMergeSettings(): Promise<string>;
  pushSettings(): Promise<string>;
  syncAll(): Promise<string>;
  getLastSyncAt(): Promise<number>;
}

export class HttpCloudSyncService implements ICloudSyncService {
  private meta: preferences.Preferences | null = null;

  async init(context: common.Context): Promise<void> {
    this.meta = await preferences.getPreferences(context, META_STORE);
  }

  async syncAll(): Promise<string> {
    const a = await this.pullAndMergeHosts();
    const b = await this.pullAndMergeSettings();
    await this.touchLastSync();
    const merged = a.indexOf('已从云端合并') >= 0 || b.indexOf('已从云端合并') >= 0 ||
      a.indexOf('已按服务端时间合并') >= 0 || b.indexOf('已应用云端') >= 0;
    if (merged) {
      return `同步完成（已合并云端变更）：${a}；${b}`;
    }
    return `同步完成：${a}；${b}`;
  }

  async getLastSyncAt(): Promise<number> {
    return this.getMeta(KEY_LAST_SYNC);
  }

  private async touchLastSync(): Promise<void> {
    await this.setMeta(KEY_LAST_SYNC, Date.now());
  }

  async pullAndMergeHosts(): Promise<string> {
    const token = AuthStore.getInstance().getAccessToken();
    if (!token) {
      throw new Error('未登录');
    }
    const raw = await cloudRequest('GET', '/api/v1/sync/hosts', null, token);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const serverTs = Number(parsed['updated_at'] ?? 0);
    const data = parsed['data'];
    const localTs = await this.getMeta(KEY_HOSTS_TS);

    const store = HostStore.getInstance();
    const localList = store.getAll();

    if (serverTs === 0 || !Array.isArray(data)) {
      await this.pushHosts();
      return '主机：云端为空，已上传本地（不含明文密码/私钥）';
    }

    const remoteJson = data as HostJson[];
    const remoteHosts = remoteJson.map((j: HostJson) => HostConfig.fromJson(j));

    if (serverTs > localTs) {
      // 本地在上次同步确认后仍有改动 → 轻量冲突（非完整三路编辑器）
      const localDirty = localList.some((h: HostConfig) => h.updatedAt > localTs);
      const merged = mergeHostsByUpdatedAt(localList, remoteHosts);
      await store.replaceAll(merged);
      await this.setMeta(KEY_HOSTS_TS, serverTs);
      await this.pushHostsInternal(token);
      if (localDirty) {
        SyncStatusHub.stashHostsConflict(localList, remoteHosts);
        SyncStatusHub.setConflict(
          'hosts',
          `主机冲突：云端与本地均有较新变更，已按条目 updatedAt 合并（${merged.length} 条）。可在帐号页选择「保留本地」或「使用云端」。`
        );
        return `主机：同步冲突已自动合并（${merged.length} 条；同 id 取较新）`;
      }
      SyncStatusHub.clearConflictIf('hosts');
      return `主机：已按服务端时间合并（${merged.length} 条）`;
    }

    await this.pushHostsInternal(token);
    return '主机：已上传本地到云端（不含明文密码/私钥）';
  }

  async pushHosts(): Promise<string> {
    const token = AuthStore.getInstance().getAccessToken();
    if (!token) {
      throw new Error('未登录');
    }
    await this.pushHostsInternal(token);
    return '主机：已上传（不含明文密码/私钥）';
  }

  private async pushHostsInternal(token: string): Promise<void> {
    const vault = AppSettings.getInstance().isCloudVaultEnabled();
    const list: HostJson[] = HostStore.getInstance().getAll().map((h: HostConfig) => h.toCloudJson(vault));
    const raw = await cloudRequest('PUT', '/api/v1/sync/hosts', {
      data: list,
      client_updated_at: Date.now()
    }, token);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    await this.setMeta(KEY_HOSTS_TS, Number(parsed['updated_at'] ?? Date.now()));
  }

  async pullAndMergeSettings(): Promise<string> {
    const token = AuthStore.getInstance().getAccessToken();
    if (!token) {
      throw new Error('未登录');
    }
    const raw = await cloudRequest('GET', '/api/v1/sync/settings', null, token);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const serverTs = Number(parsed['updated_at'] ?? 0);
    const data = parsed['data'] as CloudSettingsJson;
    const localTs = await this.getMeta(KEY_SETTINGS_TS);
    const theme = ThemeStore.getInstance();

    if (serverTs === 0 || !data || (!data.theme_mode && !data.accent_id && !data.terminal_scheme_id)) {
      await this.pushSettingsInternal(token);
      return '设置：云端为空，已上传本地';
    }

    if (serverTs > localTs) {
      // 设置整包：服务端较新时覆盖；若本地曾推送过则提示冲突已取云端
      const localTouched = localTs > 0;
      const localSnap = theme.exportCloudSettings();
      if (localTouched) {
        SyncStatusHub.stashSettingsConflict(localSnap, data);
      }
      await theme.applyCloudSettings(data);
      await this.setMeta(KEY_SETTINGS_TS, serverTs);
      if (localTouched) {
        SyncStatusHub.setConflict(
          'settings',
          '设置冲突：云端较新，已应用云端整包。可在帐号页选择「保留本地」或确认「使用云端」。'
        );
        return '设置：同步冲突，已应用云端（可帐号页改回本地）';
      }
      SyncStatusHub.clearConflictIf('settings');
      return '设置：已从云端合并';
    }
    await this.pushSettingsInternal(token);
    return '设置：已上传本地到云端';
  }

  async pushSettings(): Promise<string> {
    const token = AuthStore.getInstance().getAccessToken();
    if (!token) {
      throw new Error('未登录');
    }
    await this.pushSettingsInternal(token);
    return '设置：已上传';
  }

  private async pushSettingsInternal(token: string): Promise<void> {
    const payload = ThemeStore.getInstance().exportCloudSettings();
    const raw = await cloudRequest('PUT', '/api/v1/sync/settings', {
      data: payload,
      client_updated_at: Date.now()
    }, token);
    const parsed = JSON.parse(raw) as Record<string, Object>;
    await this.setMeta(KEY_SETTINGS_TS, Number(parsed['updated_at'] ?? Date.now()));
  }

  private async getMeta(key: string): Promise<number> {
    if (!this.meta) {
      return 0;
    }
    return Number(await this.meta.get(key, 0));
  }

  private async setMeta(key: string, value: number): Promise<void> {
    if (!this.meta) {
      return;
    }
    await this.meta.put(key, value);
    await this.meta.flush();
  }
}

/** Mock：仅在本地 preferences 间模拟「云端」blob，便于离线 UI 联调 */
export class MockCloudSyncService implements ICloudSyncService {
  private static hostsBlob: string = '[]';
  private static hostsTs: number = 0;
  private static settingsBlob: string = '{}';
  private static settingsTs: number = 0;
  private meta: preferences.Preferences | null = null;

  async init(context: common.Context): Promise<void> {
    this.meta = await preferences.getPreferences(context, META_STORE);
  }

  private lastSyncAt: number = 0;

  async syncAll(): Promise<string> {
    const a = await this.pullAndMergeHosts();
    const b = await this.pullAndMergeSettings();
    this.lastSyncAt = Date.now();
    if (this.meta) {
      await this.meta.put(KEY_LAST_SYNC, this.lastSyncAt);
      await this.meta.flush();
    }
    const merged = a.indexOf('Mock 合并') >= 0 || b.indexOf('已应用 Mock') >= 0;
    if (merged) {
      return `已从云端合并；${a}；${b}（Mock）`;
    }
    return `${a}；${b}（Mock）`;
  }

  async getLastSyncAt(): Promise<number> {
    if (this.lastSyncAt > 0) {
      return this.lastSyncAt;
    }
    if (!this.meta) {
      return 0;
    }
    return Number(await this.meta.get(KEY_LAST_SYNC, 0));
  }

  async pullAndMergeHosts(): Promise<string> {
    const store = HostStore.getInstance();
    if (MockCloudSyncService.hostsTs === 0) {
      return await this.pushHosts();
    }
    const remote = JSON.parse(MockCloudSyncService.hostsBlob) as HostJson[];
    const merged = mergeHostsByUpdatedAt(
      store.getAll(),
      remote.map((j: HostJson) => HostConfig.fromJson(j))
    );
    await store.replaceAll(merged);
    return `主机：Mock 合并 ${merged.length} 条`;
  }

  async pushHosts(): Promise<string> {
    const vault = AppSettings.getInstance().isCloudVaultEnabled();
    const list = HostStore.getInstance().getAll().map((h: HostConfig) => h.toCloudJson(vault));
    MockCloudSyncService.hostsBlob = JSON.stringify(list);
    MockCloudSyncService.hostsTs = Date.now();
    return '主机：已写入 Mock 云端（不含明文密码/私钥）';
  }

  async pullAndMergeSettings(): Promise<string> {
    if (MockCloudSyncService.settingsTs === 0) {
      return await this.pushSettings();
    }
    const data = JSON.parse(MockCloudSyncService.settingsBlob) as CloudSettingsJson;
    await ThemeStore.getInstance().applyCloudSettings(data);
    return '设置：已应用 Mock 云端';
  }

  async pushSettings(): Promise<string> {
    MockCloudSyncService.settingsBlob =
      JSON.stringify(ThemeStore.getInstance().exportCloudSettings());
    MockCloudSyncService.settingsTs = Date.now();
    return '设置：已写入 Mock 云端';
  }
}

export class CloudSyncServiceFactory {
  private static httpInst: HttpCloudSyncService | null = null;
  private static mockInst: MockCloudSyncService | null = null;
  private static context: common.Context | null = null;

  static async init(context: common.Context): Promise<void> {
    CloudSyncServiceFactory.context = context;
    CloudSyncServiceFactory.mockInst = new MockCloudSyncService();
    await CloudSyncServiceFactory.mockInst.init(context);
    CloudSyncServiceFactory.httpInst = new HttpCloudSyncService();
    await CloudSyncServiceFactory.httpInst.init(context);
  }

  static create(): ICloudSyncService {
    const useMock = AuthStore.getInstance().isUseMock();
    if (useMock) {
      if (!CloudSyncServiceFactory.mockInst) {
        CloudSyncServiceFactory.mockInst = new MockCloudSyncService();
      }
      return CloudSyncServiceFactory.mockInst;
    }
    if (!CloudSyncServiceFactory.httpInst) {
      CloudSyncServiceFactory.httpInst = new HttpCloudSyncService();
    }
    return CloudSyncServiceFactory.httpInst;
  }
}

/** 同步协调：单飞 syncAll + 本地变更推送防抖，避免风暴 */
class SyncCoordinator {
  private syncInFlight: Promise<string> | null = null;
  private pushTimerHosts: number = -1;
  private pushTimerSettings: number = -1;
  private pendingHosts: boolean = false;
  private pendingSettings: boolean = false;
  private static readonly PUSH_DEBOUNCE_MS: number = 800;

  async syncAllCoalesced(): Promise<string> {
    if (this.syncInFlight) {
      return this.syncInFlight;
    }
    const svc = CloudSyncServiceFactory.create();
    this.syncInFlight = (async () => {
      try {
        const msg = await svc.syncAll();
        SyncStatusHub.markSyncOk();
        return msg;
      } catch (e) {
        const m = e instanceof Error ? e.message : `${e}`;
        SyncStatusHub.markSyncError(m);
        throw e;
      } finally {
        this.syncInFlight = null;
      }
    })();
    return this.syncInFlight;
  }

  schedulePush(kind: 'hosts' | 'settings'): void {
    const auth = AuthStore.getInstance();
    if (!auth.isLoggedIn()) {
      return;
    }
    if (kind === 'hosts') {
      this.pendingHosts = true;
      if (this.pushTimerHosts >= 0) {
        clearTimeout(this.pushTimerHosts);
      }
      this.pushTimerHosts = setTimeout(() => {
        this.pushTimerHosts = -1;
        void this.flushPush('hosts');
      }, SyncCoordinator.PUSH_DEBOUNCE_MS) as number;
    } else {
      this.pendingSettings = true;
      if (this.pushTimerSettings >= 0) {
        clearTimeout(this.pushTimerSettings);
      }
      this.pushTimerSettings = setTimeout(() => {
        this.pushTimerSettings = -1;
        void this.flushPush('settings');
      }, SyncCoordinator.PUSH_DEBOUNCE_MS) as number;
    }
  }

  private async flushPush(kind: 'hosts' | 'settings'): Promise<void> {
    if (kind === 'hosts') {
      if (!this.pendingHosts) {
        return;
      }
      this.pendingHosts = false;
    } else {
      if (!this.pendingSettings) {
        return;
      }
      this.pendingSettings = false;
    }
    // 若全量同步进行中，结束后再推一次（合并到下一次 debounce 即可）
    if (this.syncInFlight) {
      this.schedulePush(kind);
      return;
    }
    try {
      const svc = CloudSyncServiceFactory.create();
      if (kind === 'hosts') {
        await svc.pushHosts();
      } else {
        await svc.pushSettings();
      }
      SyncStatusHub.markSyncOk();
    } catch (e) {
      // 后台同步失败不影响本地保存；记录错误供状态行展示
      const m = e instanceof Error ? e.message : `${e}`;
      SyncStatusHub.markSyncError(m);
    }
  }
}

const SYNC_COORD = new SyncCoordinator();

/** 单飞全量同步（登录后 / 下拉刷新 / 帐号页共用） */
export async function syncAllCoalesced(): Promise<string> {
  return SYNC_COORD.syncAllCoalesced();
}

/**
 * 登录态下本地变更后的后台推送（防抖；失败静默，不打断 UI）。
 */
export async function maybePushAfterLocalChange(kind: 'hosts' | 'settings'): Promise<void> {
  SYNC_COORD.schedulePush(kind);
}


/** 同步状态中枢：最近错误 / 离线感 / 轻量冲突文案（供 Index / Account 展示） */
export class SyncStatusHub {
  private static lastError: string = '';
  private static offline: boolean = false;
  private static conflictKind: string = '';
  private static conflictMessage: string = '';
  /** 冲突时暂存的本地 / 云端主机快照（JSON），供保留本地 / 使用云端 */
  private static stashLocalHostsJson: string = '';
  private static stashRemoteHostsJson: string = '';
  private static stashLocalSettings: CloudSettingsJson | null = null;
  private static stashRemoteSettings: CloudSettingsJson | null = null;

  static markSyncOk(): void {
    SyncStatusHub.lastError = '';
    SyncStatusHub.offline = false;
  }

  static markSyncError(msg: string): void {
    const m = (msg ?? '').trim();
    SyncStatusHub.lastError = m.length > 0 ? m : '同步失败';
    const low = SyncStatusHub.lastError.toLowerCase();
    if (low.indexOf('network') >= 0 ||
      low.indexOf('failed to connect') >= 0 ||
      low.indexOf('timeout') >= 0 ||
      low.indexOf('timed out') >= 0 ||
      low.indexOf('econn') >= 0 ||
      low.indexOf('offline') >= 0 ||
      low.indexOf('无法连接') >= 0 ||
      low.indexOf('网络') >= 0) {
      SyncStatusHub.offline = true;
    }
  }

  static markOffline(hint?: string): void {
    SyncStatusHub.offline = true;
    if (hint && hint.length > 0) {
      SyncStatusHub.lastError = hint;
    }
  }

  static markOnline(): void {
    SyncStatusHub.offline = false;
  }

  static isOffline(): boolean {
    return SyncStatusHub.offline;
  }

  static getLastError(): string {
    return SyncStatusHub.lastError;
  }

  static setConflict(kind: string, message: string): void {
    SyncStatusHub.conflictKind = kind;
    SyncStatusHub.conflictMessage = message;
  }

  static stashHostsConflict(local: HostConfig[], remote: HostConfig[]): void {
    const vault = false;
    SyncStatusHub.stashLocalHostsJson = JSON.stringify(local.map((h: HostConfig) => h.toJson()));
    SyncStatusHub.stashRemoteHostsJson = JSON.stringify(remote.map((h: HostConfig) => h.toJson()));
  }

  static stashSettingsConflict(local: CloudSettingsJson, remote: CloudSettingsJson): void {
    SyncStatusHub.stashLocalSettings = local;
    SyncStatusHub.stashRemoteSettings = remote;
  }

  static takeStashLocalHosts(): HostConfig[] | null {
    if (!SyncStatusHub.stashLocalHostsJson) {
      return null;
    }
    try {
      const arr = JSON.parse(SyncStatusHub.stashLocalHostsJson) as HostJson[];
      return arr.map((j: HostJson) => HostConfig.fromJson(j));
    } catch (_e) {
      return null;
    }
  }

  static takeStashRemoteHosts(): HostConfig[] | null {
    if (!SyncStatusHub.stashRemoteHostsJson) {
      return null;
    }
    try {
      const arr = JSON.parse(SyncStatusHub.stashRemoteHostsJson) as HostJson[];
      return arr.map((j: HostJson) => HostConfig.fromJson(j));
    } catch (_e) {
      return null;
    }
  }

  static takeStashLocalSettings(): CloudSettingsJson | null {
    return SyncStatusHub.stashLocalSettings;
  }

  static takeStashRemoteSettings(): CloudSettingsJson | null {
    return SyncStatusHub.stashRemoteSettings;
  }

  static clearConflictIf(kind: string): void {
    if (SyncStatusHub.conflictKind === kind) {
      SyncStatusHub.clearConflict();
    }
  }

  static clearConflict(): void {
    SyncStatusHub.conflictKind = '';
    SyncStatusHub.conflictMessage = '';
    SyncStatusHub.stashLocalHostsJson = '';
    SyncStatusHub.stashRemoteHostsJson = '';
    SyncStatusHub.stashLocalSettings = null;
    SyncStatusHub.stashRemoteSettings = null;
  }

  static getConflictKind(): string {
    return SyncStatusHub.conflictKind;
  }

  static getConflictMessage(): string {
    return SyncStatusHub.conflictMessage;
  }

  static statusLine(lastSyncLabel: string): string {
    if (SyncStatusHub.offline) {
      return SyncStatusHub.lastError.length > 0 ?
        `离线 · ${SyncStatusHub.lastError}` : '离线';
    }
    if (SyncStatusHub.lastError.length > 0) {
      return `同步失败：${SyncStatusHub.lastError}`;
    }
    if (SyncStatusHub.conflictMessage.length > 0) {
      return SyncStatusHub.conflictMessage;
    }
    if (lastSyncLabel.length > 0) {
      return `上次同步：${lastSyncLabel}`;
    }
    return '';
  }
}

/** 冲突解决：强制保留本地快照并上传 */
export async function resolveConflictKeepLocal(): Promise<string> {
  const kind = SyncStatusHub.getConflictKind();
  const store = HostStore.getInstance();
  if (kind === 'settings') {
    const local = SyncStatusHub.takeStashLocalSettings();
    if (local) {
      await ThemeStore.getInstance().applyCloudSettings(local);
    }
    await CloudSyncServiceFactory.create().pushSettings();
    SyncStatusHub.clearConflict();
    SyncStatusHub.markSyncOk();
    return '已保留本地设置并上传云端';
  }
  const localHosts = SyncStatusHub.takeStashLocalHosts();
  if (localHosts) {
    await store.replaceAll(localHosts);
  }
  await CloudSyncServiceFactory.create().pushHosts();
  SyncStatusHub.clearConflict();
  SyncStatusHub.markSyncOk();
  return '已保留本地主机并上传云端';
}

/** 冲突解决：强制使用云端快照 */
export async function resolveConflictUseCloud(): Promise<string> {
  const kind = SyncStatusHub.getConflictKind();
  const store = HostStore.getInstance();
  if (kind === 'settings') {
    const remote = SyncStatusHub.takeStashRemoteSettings();
    if (remote) {
      await ThemeStore.getInstance().applyCloudSettings(remote);
    }
    await CloudSyncServiceFactory.create().pushSettings();
    SyncStatusHub.clearConflict();
    SyncStatusHub.markSyncOk();
    return '已使用云端设置';
  }
  const remoteHosts = SyncStatusHub.takeStashRemoteHosts();
  if (remoteHosts) {
    // 吸收本地机密后整表采用云端
    const withSecrets = remoteHosts.map((h: HostConfig) => {
      const copy = h.clone();
      const prev = store.getAll().find((x: HostConfig) => x.id === h.id);
      copy.absorbLocalSecrets(prev);
      return copy;
    });
    await store.replaceAll(withSecrets);
  }
  await CloudSyncServiceFactory.create().pushHosts();
  SyncStatusHub.clearConflict();
  SyncStatusHub.markSyncOk();
  return '已使用云端主机列表';
}

/** 按 host.id 合并，updatedAt 较大者胜出；云端空机密时保留本地 password/privateKey */
export function mergeHostsByUpdatedAt(local: HostConfig[], remote: HostConfig[]): HostConfig[] {
  const localById = new Map<string, HostConfig>();
  local.forEach((h: HostConfig) => localById.set(h.id, h));

  const map = new Map<string, HostConfig>();
  const ingest = (h: HostConfig) => {
    const prev = map.get(h.id);
    if (!prev || h.updatedAt >= prev.updatedAt) {
      const copy = h.clone();
      copy.absorbLocalSecrets(localById.get(h.id));
      // 若胜出者来自远端且机密空，也尝试从 prev（可能是本地）吸收
      copy.absorbLocalSecrets(prev);
      map.set(h.id, copy);
    }
  };
  local.forEach(ingest);
  remote.forEach(ingest);
  return Array.from(map.values()).sort((a: HostConfig, b: HostConfig) => b.updatedAt - a.updatedAt);
}
