import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { CloudConfig } from '../common/Constants';
import { HuksCrypto } from './HuksCrypto';

const STORE_NAME = 'hm_ssh_auth';
const KEY_ACCESS = 'access_token';
const KEY_REFRESH = 'refresh_token';
const KEY_EXPIRES = 'expires_at';
const KEY_USER_JSON = 'user_json';
const KEY_BASE_URL = 'cloud_base_url';
const KEY_USE_MOCK = 'use_mock';
const AUTH_REV_KEY = 'authRev';

/** 提前多少秒刷新 access token */
const REFRESH_SKEW_SECS = 60;

export interface CloudUser {
  id: string;
  email: string;
  username: string;
  created_at: number;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  user: CloudUser;
}

export interface IAuthService {
  register(email: string, username: string, password: string): Promise<AuthTokens>;
  login(login: string, password: string): Promise<AuthTokens>;
  me(): Promise<CloudUser>;
  logout(): Promise<void>;
  refresh?(): Promise<AuthTokens>;
}

/**
 * 帐号与 JWT 本地缓存（preferences）。
 * access/refresh token 经 HUKS 加密后写入 preferences；内存保留明文。
 */
export class AuthStore {
  private static instance: AuthStore | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private ready: boolean = false;
  private accessToken: string = '';
  private refreshToken: string = '';
  private expiresAt: number = 0;
  private user: CloudUser | null = null;
  private baseUrl: string = CloudConfig.DEFAULT_BASE_URL;
  private useMock: boolean = CloudConfig.USE_MOCK;
  private revision: number = 0;
  private refreshInFlight: Promise<boolean> | null = null;

