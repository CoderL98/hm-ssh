/**
 * HUKS 本地机密加密 + 可选「云端密钥保险柜」（口令派生可导出密钥）。
 *
 * 导入路径对齐 HarmonyOS NEXT API 12+：
 * - `@kit.UniversalKeystoreKit` → huks（generateKeyItem / initSession / finishSession）
 * - `@kit.CryptoArchitectureKit` → cryptoFramework（PBKDF2 / AES，用于可跨设备同步的保险柜）
 *
 * 若运行时 kit 符号有差异，调用方应捕获错误并提示用户（见 Account / Settings）。
 */
import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AppSettings } from './AppSettings';

const LOCAL_KEY_ALIAS = 'hmssh_local_aes256';
const AAD_UTF8 = 'hmssh-v1';

export interface EncBlob {
  /** base64 ciphertext */
  cipherB64: string;
  /** base64 IV / nonce */
  ivB64: string;
}

export class HuksCrypto {
  private static instance: HuksCrypto | undefined = undefined;
  private ready: boolean = false;
  private lastError: string = '';

  static getInstance(): HuksCrypto {
    if (!HuksCrypto.instance) {
      HuksCrypto.instance = new HuksCrypto();
    }
    return HuksCrypto.instance;
  }

  getLastError(): string {
    return this.lastError;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      await this.ensureLocalAesKey();
      this.ready = true;
      this.lastError = '';
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : `${e}`;
      this.ready = false;
      throw e;
    }
  }

  isReady(): boolean {
    return this.ready;
  }

  /** 加密 UTF-8 明文 → EncBlob（HUKS 非导出 AES） */
  async encryptUtf8(plain: string): Promise<EncBlob> {
    await this.ensureLocalAesKey();
    const plainBytes = stringToUint8Array(plain);
    const iv = randomBytes(16);
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
    ];
    const options: huks.HuksOptions = { properties: properties, inData: plainBytes };
    const initResult = await huks.initSession(LOCAL_KEY_ALIAS, options);
    const finish = await huks.finishSession(initResult.handle, options);
    const out = finish.outData;
    if (!out) {
      throw new Error('HUKS encrypt 无输出');
    }
    return { cipherB64: uint8ToBase64(out), ivB64: uint8ToBase64(iv) };
  }

  async decryptUtf8(blob: EncBlob): Promise<string> {
    await this.ensureLocalAesKey();
    const cipher = base64ToUint8Array(blob.cipherB64);
    const iv = base64ToUint8Array(blob.ivB64);
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
    ];
    const options: huks.HuksOptions = { properties: properties, inData: cipher };
    const initResult = await huks.initSession(LOCAL_KEY_ALIAS, options);
    const finish = await huks.finishSession(initResult.handle, options);
    const out = finish.outData;
    if (!out) {
      throw new Error('HUKS decrypt 无输出');
    }
    return uint8ArrayToString(out);
  }

  /**
   * 序列化 EncBlob 为单字符串（存 preferences / JSON 字段）。
   * 格式：v1:<ivB64>:<cipherB64>
   */
  static pack(blob: EncBlob): string {
    return `v1:${blob.ivB64}:${blob.cipherB64}`;
  }

  static unpack(packed: string): EncBlob | null {
    if (!packed || !packed.startsWith('v1:')) {
      return null;
    }
    const parts = packed.split(':');
    if (parts.length < 3) {
      return null;
    }
    return { ivB64: parts[1], cipherB64: parts.slice(2).join(':') };
  }

  /** 若已是 pack 格式则解密；否则视为明文原样返回（迁移用） */
  async decryptPackedOrPlain(value: string): Promise<string> {
    if (!value || value.length === 0) {
      return '';
    }
    const blob = HuksCrypto.unpack(value);
    if (!blob) {
      return value;
    }
    return await this.decryptUtf8(blob);
  }

  async encryptToPacked(plain: string): Promise<string> {
    if (!plain || plain.length === 0) {
      return '';
    }
    const blob = await this.encryptUtf8(plain);
    return HuksCrypto.pack(blob);
  }

  // ---------- 云端保险柜：口令 PBKDF2 + AES（可跨设备） ----------

  /**
   * 用用户口令派生密钥，加密明文，返回 pack 字符串（写入 passwordEnc / privateKeyEnc）。
   */
  async encryptForCloudVault(plain: string, passphrase: string): Promise<string> {
    if (!plain) {
      return '';
    }
    if (!passphrase || passphrase.length < 8) {
      throw new Error('云端保险柜口令至少 8 位');
    }
    const saltB64 = await AppSettings.getInstance().ensureVaultSalt();
    const key = await deriveAesKey(passphrase, saltB64);
    const iv = randomBytes(16);
    const cipher = await aesCbcEncrypt(key, iv, stringToUint8Array(plain));
    return `cv1:${saltB64}:${uint8ToBase64(iv)}:${uint8ToBase64(cipher)}`;
  }

  async decryptFromCloudVault(packed: string, passphrase: string): Promise<string> {
    if (!packed) {
      return '';
    }
    if (!packed.startsWith('cv1:')) {
      throw new Error('非法保险柜密文');
    }
    const parts = packed.split(':');
    if (parts.length < 4) {
      throw new Error('保险柜密文格式错误');
    }
    const saltB64 = parts[1];
    const ivB64 = parts[2];
    const cipherB64 = parts.slice(3).join(':');
    const key = await deriveAesKey(passphrase, saltB64);
    const plain = await aesCbcDecrypt(key, base64ToUint8Array(ivB64), base64ToUint8Array(cipherB64));
    return uint8ArrayToString(plain);
  }

  private async ensureLocalAesKey(): Promise<void> {
    try {
      const exists = await huks.isKeyItemExist(LOCAL_KEY_ALIAS, { properties: [] });
      if (exists) {
        return;
      }
    } catch (_e) {
      // isKeyItemExist 在部分版本以异常表示不存在
    }
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
      // 非导出，仅本应用可用
      { tag: huks.HuksTag.HUKS_TAG_IS_KEY_EXPORT_ALLOW, value: 0 }
    ];
    // 部分文档使用 HUKS_TAG_AUTH_STORAGE_LEVEL；缺省即可绑定应用
    await huks.generateKeyItem(LOCAL_KEY_ALIAS, { properties: properties });
  }
}

