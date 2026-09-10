import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { HuksCrypto } from './HuksCrypto';

const STORE_NAME = 'hm_ssh_app_settings';
const KEY_USE_NATIVE = 'use_native_protocols';
const KEY_CLOUD_VAULT = 'sync_encrypted_secrets';
const KEY_VAULT_SALT = 'cloud_vault_salt_b64';
const KEY_REMEMBER_VAULT = 'remember_vault_passphrase';
const KEY_VAULT_PASSPHRASE_ENC = 'vault_passphrase_enc';
const SETTINGS_REV = 'appSettingsRev';

/**
 * 应用级开关：原生协议、云端密钥保险柜。
 * 保险柜口令默认经 HUKS 加密后落盘（「记住保险柜口令」），以便重启后解开 passwordEnc。
 */
export class AppSettings {
  private static instance: AppSettings | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private ready: boolean = false;
  private useNativeProtocols: boolean = false;
  private syncEncryptedSecrets: boolean = false;
  private vaultSaltB64: string = '';
  private revision: number = 0;
  /** 内存中的保险柜口令；可选 HUKS 加密后写入 preferences */
  private vaultPassphrase: string = '';
  /** 记住口令（默认 ON；保险柜开启时生效） */
  private rememberVaultPassphrase: boolean = true;

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
    const rememberRaw = await this.pref.get(KEY_REMEMBER_VAULT, '1') as string;
    this.rememberVaultPassphrase = rememberRaw !== '0' && rememberRaw !== 'false';

    // 保险柜开启且「记住口令」时，从 HUKS 密文恢复内存口令
    if (this.syncEncryptedSecrets && this.rememberVaultPassphrase) {
      const packed = await this.pref.get(KEY_VAULT_PASSPHRASE_ENC, '') as string;
      if (packed && packed.length > 0) {
        try {
          const crypto = HuksCrypto.getInstance();
          await crypto.init();
          this.vaultPassphrase = await crypto.decryptPackedOrPlain(packed);
        } catch (_e) {
          this.vaultPassphrase = packed.startsWith('v1:') ? '' : packed;
        }
      }
    }

    this.ready = true;
    this.publish();
  }

  isReady(): boolean {
    return this.ready;
  }

  preferNative(): boolean {
    return this.useNativeProtocols;
  }

  isCloudVaultEnabled(): boolean {
    return this.syncEncryptedSecrets;
  }

  isRememberVaultPassphrase(): boolean {
    return this.rememberVaultPassphrase;
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
    if (!value) {
      // 关闭保险柜：清内存与落盘口令
      await this.clearVaultPassphrase(true);
    } else if (this.rememberVaultPassphrase && this.vaultPassphrase.length > 0) {
      await this.persistVaultPassphraseEnc();
    }
    this.publish();
  }

  /**
   * 更新内存口令；若开启「记住」且保险柜 ON，则 HUKS 加密后落盘。
   */
  async setVaultPassphrase(passphrase: string): Promise<void> {
    this.vaultPassphrase = passphrase;
    if (this.syncEncryptedSecrets && this.rememberVaultPassphrase && passphrase.length > 0) {
      await this.persistVaultPassphraseEnc();
    } else if (!this.rememberVaultPassphrase || passphrase.length === 0) {
      await this.clearPersistedVaultPassphraseOnly();
    }
    this.publish();
  }

  async setRememberVaultPassphrase(value: boolean): Promise<void> {
    this.rememberVaultPassphrase = value;
    if (this.pref) {
      await this.pref.put(KEY_REMEMBER_VAULT, value ? '1' : '0');
      await this.pref.flush();
    }
    if (value && this.syncEncryptedSecrets && this.vaultPassphrase.length > 0) {
      await this.persistVaultPassphraseEnc();
    } else if (!value) {
      await this.clearPersistedVaultPassphraseOnly();
    }
    this.publish();
  }

  /**
   * 退出登录或关闭保险柜时调用：清空内存口令，并删除落盘密文。
   */
  async clearVaultPassphrase(clearMemory: boolean = true): Promise<void> {
    if (clearMemory) {
      this.vaultPassphrase = '';
    }
    await this.clearPersistedVaultPassphraseOnly();
    this.publish();
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

  private async persistVaultPassphraseEnc(): Promise<void> {
    if (!this.pref || !this.vaultPassphrase) {
      return;
    }
    let packed = this.vaultPassphrase;
    try {
      const crypto = HuksCrypto.getInstance();
      await crypto.init();
      packed = await crypto.encryptToPacked(this.vaultPassphrase);
    } catch (_e) {
      // HUKS 不可用时仍写入（与 Token 同样明文回退）；README 已说明权衡
    }
    await this.pref.put(KEY_VAULT_PASSPHRASE_ENC, packed);
    await this.pref.flush();
  }

  private async clearPersistedVaultPassphraseOnly(): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_VAULT_PASSPHRASE_ENC, '');
    await this.pref.flush();
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
