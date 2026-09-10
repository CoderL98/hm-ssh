import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { HostConfig, HostJson } from '../models/HostConfig';
import { HuksCrypto } from './HuksCrypto';
import { AppSettings } from './AppSettings';

const STORE_NAME = 'hm_ssh_hosts';
const KEY_HOSTS = 'hosts_json';

/**
 * 基于 preferences 的主机配置持久化。
 * 密码/私钥：内存明文；落盘 HUKS 密文（passwordLocalEnc）。
 * 可选云端保险柜字段 passwordEnc（PBKDF）由 upsert/sync 填充。
 */
export class HostStore {
  private static instance: HostStore | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private hosts: HostConfig[] = [];
  private ready: boolean = false;
  private huksOk: boolean = false;
  private huksError: string = '';

  static getInstance(): HostStore {
    if (!HostStore.instance) {
      HostStore.instance = new HostStore();
    }
    return HostStore.instance;
  }

  getHuksError(): string {
    return this.huksError;
  }

  async init(context: common.Context): Promise<void> {
    if (this.ready) {
      return;
    }
    this.pref = await preferences.getPreferences(context, STORE_NAME);
    try {
      await HuksCrypto.getInstance().init();
      this.huksOk = true;
      this.huksError = '';
    } catch (e) {
      this.huksOk = false;
      this.huksError = e instanceof Error ? e.message : `${e}`;
    }
    const raw = await this.pref.get(KEY_HOSTS, '[]') as string;
    this.hosts = HostStore.parseList(raw);
    await this.migrateAndUnlock();
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
    await this.sealHostSecrets(host);
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

  async replaceAll(hosts: HostConfig[]): Promise<void> {
    this.hosts = hosts.slice();
    for (let i = 0; i < this.hosts.length; i++) {
      await this.unlockHost(this.hosts[i]);
      await this.sealHostSecrets(this.hosts[i]);
    }
    await this.persist();
  }

  exportJson(): HostJson[] {
    return this.hosts.map((h: HostConfig) => h.toJson());
  }

  private async migrateAndUnlock(): Promise<void> {
    let changed = false;
    for (let i = 0; i < this.hosts.length; i++) {
      const h = this.hosts[i];
      // 旧明文 → 加密
      if (h.password && h.password.length > 0 && !h.passwordLocalEnc) {
        changed = true;
      }
      if (h.privateKey && h.privateKey.length > 0 && !h.privateKeyLocalEnc) {
        changed = true;
      }
      await this.unlockHost(h);
      await this.sealHostSecrets(h);
    }
    if (changed || this.huksOk) {
      await this.persist();
    }
  }

  private async unlockHost(h: HostConfig): Promise<void> {
    if (!this.huksOk) {
      return;
    }
    const crypto = HuksCrypto.getInstance();
    try {
      if (h.passwordLocalEnc) {
        h.password = await crypto.decryptPackedOrPlain(h.passwordLocalEnc);
      }
      if (h.privateKeyLocalEnc) {
        h.privateKey = await crypto.decryptPackedOrPlain(h.privateKeyLocalEnc);
      }
      // 云端保险柜密文：若本地明文空且用户已提供口令，尝试解开
      const settings = AppSettings.getInstance();
      const pass = settings.getVaultPassphrase();
      if (pass && settings.isCloudVaultEnabled()) {
        if ((!h.password || h.password.length === 0) && h.passwordEnc) {
          h.password = await crypto.decryptFromCloudVault(h.passwordEnc, pass);
        }
        if ((!h.privateKey || h.privateKey.length === 0) && h.privateKeyEnc) {
          h.privateKey = await crypto.decryptFromCloudVault(h.privateKeyEnc, pass);
        }
      }
    } catch (e) {
      this.huksError = e instanceof Error ? e.message : `${e}`;
    }
  }

  private async sealHostSecrets(h: HostConfig): Promise<void> {
    if (!this.huksOk) {
      // HUKS 失败时仍允许明文演示（并记录错误）
      return;
    }
    const crypto = HuksCrypto.getInstance();
    try {
      if (h.password && h.password.length > 0) {
        h.passwordLocalEnc = await crypto.encryptToPacked(h.password);
      } else {
        h.passwordLocalEnc = '';
      }
      if (h.privateKey && h.privateKey.length > 0) {
        h.privateKeyLocalEnc = await crypto.encryptToPacked(h.privateKey);
      } else {
        h.privateKeyLocalEnc = '';
      }
      const settings = AppSettings.getInstance();
      if (settings.isCloudVaultEnabled()) {
        const pass = settings.getVaultPassphrase();
        if (pass && pass.length >= 8) {
          h.passwordEnc = h.password ? await crypto.encryptForCloudVault(h.password, pass) : '';
          h.privateKeyEnc = h.privateKey ? await crypto.encryptForCloudVault(h.privateKey, pass) : '';
        }
      }
    } catch (e) {
      this.huksError = e instanceof Error ? e.message : `${e}`;
    }
  }

  private async persist(): Promise<void> {
    if (!this.pref) {
      return;
    }
    const list: HostJson[] = this.hosts.map((h: HostConfig) => {
      const j = h.toJson();
      // HUKS 不可用时回退明文落盘，避免丢密
      if (!this.huksOk) {
        j.password = h.password;
        j.privateKey = h.privateKey;
      }
      return j;
    });
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
