<script lang="ts">
	import { imported } from './data';
	import { writable } from 'svelte/store';
	export let prop = 1;
	const constant = 1;
	const fn = () => 1;
	const object = { a: 1 };
	let neverWritten = 2;
	let written = 3;
	let member = { a: 1 };
	let bound = '';
	let eachList = [{ v: 1 }];
	let eachUntouched = [{ v: 1 }];
	const store = writable(0);
	$: a = constant * 2;
	$: b = fn();
	$: c = imported;
	$: d = object.a;
	$: e = neverWritten;
	$: f = written;
	$: g = member.a;
	$: h = prop;
	$: i = $store;
	$: j = unknownGlobal;
	$: k = Math.max(constant, 1);
	$: l = bound;
	$: m = eachList;
	$: n = eachUntouched;
	$: o = $$props;
	$: console.log(constant);
	$: {
		const local = constant;
		local;
	}
	$: p = a;
	function update() {
		written = 4;
		member.a = 2;
	}
	update;
</script>

<input bind:value={bound} />
{#each eachList as item}
	<input bind:value={item.v} />
{/each}
{#each eachUntouched as item}
	{item.v}
{/each}
<p>{b}{c}{d}{e}{f}{g}{h}{i}{j}{k}{l}{m}{n}{o}{p}</p>
