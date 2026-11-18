<script lang="ts">
	import { writable, readable, derived } from 'svelte/store';
	import { writable as w } from 'svelte/store';
	import * as stores from 'svelte/store';

	const args: [number] = [1];
	const a = writable();
	const b = readable();
	const c = derived(a, ($a) => $a);
	const d = derived(a, ($a, set) => set($a), 0);
	const e = writable(...args);
	const f = w();
	const g = stores.readable();
	const h = writable(0);
	const i = derived(a);
</script>

<p>{$a} {$b} {$c} {$d} {$e} {$f} {$g} {$h} {$i}</p>
