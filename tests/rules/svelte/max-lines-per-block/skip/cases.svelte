<svelte:options immutable />
<script lang="ts">
	// a comment
	let a = 1;

	/* block
	   comment */
	let b = 2;
</script>

<!-- html comment -->
<div>{a}</div>
<p>{b}</p>

<style>
	/* css */
	div { color: red; }

	p { color: blue; } /* trailing */
</style>
{#if true}
	<!-- c -->
	<b>x</b> <!-- d -->
{/if}
