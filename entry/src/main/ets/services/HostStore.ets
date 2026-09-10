import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { HostConfig, HostJson } from '../models/HostConfig';

const STORE_NAME = 'hm_ssh_hosts';
const KEY_HOSTS = 'hosts_json';

/**
 * 基于 preferences 的主机配置持久化。
 * 简单可靠，适合第一里程碑；后续可迁移至 relationalStore。
 */
export class HostStore {
  private static instance: HostStore | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private hosts: HostConfig[] = [];
  private ready: boolean = false;

  static getInstance(): HostStore {
    if (!HostStore.instance) {
      HostStore.instance = new HostStore();
    }
    return HostStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.ready) {
      return;
    }
    this.pref = await preferences.getPreferences(context, STORE_NAME);
    const raw = await this.pref.get(KEY_HOSTS, '[]') as string;
    this.hosts = HostStore.parseList(raw);
    this.ready = true;
  }

  getAll(): HostConfig[] {
    return this.hosts.slice();
  }

  getById(id: string): HostConfig | undefined {
    return this.hosts.find((h: HostConfig) => h.id === id);
  }

  async upsert(host: HostConfig): Promise<HostConfig> {
    const now = Date.now();
    if (!host.id || host.id.length === 0) {
      host.id = HostStore.genId();
      host.createdAt = now;
    }
    host.updatedAt = now;
    const idx = this.hosts.findIndex((h: HostConfig) => h.id === host.id);
    if (idx >= 0) {
      this.hosts[idx] = host;
    } else {
      this.hosts.push(host);
    }
    await this.persist();
    return host;
  }

  async remove(id: string): Promise<boolean> {
    const before = this.hosts.length;
    this.hosts = this.hosts.filter((h: HostConfig) => h.id !== id);
    if (this.hosts.length === before) {
      return false;
    }
    await this.persist();
    return true;
  }


  /** 云同步：整体替换本地列表（additive 云能力，不改变单条 CRUD API） */
  async replaceAll(hosts: HostConfig[]): Promise<void> {
    this.hosts = hosts.slice();
    await this.persist();
  }

  /** 导出 JSON 数组（云同步 PUT） */
  exportJson(): HostJson[] {
    return this.hosts.map((h: HostConfig) => h.toJson());
  }

  private async persist(): Promise<void> {
    if (!this.pref) {
      return;
    }
    const list: HostJson[] = this.hosts.map((h: HostConfig) => h.toJson());
    await this.pref.put(KEY_HOSTS, JSON.stringify(list));
    await this.pref.flush();
  }

  private static parseList(raw: string): HostConfig[] {
    try {
      const arr = JSON.parse(raw) as HostJson[];
      if (!Array.isArray(arr)) {
        return [];
      }
      return arr.map((item: HostJson) => HostConfig.fromJson(item));
    } catch (_e) {
      return [];
    }
  }

  private static genId(): string {
    return `host_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }
}
