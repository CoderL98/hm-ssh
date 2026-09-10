<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { clearSession, getStoredUser, type AuthUser } from '$lib/api';
	import { Button } from '$lib/components/ui/button/index.js';
	import { Separator } from '$lib/components/ui/separator/index.js';
	import * as Sidebar from '$lib/components/ui/sidebar/index.js';
	import { toggleMode, mode } from 'mode-watcher';
	import RiDashboardLine from 'remixicon-svelte/icons/dashboard-line';
	import RiUserLine from 'remixicon-svelte/icons/user-line';
	import RiMoonLine from 'remixicon-svelte/icons/moon-line';
	import RiSunLine from 'remixicon-svelte/icons/sun-line';
	import RiLogoutBoxRLine from 'remixicon-svelte/icons/logout-box-r-line';

	let { children } = $props();

	let user = $state<AuthUser | null>(null);
	$effect(() => {
		user = getStoredUser();
	});

	function logout() {
		clearSession();
		goto('/login');
	}

	const path = $derived(page.url.pathname);
</script>

<Sidebar.Provider>
	<Sidebar.Root>
		<Sidebar.Header>
			<div class="flex flex-col gap-1 px-2 py-1">
				<span class="text-sm font-semibold tracking-tight">HmSSH Admin</span>
				<span class="text-xs text-muted-foreground">云端管理控制台</span>
			</div>
		</Sidebar.Header>
		<Sidebar.Separator />
		<Sidebar.Content>
			<Sidebar.Group>
				<Sidebar.GroupLabel>导航</Sidebar.GroupLabel>
				<Sidebar.GroupContent>
					<Sidebar.Menu>
						<Sidebar.MenuItem>
							<Sidebar.MenuButton isActive={path === '/'}>
								{#snippet child({ props })}
									<a href="/" {...props}>
										<RiDashboardLine />
										<span>仪表盘</span>
									</a>
								{/snippet}
							</Sidebar.MenuButton>
						</Sidebar.MenuItem>
						<Sidebar.MenuItem>
							<Sidebar.MenuButton isActive={path.startsWith('/users')}>
								{#snippet child({ props })}
									<a href="/users" {...props}>
										<RiUserLine />
										<span>用户</span>
									</a>
								{/snippet}
							</Sidebar.MenuButton>
						</Sidebar.MenuItem>
					</Sidebar.Menu>
				</Sidebar.GroupContent>
			</Sidebar.Group>
		</Sidebar.Content>
		<Sidebar.Footer>
			<div class="flex flex-col gap-2 p-2">
				{#if user}
					<div class="flex flex-col gap-0.5 px-1">
						<span class="truncate text-sm font-medium">{user.username}</span>
						<span class="truncate text-xs text-muted-foreground">{user.email}</span>
					</div>
				{/if}
				<div class="flex items-center gap-2">
					<Button variant="outline" size="sm" onclick={() => toggleMode()} class="flex-1">
						{#if mode.current === 'dark'}
							<RiSunLine />
							<span>浅色</span>
						{:else}
							<RiMoonLine />
							<span>深色</span>
						{/if}
					</Button>
					<Button variant="ghost" size="sm" onclick={logout}>
						<RiLogoutBoxRLine />
						<span>退出</span>
					</Button>
				</div>
			</div>
		</Sidebar.Footer>
		<Sidebar.Rail />
	</Sidebar.Root>
	<Sidebar.Inset>
		<header class="flex h-12 items-center gap-2 border-b px-4">
			<Sidebar.Trigger />
			<Separator orientation="vertical" class="h-4" />
			<span class="text-sm text-muted-foreground">管理后台</span>
		</header>
		<main class="flex flex-1 flex-col gap-4 p-4 md:p-6">
			{@render children()}
		</main>
	</Sidebar.Inset>
</Sidebar.Provider>
