<script lang="ts">
	let a = true;
	let b = false;
	let c = 1;
</script>

{#if a}
	<p>a</p>
{:else if a}
	<p>dupe</p>
{/if}
{#if a || b}
	<p>a or b</p>
{:else if b}
	<p>covered</p>
{:else if a && c}
	<p>covered too</p>
{:else if c > 1}
	<p>fine</p>
{:else if c>1}
	<p>same tokens</p>
{/if}
{#if a && b}
	<p>x</p>
{:else if b && a}
	<p>commuted</p>
{/if}
{#if a}
	<p>x</p>
{:else}
	{#if a}
		<p>nested if, not a chain</p>
	{/if}
{/if}
{#if a && b}
	<p>x</p>
{:else if a && b && c}
	<p>subset</p>
{/if}
