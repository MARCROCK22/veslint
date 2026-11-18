<svelte:options runes={false} />

<script lang="ts">
	let count = 0;
	const a = $derived.by(() => count * 2);
</script>

{a}
