import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { CloudConfig } from '../common/Constants';

const STORE_NAME = 'hm_ssh_auth';
const KEY_ACCESS = 'access_token';
const KEY_REFRESH = 'refresh_token';
const KEY_USER_JSON = 'user_json';
const KEY_BASE_URL = 'cloud_base_url';
const AUTH_REV_KEY = 'authRev';

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
}

/**
 * 帐号与 JWT 本地缓存（preferences）。
 * 正式版应将 token 迁入 HUKS；当前为演示接缝。
 */
export class AuthStore {
  private static instance: AuthStore | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private ready: boolean = false;
  private accessToken: string = '';
  private refreshToken: string = '';
  private user: CloudUser | null = null;
  private baseUrl: string = CloudConfig.DEFAULT_BASE_URL;
  private revision: number = 0;

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
    this.accessToken = await this.pref.get(KEY_ACCESS, '') as string;
    this.refreshToken = await this.pref.get(KEY_REFRESH, '') as string;
    this.baseUrl = await this.pref.get(KEY_BASE_URL, CloudConfig.DEFAULT_BASE_URL) as string;
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

  getUser(): CloudUser | null {
    return this.user;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  async setBaseUrl(url: string): Promise<void> {
    this.baseUrl = url.trim().replace(/\/$/, '');
    if (!this.pref) {
      return;
    }
    await this.pref.put(KEY_BASE_URL, this.baseUrl);
    await this.pref.flush();
  }

  async saveSession(tokens: AuthTokens): Promise<void> {
    this.accessToken = tokens.accessToken;
    this.refreshToken = tokens.refreshToken;
    this.user = tokens.user;
    if (!this.pref) {
      this.publish();
      return;
    }
    await this.pref.put(KEY_ACCESS, this.accessToken);
    await this.pref.put(KEY_REFRESH, this.refreshToken);
    await this.pref.put(KEY_USER_JSON, JSON.stringify(this.user));
    await this.pref.flush();
    this.publish();
  }

  async clearSession(): Promise<void> {
    this.accessToken = '';
    this.refreshToken = '';
    this.user = null;
    if (this.pref) {
      await this.pref.put(KEY_ACCESS, '');
      await this.pref.put(KEY_REFRESH, '');
      await this.pref.put(KEY_USER_JSON, '');
      await this.pref.flush();
    }
    this.publish();
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

  async me(): Promise<CloudUser> {
    const store = AuthStore.getInstance();
    const token = store.getAccessToken();
    if (!token) {
      throw new Error('未登录');
    }
    const raw = await cloudRequest('GET', '/api/v1/me', null, token);
    return JSON.parse(raw) as CloudUser;
  }

  async logout(): Promise<void> {
    await AuthStore.getInstance().clearSession();
  }

  private async postAuth(path: string, body: object): Promise<AuthTokens> {
    const raw = await cloudRequest('POST', path, body, null);
    const obj = JSON.parse(raw) as Record<string, Object>;
    const userObj = obj['user'] as Record<string, Object>;
    const tokens: AuthTokens = {
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
    await AuthStore.getInstance().saveSession(tokens);
    return tokens;
  }
}

/**
 * Mock：离线演示帐号。任意非空凭据可登录；数据仅存本地 preferences。
 */
export class MockAuthService implements IAuthService {
  async register(email: string, username: string, password: string): Promise<AuthTokens> {
    if (!email || !username || password.length < 4) {
      throw new Error('请填写邮箱、用户名与密码');
    }
    return this.fakeSession(email, username);
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
  /** 默认：有 USE_MOCK_CLOUD 时用 Mock，否则 HTTP */
  static create(): IAuthService {
    if (CloudConfig.USE_MOCK) {
      return new MockAuthService();
    }
    return new HttpAuthService();
  }
}

/** 共享 HTTP 辅助：供 Auth / CloudSync 使用 */
export async function cloudRequest(
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
    const resp = await req.request(url, options);
    const code = resp.responseCode;
    const result = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
    if (code < 200 || code >= 300) {
      let msg = `HTTP ${code}`;
      try {
        const errObj = JSON.parse(result) as Record<string, string>;
        if (errObj['error']) {
          msg = errObj['error'];
        }
      } catch (_e) {
        if (result && result.length > 0 && result.length < 200) {
          msg = result;
        }
      }
      throw new Error(msg);
    }
    return result;
  } finally {
    req.destroy();
  }
}
