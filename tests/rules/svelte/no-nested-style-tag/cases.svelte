<script lang="ts">
	const a = 1;
</script>

<div>
	<style>
		div { color: red; }
	</style>
</div>
{#if a}
	<style>p { color: blue; }</style>
{/if}
<svelte:head>
	<style>body { margin: 0; }</style>
</svelte:head>

<style>
	div { color: green; }
</style>
