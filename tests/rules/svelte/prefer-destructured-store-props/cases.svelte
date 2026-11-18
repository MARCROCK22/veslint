<script lang="ts">
	import { writable } from 'svelte/store';
	const foo = writable({ bar: 1, baz: 2, name: 'n', class: 'c', $x: 3, items: [1] });
	const key = 'bar';
	$: reactiveBar = $foo.bar;
	$: ({ baz: reactiveBaz } = $foo);
	let bar1 = 0;
	$foo.bar;
</script>

<script lang="ts" module>
	export const moduleLevel = 1;
</script>

<p>{$foo.bar}</p>
<p>{$foo.baz}</p>
<p>{$foo['bar']}</p>
<p>{$foo[key]}</p>
<p>{$foo[ key  ]}</p>
<p>{$foo.name}</p>
<p>{$foo.class}</p>
<p>{$foo.$x}</p>
<p>{$foo.bar.toFixed(1)}</p>
{#each $foo.items as item}
	<p>{$foo.items[item]}</p>
{/each}
<p>{$$props.x}</p>
<p>{reactiveBar}{reactiveBaz}{bar1}</p>
