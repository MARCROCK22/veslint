<script lang="ts">
	import { mount } from 'svelte';
	import { noop } from 'svelte/internal';
	import * as internal from 'svelte/internal/client';
	import type { Snippet } from 'svelte/internalx';
	export { flush } from 'svelte/internal';
	export * from 'svelte/internal/server';
	export * as all from 'svelte/internal/disclose-version';
	const lazy = import('svelte/internal');
	const notLiteral = import(`svelte/internal`);
	const fine = import('svelte/store');
	mount;
	noop;
	internal;
	lazy;
	notLiteral;
	fine;
	let snippet: Snippet | undefined;
	snippet;
</script>

<button onclick={() => import('svelte/internal/client')}>load</button>
{#await import('svelte/internal') then mod}{mod}{/await}
