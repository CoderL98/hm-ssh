<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { getToken, getStoredUser } from '$lib/api';
	import AdminShell from '$lib/components/AdminShell.svelte';

	let { children } = $props();
	let ready = $state(false);

	onMount(() => {
		if (!browser) return;
		const token = getToken();
		const user = getStoredUser();
		if (!token || !user?.is_admin) {
			goto('/login');
			return;
		}
		ready = true;
	});
</script>

{#if ready}
	<AdminShell>
		{@render children()}
	</AdminShell>
{:else}
	<div class="flex min-h-svh items-center justify-center text-sm text-muted-foreground">
		加载中…
	</div>
{/if}
