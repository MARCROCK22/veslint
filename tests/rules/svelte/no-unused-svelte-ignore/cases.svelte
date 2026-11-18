<script lang="ts">
	// svelte-ignore 
	let a = 1;
	/* svelte-ignore (a note) */
	let b = 2;
	// svelte-ignore
	let c = 3;
</script>

<!-- svelte-ignore -->
<div>{a}{b}{c}</div>
<!-- svelte-ignore (only a note) -->
<p>x</p>
<!-- svelte-ignore a11y_missing_attribute -->
<img src="x.png" />
<!--svelte-ignore    -->
<span>y</span>
<!-- not an ignore -->
