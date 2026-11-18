<svelte:options runes />

<script lang="ts">
	let a = 0;
	let f: () => number;
	$: {
		a = 1;
	}
	$: a = 2;
	$: f = () => a;
</script>

<p>{a} {f}</p>
