<script lang="ts">
	let { value } = $props();
	// svelte-ignore state_referenced_locally
	const a = value;
	// svelte-ignore state_referenced_locally, a11y_autofocus
	const b = value;
	/* svelte-ignore non_reactive_update */
	let c = 0;
	console.log(a, b, c);
</script>

<!-- svelte-ignore a11y_missing_attribute -->
<img src="x.png" />
<!-- svelte-ignore a11y_missing_attribute a11y-autofocus -->
<div></div>
<!-- svelte-ignore hydration_attribute_changed -->
<p>runtime</p>
<!-- svelte-ignore css_unused_selector -->
<style>
	.nothing {
		color: red;
	}
</style>
