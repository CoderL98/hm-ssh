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
const USER_KEY = 'hmssh_admin_user';

export function getToken(): string | null {
	if (!browser) return null;
	return localStorage.getItem(TOKEN_KEY);
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
	localStorage.setItem(USER_KEY, JSON.stringify(auth.user));
}

export function clearSession() {
	if (!browser) return;
	localStorage.removeItem(TOKEN_KEY);
	localStorage.removeItem(REFRESH_KEY);
	localStorage.removeItem(USER_KEY);
}

async function parseError(res: Response): Promise<string> {
	try {
		const j = await res.json();
		return (j?.error as string) || res.statusText || 'request failed';
	} catch {
		return res.statusText || 'request failed';
	}
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
		const token = getToken();
		if (!token) throw new Error('未登录');
		h.set('authorization', `Bearer ${token}`);
	}
	const res = await fetch(`${apiBase()}${path}`, { ...rest, headers: h });
	if (!res.ok) {
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

export async function fetchUsers(q?: string) {
	const qs = q?.trim() ? `?q=${encodeURIComponent(q.trim())}` : '';
	return apiFetch<AdminUser[]>(`/api/v1/admin/users${qs}`);
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

export async function fetchHealth(): Promise<{ status?: string } | null> {
	try {
		const res = await fetch(`${apiBase()}/health`);
		if (!res.ok) return null;
		return (await res.json()) as { status?: string };
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
