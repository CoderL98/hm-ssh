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
      return `已从云端合并；${a}；${b}`;
    }
    return `${a}；${b}`;
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
      const localDirty = localList.length > 0;
      const merged = mergeHostsByUpdatedAt(localList, remoteHosts);
      await store.replaceAll(merged);
      await this.setMeta(KEY_HOSTS_TS, serverTs);
      await this.pushHostsInternal(token);
      if (localDirty) {
        return `主机：已从云端合并（${merged.length} 条）`;
      }
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
      await theme.applyCloudSettings(data);
      await this.setMeta(KEY_SETTINGS_TS, serverTs);
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

/**
 * 登录态下本地变更后的后台推送（失败静默，不打断 UI）。
 */
export async function maybePushAfterLocalChange(kind: 'hosts' | 'settings'): Promise<void> {
  const auth = AuthStore.getInstance();
  if (!auth.isLoggedIn()) {
    return;
  }
  try {
    const svc = CloudSyncServiceFactory.create();
    if (kind === 'hosts') {
      await svc.pushHosts();
    } else {
      await svc.pushSettings();
    }
  } catch (_e) {
    // 后台同步失败不影响本地保存
  }
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
