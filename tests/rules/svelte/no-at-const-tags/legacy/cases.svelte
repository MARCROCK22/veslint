<script lang="ts">
	const items = [1];
</script>

{#each items as item}
	{@const double = item * 2}
	<p>{double}</p>
{/each}
