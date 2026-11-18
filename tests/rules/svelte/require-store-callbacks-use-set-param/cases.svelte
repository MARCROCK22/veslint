<script lang="ts">
	import { readable, writable, derived } from 'svelte/store';
	import * as stores from 'svelte/store';

	const a = readable(0, () => {});
	const b = writable(0, (update) => {
		update(1);
		return () => update(0);
	});
	const c = readable(0, function (s: (v: number) => void) {
		s(1);
	});
	const d = writable(0, (set) => set(1));
	const e = readable(0, ({ set }: { set: (v: number) => void }) => set(1));
	const f = readable(0, (x) => {
		const set = 1;
		x(set);
	});
	const g = readable(0, () => {
		set;
	});
	const h = stores.writable(0, async /* c */ () => {});
	const i = derived(a, (v) => v);
	const j = readable(0, (_) => {});
	const k = writable(0, function named () {});
	declare const set: unknown;
</script>

<p>{$a} {$b} {$c} {$d} {$e} {$f} {$g} {$h} {$i} {$j} {$k}</p>
