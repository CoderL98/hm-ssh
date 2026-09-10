import { browser } from '$app/environment';
import { env } from '$env/dynamic/public';

export function apiBase(): string {
	const raw = env.PUBLIC_API_BASE || 'http://127.0.0.1:8080';
	return raw.replace(/\/$/, '');
}

export type AuthUser = {
	id: string;
	email: string;
	username: string;
	created_at: number;
	is_admin?: boolean;
};

export type AuthResponse = {
	access_token: string;
	refresh_token: string;
	token_type: string;
	expires_at: number;
	user: AuthUser;
};

export type AdminStats = {
	user_count: number;
	admin_count: number;
	disabled_count: number;
	health: string;
	db_backend: string;
};

export type AdminUser = {
	id: string;
	email: string;
	username: string;
	created_at: number;
	last_login_at: number | null;
	is_admin: boolean;
	disabled: boolean;
	deleted_at: number | null;
};

export type SyncMeta = {
	hosts: { updated_at: number; byte_size: number; item_count: number | null };
	settings: { updated_at: number; byte_size: number; item_count: number | null };
};

const TOKEN_KEY = 'hmssh_admin_token';
const REFRESH_KEY = 'hmssh_admin_refresh';
const EXPIRES_KEY = 'hmssh_admin_expires_at';
const USER_KEY = 'hmssh_admin_user';

/** Mirror client skew: refresh ~60s before access expiry */
const REFRESH_SKEW_SECS = 60;

let refreshInFlight: Promise<boolean> | null = null;

export function getToken(): string | null {
	if (!browser) return null;
	return localStorage.getItem(TOKEN_KEY);
}

export function getRefreshToken(): string | null {
	if (!browser) return null;
	return localStorage.getItem(REFRESH_KEY);
}

export function getExpiresAt(): number {
	if (!browser) return 0;
	const raw = localStorage.getItem(EXPIRES_KEY);
	if (!raw) return 0;
	const n = Number(raw);
	return Number.isFinite(n) ? n : 0;
}

export function getStoredUser(): AuthUser | null {
	if (!browser) return null;
	const raw = localStorage.getItem(USER_KEY);
	if (!raw) return null;
	try {
		return JSON.parse(raw) as AuthUser;
	} catch {
		return null;
	}
}

export function setSession(auth: AuthResponse) {
	if (!browser) return;
	localStorage.setItem(TOKEN_KEY, auth.access_token);
	localStorage.setItem(REFRESH_KEY, auth.refresh_token);
	localStorage.setItem(EXPIRES_KEY, String(auth.expires_at ?? 0));
	localStorage.setItem(USER_KEY, JSON.stringify(auth.user));
}

export function clearSession() {
	if (!browser) return;
	localStorage.removeItem(TOKEN_KEY);
	localStorage.removeItem(REFRESH_KEY);
	localStorage.removeItem(EXPIRES_KEY);
	localStorage.removeItem(USER_KEY);
}

function redirectToLogin() {
	if (!browser) return;
	clearSession();
	const path = window.location.pathname || '';
	if (!path.startsWith('/login')) {
		window.location.assign('/login');
	}
}

function isAccessExpiringSoon(): boolean {
	const expiresAt = getExpiresAt();
	if (!expiresAt || expiresAt <= 0) return false;
	const nowSecs = Math.floor(Date.now() / 1000);
	return nowSecs >= expiresAt - REFRESH_SKEW_SECS;
}

async function parseError(res: Response): Promise<string> {
	try {
		const j = await res.json();
		return (j?.error as string) || res.statusText || 'request failed';
	} catch {
		return res.statusText || 'request failed';
	}
}

/**
 * Exchange refresh_token for a new pair. Concurrent callers share one in-flight promise.
 * On failure clears session and redirects to login.
 */
export async function refreshSession(): Promise<boolean> {
	if (!browser) return false;
	if (refreshInFlight) return refreshInFlight;

	refreshInFlight = (async () => {
		const rt = getRefreshToken();
		if (!rt) {
			redirectToLogin();
			return false;
		}
		try {
			const res = await fetch(`${apiBase()}/api/v1/auth/refresh`, {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ refresh_token: rt })
			});
			if (!res.ok) {
				redirectToLogin();
				return false;
			}
			const auth = (await res.json()) as AuthResponse;
			if (!auth?.access_token || !auth?.refresh_token) {
				redirectToLogin();
				return false;
			}
			// Keep existing user if refresh payload omits it
			if (!auth.user) {
				const prev = getStoredUser();
				if (prev) auth.user = prev;
			}
			if (auth.user && auth.user.is_admin === false) {
				redirectToLogin();
				return false;
			}
			setSession(auth);
			return true;
		} catch {
			redirectToLogin();
			return false;
		} finally {
			refreshInFlight = null;
		}
	})();

	return refreshInFlight;
}

