<script lang="ts">
	import { writable, readable, derived } from 'svelte/store';
	import * as stores from 'svelte/store';
	import { writable as w } from 'svelte/store';

	const a = writable(0, async () => {});
	const b = readable(0, async function () {});
	const c = derived(a, async ($a, set) => set($a));
	const d = stores.writable(0, async () => {});
	const e = w(0, async (set) => {
		set(1);
	});
	const f = writable(0, () => {});
	const g = writable(0, async () => {}, 1);
	const h = derived(a, async function named($a) {
		return $a;
	});
	const i = writable(0);
</script>

<p>{$a} {$b} {$c} {$d} {$e} {$f} {$g} {$h} {$i}</p>
