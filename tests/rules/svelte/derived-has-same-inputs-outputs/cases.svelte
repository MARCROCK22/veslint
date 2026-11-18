<script lang="ts">
	import { writable, derived } from 'svelte/store';
	import * as stores from 'svelte/store';

	const a = writable(0);
	const b = writable(1);
	const c = derived(a, (x) => x * 2);
	const d = derived(a, ($a) => $a);
	const e = derived([a, b], ([x, $b]) => x + $b);
	const f = derived([a, b], ([$a, y], set) => set($a + y));
	const g = derived(a, (value: number) => {
		const $a = value;
		return $a;
	});
	const h = derived([a, , b], ([one, two, three]) => one + two + three);
	const i = stores.derived(a, function (v) {
		return v;
	});
	const j = derived(a, ({ length }) => length);
	const k = derived(a, (v) => $a);
	const l = derived([a, b], (both) => both);
	const m = derived(a, (n) => n, 0);
</script>

<p>{$c} {$d} {$e} {$f} {$g} {$h} {$i} {$j} {$k} {$l} {$m}</p>
