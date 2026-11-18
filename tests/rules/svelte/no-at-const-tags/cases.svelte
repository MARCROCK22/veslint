<script lang="ts">
	let { items = [1, 2] }: { items?: number[] } = $props();
</script>

{#each items as item}
	{@const double = item * 2}
	{@const derived = $derived(item * 3)}
	{ @const spaced = item}
	<p>{double}{derived}{spaced}</p>
{/each}
