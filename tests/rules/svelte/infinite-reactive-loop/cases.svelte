<script lang="ts">
	import { tick } from 'svelte';
	let a = 0;
	let b = { v: 0 };
	let c = 0;
	let d = 0;
	let e = 0;
	const later = (): Promise<void> => Promise.resolve();
	async function update() {
		await later();
		a += 1;
	}
	function syncUpdate() {
		c = 1;
	}
	const viaArrow = async () => {
		await tick();
		d = 2;
	};
	$: {
		a;
		update();
	}
	$: (async () => {
		b;
		await later();
		b.v = 1;
	})();
	$: {
		c;
		syncUpdate();
	}
	$: {
		d;
		viaArrow();
	}
	$: {
		e;
		setTimeout(() => {
			e = 1;
		});
		later().then(() => {
			e = 2;
		});
		queueMicrotask(() => (e = 3));
		tick().then(() => e = 4);
	}
	$: if (a) {
		e = await later() ? 1 : 0;
	}
	$: c = c + 1;
</script>

<p>{a}{b.v}{c}{d}{e}</p>
