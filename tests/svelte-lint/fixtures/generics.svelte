<script lang="ts" generics="T extends { id: string }, U = number">
	let { rows, pick }: { rows: T[]; pick: (row: T) => U } = $props();
	let selected: T | undefined = $state();
</script>

{#each rows as row (row.id)}
	<button on:click={() => (selected = row)}>{pick(row)}</button>
{/each}
{#if selected !== undefined}{selected.id}{/if}
