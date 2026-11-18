<script lang="ts">
	import { writable } from "svelte/store";

	interface Props {
		"title": string;
		"count"?: number;
		"items": string[];
	}
	let { title, count = $bindable(0), items }: Props = $props();
	const doubled = $derived(count * 2);
	const total = $derived.by<number>(() => items.length + doubled);
	let name = $state("world");
	const unused = $state(1);
	const store = writable(0);

	$effect(() => {
		console.log(title,
total);
	});

	function onClick (event: MouseEvent): void {
		count += 1;
		$store += 1;
		console.log(event.button == 0);
	}

	async function load () {
		return { status: 200 };
	}
</script>

<h1 class:big={count > 10}>Hello {name}!</h1>
<input bind:value={name} />
<button on:click={onClick} disabled={items.length === 0}>{$store}</button>
{#each items as item, index (item)}
	{@const label = `${index}: ${item}`}
	<p>{label} {item.toUpperCase()}</p>
{:else}
	<p>none</p>
{/each}
{#if count > 1 && count < 5}
	<span>{count}</span>
{:else if count == 5}
	<span>five</span>
{/if}
{#await load()}
	<p>loading</p>
{:then response}
	<p>{response.status}</p>
{:catch error}
	<p>{error}</p>
{/await}
{#snippet row(label: string, value: number)}
	<td>{label}</td><td>{value}</td>
{/snippet}
{@render row("a",
1)}