  static getInstance(): AuthStore {
    if (!AuthStore.instance) {
      AuthStore.instance = new AuthStore();
    }
    return AuthStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.ready) {
      return;
    }
    this.pref = await preferences.getPreferences(context, STORE_NAME);
    const accessPacked = await this.pref.get(KEY_ACCESS, '') as string;
    const refreshPacked = await this.pref.get(KEY_REFRESH, '') as string;
    try {
      const crypto = HuksCrypto.getInstance();
      await crypto.init();
      this.accessToken = await crypto.decryptPackedOrPlain(accessPacked);
      this.refreshToken = await crypto.decryptPackedOrPlain(refreshPacked);
    } catch (_e) {
      // HUKS 不可用时回退明文（兼容旧数据 / 模拟器）
      this.accessToken = accessPacked.startsWith('v1:') ? '' : accessPacked;
      this.refreshToken = refreshPacked.startsWith('v1:') ? '' : refreshPacked;
    }
    this.expiresAt = Number(await this.pref.get(KEY_EXPIRES, 0));
    this.baseUrl = await this.pref.get(KEY_BASE_URL, CloudConfig.DEFAULT_BASE_URL) as string;
    const mockRaw = await this.pref.get(KEY_USE_MOCK, CloudConfig.USE_MOCK ? '1' : '0') as string;
    this.useMock = mockRaw === '1' || mockRaw === 'true';
    const raw = await this.pref.get(KEY_USER_JSON, '') as string;
    if (raw && raw.length > 0) {
      try {
        this.user = JSON.parse(raw) as CloudUser;
      } catch (_e) {
        this.user = null;
      }
    }
    this.ready = true;
    this.publish();
  }

  isLoggedIn(): boolean {
    return this.accessToken.length > 0 && this.user !== null;
  }

  getAccessToken(): string {
    return this.accessToken;
  }

  getRefreshToken(): string {
    return this.refreshToken;
  }

  getExpiresAt(): number {
    return this.expiresAt;
  }

  getUser(): CloudUser | null {
    return this.user;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  isUseMock(): boolean {
    return this.useMock;
  }

  async setBaseUrl(url: string): Promise<void> {
    this.baseUrl = url.trim().replace(/\/$/, '');
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_BASE_URL, this.baseUrl);
    await this.pref.flush();
    this.publish();
  }

  async setUseMock(value: boolean): Promise<void> {
    this.useMock = value;
    if (!this.pref) {
      this.publish();
      return;
    }
    await this.pref.put(KEY_USE_MOCK, value ? '1' : '0');
    await this.pref.flush();
    this.publish();
  }

  async saveSession(tokens: AuthTokens): Promise<void> {
    this.accessToken = tokens.accessToken;
    this.refreshToken = tokens.refreshToken;
    this.expiresAt = tokens.expiresAt;
    this.user = tokens.user;
    if (!this.pref) {
      this.publish();
      return;
    }
    let accessStore = this.accessToken;
    let refreshStore = this.refreshToken;
    try {
      const crypto = HuksCrypto.getInstance();
      await crypto.init();
      accessStore = await crypto.encryptToPacked(this.accessToken);
      refreshStore = await crypto.encryptToPacked(this.refreshToken);
    } catch (_e) {
      // 明文回退
    }
    await this.pref.put(KEY_ACCESS, accessStore);
    await this.pref.put(KEY_REFRESH, refreshStore);
    await this.pref.put(KEY_EXPIRES, this.expiresAt);
    await this.pref.put(KEY_USER_JSON, JSON.stringify(this.user));
    await this.pref.flush();
    this.publish();
  }

  async clearSession(): Promise<void> {
    this.accessToken = '';
    this.refreshToken = '';
    this.expiresAt = 0;
    this.user = null;
    if (this.pref) {
      await this.pref.put(KEY_ACCESS, '');
      await this.pref.put(KEY_REFRESH, '');
      await this.pref.put(KEY_EXPIRES, 0);
      await this.pref.put(KEY_USER_JSON, '');
      await this.pref.flush();
    }
    this.publish();
  }

  /** access 是否即将过期（需 refresh） */
  isAccessExpiringSoon(): boolean {
    if (!this.expiresAt || this.expiresAt <= 0) {
      return false;
    }
    const nowSecs = Math.floor(Date.now() / 1000);
    return nowSecs >= (this.expiresAt - REFRESH_SKEW_SECS);
  }

  /**
   * 确保 access token 可用：临近过期时用 refresh_token 换新。
   * 并发调用会复用同一 in-flight Promise。
   */
  async ensureFreshAccessToken(): Promise<string> {
    if (this.useMock) {
      return this.accessToken;
    }
    if (!this.accessToken) {
      return '';
    }
    if (!this.isAccessExpiringSoon()) {
      return this.accessToken;
    }
    if (!this.refreshToken) {
      return this.accessToken;
    }
    const ok = await this.runRefresh();
    if (!ok) {
      throw new Error('登录已过期，请重新登录');
    }
    return this.accessToken;
  }

  async forceRefresh(): Promise<boolean> {
    if (this.useMock || !this.refreshToken) {
      return false;
    }
    return this.runRefresh();
  }

  private async runRefresh(): Promise<boolean> {
    if (this.refreshInFlight) {
      return this.refreshInFlight;
    }
    this.refreshInFlight = (async () => {
      try {
        const raw = await cloudRequestRaw('POST', '/api/v1/auth/refresh', {
          refresh_token: this.refreshToken
        }, null);
        const tokens = parseAuthResponse(raw);
        await this.saveSession(tokens);
        return true;
      } catch (_e) {
        await this.clearSession();
        return false;
      } finally {
        this.refreshInFlight = null;
      }
    })();
    return this.refreshInFlight;
  }

  private publish(): void {
    this.revision += 1;
    try {
      AppStorage.setOrCreate(AUTH_REV_KEY, this.revision);
    } catch (_e) {
      // ignore
    }
  }
}

/** HTTP 实现：对接 Rust 云端 `/api/v1/auth/*` */
export class HttpAuthService implements IAuthService {
  async register(email: string, username: string, password: string): Promise<AuthTokens> {
    return this.postAuth('/api/v1/auth/register', {
      email: email,
      username: username,
      password: password
    });
  }

  async login(login: string, password: string): Promise<AuthTokens> {
    return this.postAuth('/api/v1/auth/login', {
      login: login,
      password: password
    });
  }

  async refresh(): Promise<AuthTokens> {
    const store = AuthStore.getInstance();
    const rt = store.getRefreshToken();
    if (!rt) {
      throw new Error('无 refresh token');
    }
    const raw = await cloudRequestRaw('POST', '/api/v1/auth/refresh', {
      refresh_token: rt
    }, null);
    const tokens = parseAuthResponse(raw);
    await store.saveSession(tokens);
    return tokens;
  }

