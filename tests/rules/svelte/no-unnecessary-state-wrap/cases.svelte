<script lang="ts">
	import { SvelteSet, SvelteMap, SvelteURL, MediaQuery } from 'svelte/reactivity';
	import { SvelteDate as D } from 'svelte/reactivity';
	import * as reactivity from 'svelte/reactivity';

	class Custom {}
	const a = $state(new SvelteSet<number>());
	let b = $state(new SvelteMap());
	const c = $state(new SvelteURL('https://example.com'));
	const d = $state(new D());
	const e = $state(new reactivity.SvelteURLSearchParams());
	const f = $state(new MediaQuery('(min-width: 1px)'));
	const g = $state(new Custom());
	const h = new SvelteSet();
	const { i } = $state({ i: new SvelteSet() });
	const j = $state.raw(new SvelteSet());
	const k = $state(SvelteSet as unknown);
	b = new SvelteMap();
	let l = $state(new Custom());
	l = new Custom();
</script>

<p>{a}{b}{c}{d}{e}{f}{g}{h}{i}{j}{k}{l}</p>
