<script lang="ts">
	import Comp from './Comp.svelte';
</script>

<Comp>
	{#snippet children()}
		<p>x</p>
	{/snippet}
</Comp>
<Comp>
	{#snippet children(arg: string)}
		<p>{arg}</p>
	{/snippet}
</Comp>
<Comp>
	{#snippet other()}
		<p>y</p>
	{/snippet}
</Comp>
<div>
	{#snippet children()}<i>z</i>{/snippet}
</div>
{#if true}
	{#snippet children()}<b>in if</b>{/snippet}
{/if}