  async me(): Promise<CloudUser> {
    const store = AuthStore.getInstance();
    const token = await store.ensureFreshAccessToken();
    if (!token) {
      throw new Error('未登录');
    }
    const raw = await cloudRequest('GET', '/api/v1/me', null, token);
    return JSON.parse(raw) as CloudUser;
  }

  async logout(): Promise<void> {
    const store = AuthStore.getInstance();
    const token = store.getAccessToken();
    if (token) {
      try {
        await cloudRequestRaw('POST', '/api/v1/auth/logout', {}, token);
      } catch (_e) {
        // 服务端登出失败仍清本地
      }
    }
    await store.clearSession();
  }

  private async postAuth(path: string, body: object): Promise<AuthTokens> {
    const raw = await cloudRequestRaw('POST', path, body, null);
    const tokens = parseAuthResponse(raw);
    await AuthStore.getInstance().saveSession(tokens);
    return tokens;
  }
}

/**
 * Mock：离线演示帐号。任意非空凭据可登录；数据仅存本地 preferences。
 */
export class MockAuthService implements IAuthService {
  async register(email: string, username: string, password: string): Promise<AuthTokens> {
    // 与服务端 MIN_PASSWORD_LEN / 客户端校验对齐
    const e = (email ?? '').trim();
    const u = (username ?? '').trim();
    if (!e || e.indexOf('@') <= 0 || e.indexOf('@') >= e.length - 1) {
      throw new Error('请输入有效邮箱');
    }
    if (!u) {
      throw new Error('请填写用户名');
    }
    if (password.length < CloudConfig.MIN_PASSWORD_LEN) {
      throw new Error(`密码至少 ${CloudConfig.MIN_PASSWORD_LEN} 位`);
    }
    return this.fakeSession(e, u);
  }

  async login(login: string, password: string): Promise<AuthTokens> {
    if (!login || password.length < 1) {
      throw new Error('请填写帐号与密码');
    }
    const email = login.indexOf('@') >= 0 ? login : `${login}@mock.local`;
    const username = login.indexOf('@') >= 0 ? login.split('@')[0] : login;
    return this.fakeSession(email, username);
  }

  async me(): Promise<CloudUser> {
    const u = AuthStore.getInstance().getUser();
    if (!u) {
      throw new Error('未登录');
    }
    return u;
  }

  async logout(): Promise<void> {
    await AuthStore.getInstance().clearSession();
  }

  private async fakeSession(email: string, username: string): Promise<AuthTokens> {
    const tokens: AuthTokens = {
      accessToken: `mock_access_${Date.now()}`,
      refreshToken: `mock_refresh_${Date.now()}`,
      expiresAt: Math.floor(Date.now() / 1000) + 86400,
      user: {
        id: `mock_${username}`,
        email: email,
        username: username,
        created_at: Date.now()
      }
    };
    await AuthStore.getInstance().saveSession(tokens);
    return tokens;
  }
}

export class AuthServiceFactory {
  static create(): IAuthService {
    if (AuthStore.getInstance().isUseMock()) {
      return new MockAuthService();
    }
    return new HttpAuthService();
  }
}

function parseAuthResponse(raw: string): AuthTokens {
  const obj = JSON.parse(raw) as Record<string, Object>;
  const userObj = obj['user'] as Record<string, Object>;
  return {
    accessToken: `${obj['access_token']}`,
    refreshToken: `${obj['refresh_token']}`,
    expiresAt: Number(obj['expires_at'] ?? 0),
    user: {
      id: `${userObj['id']}`,
      email: `${userObj['email']}`,
      username: `${userObj['username']}`,
      created_at: Number(userObj['created_at'] ?? 0)
    }
  };
}

function isUnauthorizedMessage(msg: string): boolean {
  const m = msg.toLowerCase();
  return m.indexOf('401') >= 0 ||
    m.indexOf('unauthorized') >= 0 ||
    m.indexOf('invalid or expired') >= 0 ||
    m.indexOf('expired token') >= 0 ||
    m.indexOf('登录已过期') >= 0;
}

/**
 * 共享 HTTP 辅助：自动 refresh 临近过期的 access token；
 * 遇 401 再尝试一次 refresh 后重试。
 */
