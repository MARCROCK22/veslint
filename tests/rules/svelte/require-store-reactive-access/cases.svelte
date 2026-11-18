<script lang="ts" module>
	import { writable as w } from 'svelte/store';
	export const moduleStore = w(0);
	moduleStore + 1;
</script>

<script lang="ts">
	import { writable, readable, derived, type Readable } from 'svelte/store';
	import { getContext } from 'svelte';
	import Child from './Child.svelte';
	const count = writable(0);
	const ro = readable('x');
	const both = derived(count, (c) => c * 2);
	const maybe: Readable<number> | undefined = undefined;
	const fromContext = getContext<Readable<number>>('k') ?? readable(1);
	let ctx = getContext<Readable<number>>('c');
	ctx ??= readable(0);
	const text = `${count}`;
	if (count) {
	}
	const sum = count + 1;
	const neg = !ro;
	const eq = count === ro;
	const and = both && 1;
	for (const x of count as unknown as number[]) {
	}
	const spread = [...(ro as unknown as string[])];
	const call = (count as unknown as () => void)();
	const key = { [count as unknown as string]: 1 };
	async function load() {
		await ro;
	}
	switch (both) {
	}
	maybe;
	load;
	text;
	sum;
	neg;
	eq;
	and;
	spread;
	call;
	key;
	fromContext;
	let el: HTMLElement;
</script>

<p>{count}</p>
<p>{$count}</p>
<div title={ro}></div>
<div title="a {ro}"></div>
<Child value={count} />
<Child {count} />
<input bind:value={count} />
<div class:active={count}></div>
<div style:color={ro}></div>
<div bind:this={el}></div>
{#if count}a{/if}
{#each both as item}{item}{/each}
{#await ro}x{/await}
<button onclick={count}>x</button>
<div {...count}></div>
<svelte:element this={ro}></svelte:element>
