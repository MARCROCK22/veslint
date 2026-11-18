<script lang="ts">
	/* global window, document, location, localStorage, navigator, sessionStorage, history, screen, alert */
	import { browser } from '$app/environment';
	import { BROWSER } from 'esm-env';
	const width: typeof window.innerWidth = window.innerWidth;
	const href = location.href;
	if (browser) {
		document.title = 'x';
	}
	if (!browser) {
		localStorage.getItem('a');
	} else {
		localStorage.setItem('a', 'b');
	}
	if (typeof window !== 'undefined') {
		navigator.userAgent;
	}
	if (typeof window === 'undefined') {
		navigator.language;
	}
	if (globalThis.location !== undefined) {
		globalThis.location.reload();
	}
	const maybe = globalThis.location?.href;
	const both = BROWSER && sessionStorage.length;
	const negated = !import.meta.env.SSR ? history.length : 0;
	function later() {
		return screen.width;
	}
	const arrow = () => alert('x');
	if (!browser) {
		throw new Error('server');
	}
	console.log(width, href, maybe, both, negated, later, arrow);
</script>

{location.pathname}
{#if browser}
	{location.search}
{:else}
	{location.hash}
{/if}
{#snippet s()}
	{location.host}
{/snippet}
{@render s()}
<button onclick={() => location.reload()}>reload</button>
