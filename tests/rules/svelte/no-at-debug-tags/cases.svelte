<script lang="ts">
	const a = 1;
	const b = { c: 2 };
</script>

{@debug}
{@debug a}
{@debug a, b}
<div>{@debug b}</div>
{#each [a] as item}
	{@debug item}
{/each}
<p>{a}</p>
