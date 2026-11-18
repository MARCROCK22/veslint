<script lang="ts">
	let { value } = $props();
	let a = $state(0);
	$effect(() => {
		a = value * 2;
	});
	let b = $state(0);
	$effect.pre(function () {
		b = value;
	});
	let c = $state(0);
	$effect(() => {
		c += value;
	});
	let d = $state(0);
	$effect(() => {
		d = value;
		console.log(d);
	});
	let e = 0;
	$effect(() => {
		e = value;
	});
	let f = $state.raw(0);
	$effect(() => {
		f = value;
	});
	let g = $state(0), h = $state(1);
	$effect(() => {
		h = g;
	});
	let i = $state(0);
	$effect(() => i = value);
	let j = $state(0);
	$effect((x?: number) => {
		j = x ?? 0;
	});
	let k = $state(0);
	$effect(() => {
		let k = 1;
		k = value;
	});
</script>

<p>{a}{b}{c}{d}{e}{f}{g}{h}{i}{j}{k}</p>
