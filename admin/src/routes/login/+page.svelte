<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { apiBase, getToken, getStoredUser, login } from '$lib/api';
	import { Button } from '$lib/components/ui/button/index.js';
	import { Input } from '$lib/components/ui/input/index.js';
	import { Label } from '$lib/components/ui/label/index.js';
	import * as Card from '$lib/components/ui/card/index.js';
	import * as Alert from '$lib/components/ui/alert/index.js';
	import { toast } from 'svelte-sonner';

	let loginId = $state('');
	let password = $state('');
	let loading = $state(false);
	let error = $state('');

	onMount(() => {
		if (!browser) return;
		if (getToken() && getStoredUser()?.is_admin) {
			goto('/');
		}
	});

	async function onSubmit(e: Event) {
		e.preventDefault();
		error = '';
		loading = true;
		try {
			await login(loginId.trim(), password);
			toast.success('登录成功');
			goto('/');
		} catch (err) {
			error = err instanceof Error ? err.message : '登录失败';
			toast.error(error);
		} finally {
			loading = false;
		}
	}
</script>

<div class="flex min-h-svh items-center justify-center bg-muted/40 p-4">
	<Card.Root class="w-full max-w-md">
		<Card.Header>
			<Card.Title>管理员登录</Card.Title>
			<Card.Description>
				HmSSH 云端管理 · API <code class="text-xs">{apiBase()}</code>
			</Card.Description>
		</Card.Header>
		<Card.Content>
			<form class="flex flex-col gap-4" onsubmit={onSubmit}>
				<div class="flex flex-col gap-2">
					<Label for="login">邮箱或用户名</Label>
					<Input id="login" autocomplete="username" bind:value={loginId} required />
				</div>
				<div class="flex flex-col gap-2">
					<Label for="password">密码</Label>
					<Input
						id="password"
						type="password"
						autocomplete="current-password"
						bind:value={password}
						required
					/>
				</div>
				{#if error}
					<Alert.Root variant="destructive">
						<Alert.Title>登录失败</Alert.Title>
						<Alert.Description>{error}</Alert.Description>
					</Alert.Root>
				{/if}
				<Button type="submit" disabled={loading} class="w-full">
					{loading ? '登录中…' : '登录'}
				</Button>
			</form>
		</Card.Content>
	</Card.Root>
</div>
