<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchHealth, fetchStats, type AdminStats, type HealthInfo } from '$lib/api';
	import * as Card from '$lib/components/ui/card/index.js';
	import { Badge } from '$lib/components/ui/badge/index.js';
	import { Skeleton } from '$lib/components/ui/skeleton/index.js';
	import { toast } from 'svelte-sonner';

	let stats = $state<AdminStats | null>(null);
	let health = $state<HealthInfo | null>(null);
	let healthOk = $state<boolean | null>(null);
	let loading = $state(true);

	onMount(async () => {
		try {
			const [s, h] = await Promise.all([fetchStats(), fetchHealth()]);
			stats = s;
			health = h;
			healthOk = !!h && h.status === 'ok';
		} catch (e) {
			toast.error(e instanceof Error ? e.message : '加载失败');
		} finally {
			loading = false;
		}
	});
</script>

<div class="flex flex-col gap-4">
	<div class="flex items-center justify-between gap-2">
		<div class="flex flex-col gap-1">
			<h1 class="text-2xl font-semibold tracking-tight">仪表盘</h1>
			<p class="text-sm text-muted-foreground">用户与服务健康概览</p>
		</div>
		{#if healthOk === true}
			<Badge variant="secondary">API 健康</Badge>
		{:else if healthOk === false}
			<Badge variant="destructive">API 异常 / 不可达</Badge>
		{/if}
	</div>

	{#if loading}
		<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
			{#each Array.from({ length: 4 }) as _, i (i)}
				<Skeleton class="h-28 w-full rounded-xl" />
			{/each}
		</div>
	{:else if stats}
		<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
			<Card.Root>
				<Card.Header>
					<Card.Description>用户总数</Card.Description>
					<Card.Title class="text-3xl">{stats.user_count}</Card.Title>
				</Card.Header>
			</Card.Root>
			<Card.Root>
				<Card.Header>
					<Card.Description>管理员</Card.Description>
					<Card.Title class="text-3xl">{stats.admin_count}</Card.Title>
				</Card.Header>
			</Card.Root>
			<Card.Root>
				<Card.Header>
					<Card.Description>已禁用</Card.Description>
					<Card.Title class="text-3xl">{stats.disabled_count}</Card.Title>
				</Card.Header>
			</Card.Root>
			<Card.Root>
				<Card.Header>
					<Card.Description>服务状态</Card.Description>
					<Card.Title class="flex flex-wrap items-center gap-2 text-xl">
						{stats.health}
						<Badge>{stats.db_backend}</Badge>
					</Card.Title>
					{#if health}
						<Card.Description class="pt-2">
							db={health.db ?? '—'} · cache={health.cache ?? '—'}
							{#if health.uptime_ms != null}
								· uptime {Math.round(health.uptime_ms / 1000)}s
							{/if}
						</Card.Description>
					{/if}
				</Card.Header>
			</Card.Root>
		</div>
	{/if}
</div>