async function deriveAesKey(passphrase: string, saltB64: string): Promise<Uint8Array> {
  // cryptoFramework PBKDF2：API 12+ @kit.CryptoArchitectureKit
  const salt = base64ToUint8Array(saltB64);
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password: passphrase,
    salt: salt,
    iterations: 100000,
    keySize: 32
  };
  const generator = cryptoFramework.createKdf('PBKDF2');
  const secret = await generator.generateSecret(spec);
  return secret.data;
}

async function aesCbcEncrypt(keyBytes: Uint8Array, iv: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
  const symKeyBlob: cryptoFramework.DataBlob = { data: keyBytes };
  const keyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey = await keyGenerator.convertKey(symKeyBlob);
  const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: iv };
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
  const out = await cipher.doFinal({ data: plain });
  return out.data;
}

async function aesCbcDecrypt(keyBytes: Uint8Array, iv: Uint8Array, cipherBytes: Uint8Array): Promise<Uint8Array> {
  const symKeyBlob: cryptoFramework.DataBlob = { data: keyBytes };
  const keyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  const symKey = await keyGenerator.convertKey(symKeyBlob);
  const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: iv };
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
  const out = await cipher.doFinal({ data: cipherBytes });
  return out.data;
}

function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  try {
    // @ts-ignore API 12 cryptoFramework 随机数
    const rand = cryptoFramework.createRandom();
    const blob = rand.generateRandomSync(n);
    return blob.data;
  } catch (_e) {
    for (let i = 0; i < n; i++) {
      out[i] = Math.floor(Math.random() * 256);
    }
    return out;
  }
}

function stringToUint8Array(s: string): Uint8Array {
  const encoder = new util.TextEncoder();
  return encoder.encodeInto(s);
}

function uint8ArrayToString(bytes: Uint8Array): string {
  const decoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(bytes);
}

function uint8ToBase64(bytes: Uint8Array): string {
  const helper = new util.Base64Helper();
  return helper.encodeToStringSync(bytes);
}

function base64ToUint8Array(b64: string): Uint8Array {
  const helper = new util.Base64Helper();
  return helper.decodeSync(b64);
}

// silence unused (AAD reserved for GCM migration)
void AAD_UTF8;
