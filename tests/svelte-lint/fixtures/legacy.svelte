<script lang="ts">
	import { writable } from 'svelte/store';

	export let size: number;
	export let label = 'none';
	let clicks = 0;
	let written = writable(0);
	const items = writable<string[]>([]);

	$: doubled = clicks * 2;
	$: if (clicks > 3) {
		console.log('many');
	}
	$: ({ length } = $items);

	function handle() {
		clicks += 1;
		$written = clicks;
	}
</script>

<button on:click={handle} style="width: {size}px">{label} {doubled} {length}</button>
<p>{$$props.extra}</p>
