<script lang="ts">
	export let name: string;
	export let unused: number;
	let n = 1;
	$: total = n * 2;
	function go(): void {
		$: inner = 1;
	}
</script>

<button on:click={() => n++}>{name} {total}</button>
<svelte:component this={null} />
<div class:active={n} className="x" is="custom-x"></div>
