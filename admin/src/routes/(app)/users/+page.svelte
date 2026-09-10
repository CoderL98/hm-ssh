<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		deleteUser,
		fetchUsers,
		formatMs,
		patchUser,
		type AdminUser
	} from '$lib/api';
	import { Button } from '$lib/components/ui/button/index.js';
	import { Input } from '$lib/components/ui/input/index.js';
	import { Badge } from '$lib/components/ui/badge/index.js';
	import * as Table from '$lib/components/ui/table/index.js';
	import * as Card from '$lib/components/ui/card/index.js';
	import { Skeleton } from '$lib/components/ui/skeleton/index.js';
	import { toast } from 'svelte-sonner';

	let users = $state<AdminUser[]>([]);
	let q = $state('');
	let loading = $state(true);
	let debounceTimer: ReturnType<typeof setTimeout> | null = null;
	let requestSeq = 0;

	async function load(search = q) {
		const seq = ++requestSeq;
		loading = true;
		try {
			const list = await fetchUsers(search);
			if (seq !== requestSeq) return; // stale
			users = list;
		} catch (e) {
			if (seq !== requestSeq) return;
			toast.error(e instanceof Error ? e.message : '加载失败');
		} finally {
			if (seq === requestSeq) loading = false;
		}
	}

	onMount(load);

	function scheduleSearch(value: string) {
		q = value;
		if (debounceTimer) clearTimeout(debounceTimer);
		debounceTimer = setTimeout(() => {
			void load(value);
		}, 300);
	}

	async function onSearch(e: Event) {
		e.preventDefault();
		if (debounceTimer) clearTimeout(debounceTimer);
		await load(q);
	}

	async function toggleDisabled(u: AdminUser) {
		const next = !u.disabled;
		if (next && !confirm(`确认禁用用户 ${u.email}？其会话将被吊销。`)) return;
		try {
			const updated = await patchUser(u.id, { disabled: next });
			users = users.map((x) => (x.id === u.id ? updated : x));
			toast.success(updated.disabled ? '已禁用' : '已启用');
		} catch (e) {
			toast.error(e instanceof Error ? e.message : '操作失败');
		}
	}

	async function onDelete(u: AdminUser) {
		if (!confirm(`确认软删除用户 ${u.email}？此操作会禁用帐号并吊销会话。`)) return;
		try {
			await deleteUser(u.id);
			users = users.filter((x) => x.id !== u.id);
			toast.success('已软删除');
		} catch (e) {
			toast.error(e instanceof Error ? e.message : '删除失败');
		}
	}
</script>

<div class="flex flex-col gap-4">
	<div class="flex flex-col gap-1">
		<h1 class="text-2xl font-semibold tracking-tight">用户</h1>
		<p class="text-sm text-muted-foreground">搜索（自动防抖）、禁用/启用与软删除</p>
	</div>

	<form class="flex flex-wrap items-center gap-2" onsubmit={onSearch}>
		<Input
			class="max-w-sm"
			placeholder="搜索邮箱 / 用户名 / id"
			value={q}
			oninput={(e) => scheduleSearch((e.currentTarget as HTMLInputElement).value)}
		/>
		<Button type="submit" variant="secondary">搜索</Button>
		<Button
			type="button"
			variant="outline"
			onclick={() => {
				q = '';
				load('');
			}}>重置</Button
		>
	</form>

	<Card.Root>
		<Card.Content class="p-0">
			<Table.Root>
				<Table.Header>
					<Table.Row>
						<Table.Head>ID</Table.Head>
						<Table.Head>邮箱 / 用户名</Table.Head>
						<Table.Head>创建时间</Table.Head>
						<Table.Head>最近登录</Table.Head>
						<Table.Head>状态</Table.Head>
						<Table.Head class="text-right">操作</Table.Head>
					</Table.Row>
				</Table.Header>
				<Table.Body>
					{#if loading}
						{#each Array.from({ length: 5 }) as _, i (i)}
							<Table.Row>
								<Table.Cell colspan={6}>
									<Skeleton class="h-8 w-full" />
								</Table.Cell>
							</Table.Row>
						{/each}
					{:else if users.length === 0}
						<Table.Row>
							<Table.Cell colspan={6} class="text-muted-foreground">无用户</Table.Cell>
						</Table.Row>
					{:else}
						{#each users as u (u.id)}
							<Table.Row>
								<Table.Cell class="max-w-[8rem] truncate font-mono text-xs">
									<button class="underline-offset-2 hover:underline" onclick={() => goto(`/users/${u.id}`)}>
										{u.id.slice(0, 8)}…
									</button>
								</Table.Cell>
								<Table.Cell>
									<div class="flex flex-col gap-0.5">
										<span class="font-medium">{u.email}</span>
										<span class="text-xs text-muted-foreground">@{u.username}</span>
									</div>
								</Table.Cell>
								<Table.Cell class="text-sm">{formatMs(u.created_at)}</Table.Cell>
								<Table.Cell class="text-sm">{formatMs(u.last_login_at)}</Table.Cell>
								<Table.Cell>
									<div class="flex flex-wrap gap-1">
										{#if u.is_admin}
											<Badge>admin</Badge>
										{/if}
										{#if u.disabled}
											<Badge variant="destructive">disabled</Badge>
										{:else}
											<Badge variant="secondary">active</Badge>
										{/if}
									</div>
								</Table.Cell>
								<Table.Cell class="text-right">
									<div class="flex justify-end gap-1">
										<Button size="sm" variant="outline" onclick={() => goto(`/users/${u.id}`)}>
											详情
										</Button>
										<Button size="sm" variant="secondary" onclick={() => toggleDisabled(u)}>
											{u.disabled ? '启用' : '禁用'}
										</Button>
										<Button size="sm" variant="destructive" onclick={() => onDelete(u)}>
											删除
										</Button>
									</div>
								</Table.Cell>
							</Table.Row>
						{/each}
					{/if}
				</Table.Body>
			</Table.Root>
		</Card.Content>
	</Card.Root>
</div>
