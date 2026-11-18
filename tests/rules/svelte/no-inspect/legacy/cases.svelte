<svelte:options runes={false} />

<script lang="ts">
	let count = 0;
	$inspect(count);
</script>

<p>{count}</p>
