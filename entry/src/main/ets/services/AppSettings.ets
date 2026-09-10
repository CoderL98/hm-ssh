import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'hm_ssh_app_settings';
const KEY_USE_NATIVE = 'use_native_protocols';
const KEY_CLOUD_VAULT = 'sync_encrypted_secrets';
const KEY_VAULT_SALT = 'cloud_vault_salt_b64';
const SETTINGS_REV = 'appSettingsRev';

/**
 * 应用级开关：原生协议、云端密钥保险柜。
 */
export class AppSettings {
  private static instance: AppSettings | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private ready: boolean = false;
  private useNativeProtocols: boolean = false;
  private syncEncryptedSecrets: boolean = false;
  private vaultSaltB64: string = '';
  private revision: number = 0;
  /** 内存中的保险柜口令（不上盘）；开启云端保险柜时由用户输入 */
  private vaultPassphrase: string = '';

  static getInstance(): AppSettings {
    if (!AppSettings.instance) {
      AppSettings.instance = new AppSettings();
    }
    return AppSettings.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.ready) {
      return;
    }
    this.pref = await preferences.getPreferences(context, STORE_NAME);
    const nativeRaw = await this.pref.get(KEY_USE_NATIVE, '0') as string;
    this.useNativeProtocols = nativeRaw === '1' || nativeRaw === 'true';
    const vaultRaw = await this.pref.get(KEY_CLOUD_VAULT, '0') as string;
    this.syncEncryptedSecrets = vaultRaw === '1' || vaultRaw === 'true';
    this.vaultSaltB64 = await this.pref.get(KEY_VAULT_SALT, '') as string;
    this.ready = true;
    this.publish();
  }

  preferNative(): boolean {
    return this.useNativeProtocols;
  }

  isCloudVaultEnabled(): boolean {
    return this.syncEncryptedSecrets;
  }

  getVaultPassphrase(): string {
    return this.vaultPassphrase;
  }

  getVaultSaltB64(): string {
    return this.vaultSaltB64;
  }

  async setPreferNative(value: boolean): Promise<void> {
    this.useNativeProtocols = value;
    if (this.pref) {
      await this.pref.put(KEY_USE_NATIVE, value ? '1' : '0');
      await this.pref.flush();
    }
    this.publish();
  }

  async setCloudVaultEnabled(value: boolean): Promise<void> {
    this.syncEncryptedSecrets = value;
    if (this.pref) {
      await this.pref.put(KEY_CLOUD_VAULT, value ? '1' : '0');
      await this.pref.flush();
    }
    this.publish();
  }

  setVaultPassphrase(passphrase: string): void {
    this.vaultPassphrase = passphrase;
  }

  async ensureVaultSalt(): Promise<string> {
    if (this.vaultSaltB64 && this.vaultSaltB64.length > 0) {
      return this.vaultSaltB64;
    }
    const bytes = new Uint8Array(16);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    this.vaultSaltB64 = uint8ToBase64(bytes);
    if (this.pref) {
      await this.pref.put(KEY_VAULT_SALT, this.vaultSaltB64);
      await this.pref.flush();
    }
    return this.vaultSaltB64;
  }

  private publish(): void {
    this.revision += 1;
    try {
      AppStorage.setOrCreate(SETTINGS_REV, this.revision);
    } catch (_e) {
      // ignore
    }
  }
}

function uint8ToBase64(bytes: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const triple = (a << 16) | (b << 8) | c;
    out += chars[(triple >> 18) & 63];
    out += chars[(triple >> 12) & 63];
    out += i + 1 < bytes.length ? chars[(triple >> 6) & 63] : '=';
    out += i + 2 < bytes.length ? chars[triple & 63] : '=';
  }
  return out;
}