async function ensureFreshAccessToken(): Promise<string | null> {
	const token = getToken();
	if (!token) return null;
	if (!isAccessExpiringSoon()) return token;
	const ok = await refreshSession();
	return ok ? getToken() : null;
}

export async function apiFetch<T>(
	path: string,
	opts: RequestInit & { auth?: boolean } = {}
): Promise<T> {
	const { auth = true, headers, ...rest } = opts;
	const h = new Headers(headers);
	if (!h.has('content-type') && rest.body) {
		h.set('content-type', 'application/json');
	}

	if (auth) {
		const token = await ensureFreshAccessToken();
		if (!token) {
			redirectToLogin();
			throw new Error('未登录');
		}
		h.set('authorization', `Bearer ${token}`);
	}

	let res = await fetch(`${apiBase()}${path}`, { ...rest, headers: h });

	if (auth && res.status === 401) {
		const ok = await refreshSession();
		if (!ok) {
			throw new Error('登录已过期，请重新登录');
		}
		const retryHeaders = new Headers(headers);
		if (!retryHeaders.has('content-type') && rest.body) {
			retryHeaders.set('content-type', 'application/json');
		}
		const fresh = getToken();
		if (!fresh) {
			redirectToLogin();
			throw new Error('未登录');
		}
		retryHeaders.set('authorization', `Bearer ${fresh}`);
		res = await fetch(`${apiBase()}${path}`, { ...rest, headers: retryHeaders });
	}

	if (!res.ok) {
		if (res.status === 401) {
			redirectToLogin();
		}
		throw new Error(await parseError(res));
	}
	if (res.status === 204) return undefined as T;
	return (await res.json()) as T;
}

export async function login(login: string, password: string): Promise<AuthResponse> {
	const auth = await apiFetch<AuthResponse>('/api/v1/auth/login', {
		method: 'POST',
		auth: false,
		body: JSON.stringify({ login, password })
	});
	if (!auth.user?.is_admin) {
		clearSession();
		throw new Error('需要管理员帐号');
	}
	setSession(auth);
	return auth;
}

export async function fetchStats() {
	return apiFetch<AdminStats>('/api/v1/admin/stats');
}

export type AdminUserPage = {
	items: AdminUser[];
	total: number;
	page: number;
	page_size: number;
};

export async function fetchUsers(opts?: { q?: string; page?: number; page_size?: number }) {
	const params = new URLSearchParams();
	if (opts?.q?.trim()) params.set('q', opts.q.trim());
	if (opts?.page) params.set('page', String(opts.page));
	if (opts?.page_size) params.set('page_size', String(opts.page_size));
	const qs = params.toString() ? `?${params.toString()}` : '';
	return apiFetch<AdminUserPage>(`/api/v1/admin/users${qs}`);
}

export async function fetchUser(id: string) {
	return apiFetch<AdminUser>(`/api/v1/admin/users/${encodeURIComponent(id)}`);
}

export async function patchUser(id: string, body: { disabled?: boolean }) {
	return apiFetch<AdminUser>(`/api/v1/admin/users/${encodeURIComponent(id)}`, {
		method: 'PATCH',
		body: JSON.stringify(body)
	});
}

export async function deleteUser(id: string) {
	return apiFetch<{ ok: boolean }>(`/api/v1/admin/users/${encodeURIComponent(id)}`, {
		method: 'DELETE'
	});
}

export async function revokeUser(id: string) {
	return apiFetch<{ ok: boolean }>(`/api/v1/admin/users/${encodeURIComponent(id)}/revoke`, {
		method: 'POST'
	});
}

export async function fetchUserSync(id: string) {
	return apiFetch<SyncMeta>(`/api/v1/admin/users/${encodeURIComponent(id)}/sync`);
}

export type HealthInfo = {
	status?: string;
	service?: string;
	db?: string;
	db_backend?: string;
	cache?: string;
	uptime_ms?: number;
};

export async function fetchHealth(): Promise<HealthInfo | null> {
	try {
		const res = await fetch(`${apiBase()}/health`);
		if (!res.ok) return null;
		return (await res.json()) as HealthInfo;
	} catch {
		return null;
	}
}

export function formatMs(ms: number | null | undefined): string {
	if (ms == null || ms === 0) return '—';
	try {
		return new Date(ms).toLocaleString();
	} catch {
		return String(ms);
	}
}
