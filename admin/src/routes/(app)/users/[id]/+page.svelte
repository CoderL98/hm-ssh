<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import {
		fetchUser,
		fetchUserSync,
		formatMs,
		patchUser,
		revokeUser,
		type AdminUser,
		type SyncMeta
	} from '$lib/api';
	import { Button } from '$lib/components/ui/button/index.js';
	import { Badge } from '$lib/components/ui/badge/index.js';
	import * as Card from '$lib/components/ui/card/index.js';
	import { toast } from 'svelte-sonner';

	const id = $derived(page.params.id ?? '');

	let user = $state<AdminUser | null>(null);
	let sync = $state<SyncMeta | null>(null);
	let loading = $state(true);

	async function load() {
		if (!id) return;
		loading = true;
		try {
			const [u, s] = await Promise.all([fetchUser(id), fetchUserSync(id)]);
			user = u;
			sync = s;
		} catch (e) {
			toast.error(e instanceof Error ? e.message : '加载失败');
		} finally {
			loading = false;
		}
	}

	onMount(load);

	async function toggleDisabled() {
		if (!user) return;
		const next = !user.disabled;
		if (next && !confirm(`确认禁用用户 ${user.email}？其会话将被吊销。`)) return;
		try {
			user = await patchUser(user.id, { disabled: next });
			toast.success(user.disabled ? '已禁用' : '已启用');
		} catch (e) {
			toast.error(e instanceof Error ? e.message : '操作失败');
		}
	}

	async function forceLogout() {
		if (!user) return;
		if (!confirm('强制注销该用户所有会话？')) return;
		try {
			await revokeUser(user.id);
			toast.success('已吊销会话');
		} catch (e) {
			toast.error(e instanceof Error ? e.message : '吊销失败');
		}
	}
</script>

<div class="flex flex-col gap-4">
	<div class="flex flex-wrap items-center justify-between gap-2">
		<div class="flex flex-col gap-1">
			<h1 class="text-2xl font-semibold tracking-tight">用户详情</h1>
			<p class="font-mono text-xs text-muted-foreground">{id}</p>
		</div>
		<Button variant="outline" onclick={() => goto('/users')}>返回列表</Button>
	</div>

	{#if loading}
		<p class="text-sm text-muted-foreground">加载中…</p>
	{:else if user}
		<div class="grid gap-4 lg:grid-cols-2">
			<Card.Root>
				<Card.Header>
					<Card.Title class="flex flex-wrap items-center gap-2">
						{user.username}
						{#if user.is_admin}<Badge>admin</Badge>{/if}
						{#if user.disabled}
							<Badge variant="destructive">disabled</Badge>
						{:else}
							<Badge variant="secondary">active</Badge>
						{/if}
					</Card.Title>
					<Card.Description>{user.email}</Card.Description>
				</Card.Header>
				<Card.Content>
					<div class="flex flex-col gap-2 text-sm">
						<div class="flex justify-between gap-2">
							<span class="text-muted-foreground">创建时间</span>
							<span>{formatMs(user.created_at)}</span>
						</div>
						<div class="flex justify-between gap-2">
							<span class="text-muted-foreground">最近登录</span>
							<span>{formatMs(user.last_login_at)}</span>
						</div>
						<div class="flex justify-between gap-2">
							<span class="text-muted-foreground">删除标记</span>
							<span>{formatMs(user.deleted_at)}</span>
						</div>
					</div>
				</Card.Content>
				<Card.Footer class="flex flex-wrap gap-2">
					<Button variant="secondary" onclick={toggleDisabled}>
						{user.disabled ? '启用帐号' : '禁用帐号'}
					</Button>
					<Button variant="destructive" onclick={forceLogout}>强制注销</Button>
				</Card.Footer>
			</Card.Root>

			<Card.Root>
				<Card.Header>
					<Card.Title>同步元数据</Card.Title>
					<Card.Description>仅大小与时间戳，不含密钥原文</Card.Description>
				</Card.Header>
				<Card.Content>
					{#if sync}
						<div class="flex flex-col gap-4">
							<div class="flex flex-col gap-2 rounded-lg border p-3">
								<div class="flex items-center justify-between">
									<span class="font-medium">Hosts</span>
									<Badge variant="secondary">{sync.hosts.item_count ?? 0} 条</Badge>
								</div>
								<div class="flex justify-between text-sm text-muted-foreground">
									<span>更新于</span>
									<span>{formatMs(sync.hosts.updated_at)}</span>
								</div>
								<div class="flex justify-between text-sm text-muted-foreground">
									<span>体积</span>
									<span>{sync.hosts.byte_size} B</span>
								</div>
							</div>
							<div class="flex flex-col gap-2 rounded-lg border p-3">
								<div class="flex items-center justify-between">
									<span class="font-medium">Settings</span>
								</div>
								<div class="flex justify-between text-sm text-muted-foreground">
									<span>更新于</span>
									<span>{formatMs(sync.settings.updated_at)}</span>
								</div>
								<div class="flex justify-between text-sm text-muted-foreground">
									<span>体积</span>
									<span>{sync.settings.byte_size} B</span>
								</div>
							</div>
						</div>
					{:else}
						<p class="text-sm text-muted-foreground">无同步数据</p>
					{/if}
				</Card.Content>
			</Card.Root>
		</div>
	{/if}
</div>