export async function cloudRequest(
  method: string,
  path: string,
  body: object | null,
  bearer: string | null
): Promise<string> {
  const store = AuthStore.getInstance();
  let token = bearer;
  if (token && token.length > 0 && !store.isUseMock()) {
    try {
      token = await store.ensureFreshAccessToken();
    } catch (e) {
      throw e;
    }
  }
  try {
    return await cloudRequestRaw(method, path, body, token);
  } catch (e) {
    const msg = e instanceof Error ? e.message : `${e}`;
    if (token && isUnauthorizedMessage(msg) && store.getRefreshToken() && !store.isUseMock()) {
      const ok = await store.forceRefresh();
      if (ok) {
        return await cloudRequestRaw(method, path, body, store.getAccessToken());
      }
    }
    throw e;
  }
}

/** 将服务端错误正文裁成可读片段 */
function snippetServerBody(raw: string, maxLen: number = 180): string {
  const t = (raw ?? '').trim().replace(/\s+/g, ' ');
  if (!t) {
    return '';
  }
  return t.length <= maxLen ? t : `${t.substring(0, maxLen)}…`;
}

function isNetworkFailureMessage(msg: string): boolean {
  const m = msg.toLowerCase();
  return m.indexOf('connect') >= 0 ||
    m.indexOf('network') >= 0 ||
    m.indexOf('timeout') >= 0 ||
    m.indexOf('timed out') >= 0 ||
    m.indexOf('failed to connect') >= 0 ||
    m.indexOf('could not connect') >= 0 ||
    m.indexOf('unreachable') >= 0 ||
    m.indexOf('econnrefused') >= 0 ||
    m.indexOf('socket') >= 0 ||
    m.indexOf('ssl') >= 0 ||
    m.indexOf('cleartext') >= 0 ||
    m.indexOf('dns') >= 0 ||
    m.indexOf('无法连接') >= 0;
}

/** 底层 HTTP（不做 refresh，供 refresh/login 自身使用，避免递归） */
export async function cloudRequestRaw(
  method: string,
  path: string,
  body: object | null,
  bearer: string | null
): Promise<string> {
  const base = AuthStore.getInstance().getBaseUrl();
  const url = `${base}${path}`;
  const req = http.createHttp();
  try {
    const headers: object = bearer && bearer.length > 0 ? {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': `Bearer ${bearer}`
    } : {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    let httpMethod: http.RequestMethod = http.RequestMethod.GET;
    if (method === 'POST') {
      httpMethod = http.RequestMethod.POST;
    } else if (method === 'PUT') {
      httpMethod = http.RequestMethod.PUT;
    } else if (method === 'DELETE') {
      httpMethod = http.RequestMethod.DELETE;
    }
    const options: http.HttpRequestOptions = {
      method: httpMethod,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000
    };
    if (body !== null) {
      options.extraData = JSON.stringify(body);
    }
    let resp: http.HttpResponse;
    try {
      resp = await req.request(url, options);
    } catch (netErr) {
      const raw = netErr instanceof Error ? netErr.message : `${netErr}`;
      if (isNetworkFailureMessage(raw) || !raw || raw.length === 0) {
        throw new Error('无法连接服务器，请检查地址与 cleartext');
      }
      throw new Error(`无法连接服务器，请检查地址与 cleartext（${snippetServerBody(raw, 80)}）`);
    }
    const code = resp.responseCode;
    const result = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
    if (code < 200 || code >= 300) {
      let msg = `HTTP ${code}`;
      let bodySnippet = '';
      try {
        const errObj = JSON.parse(result) as Record<string, Object>;
        if (errObj['error']) {
          msg = `${errObj['error']}`;
        } else if (errObj['message']) {
          msg = `${errObj['message']}`;
        } else {
          bodySnippet = snippetServerBody(result);
          if (bodySnippet) {
            msg = `HTTP ${code}：${bodySnippet}`;
          }
        }
      } catch (_e) {
        bodySnippet = snippetServerBody(result);
        if (bodySnippet) {
          msg = `HTTP ${code}：${bodySnippet}`;
        }
      }
      if (code === 401) {
        msg = msg.indexOf('401') >= 0 ? msg : `401 ${msg}`;
      }
      if (code === 429) {
        msg = msg.indexOf('too many') >= 0 || msg.indexOf('频繁') >= 0
          ? msg
          : `请求过于频繁（429），请稍后再试`;
      }
      throw new Error(msg);
    }
    return result;
  } finally {
    req.destroy();
  }
}
