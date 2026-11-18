<script lang="TS">
	// `lang="TS"` is TypeScript for svelte-eslint-parser with typescript-eslint's parser object.
	let count = 0;
	const label = "count" as string;
</script>

<button on:click={() => count++}>{label}: {count}</button>
