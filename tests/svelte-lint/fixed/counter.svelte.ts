
// A Svelte module: runes are globals, and typescript-eslint type-checks them through the
// declarations svelte-eslint-parser adds.
export function createCounter (initial: number) {
	let count = $state(initial);
	const doubled = $derived(count * 2);
	const unused = $state("x");
	$effect(() => {
		console.log(count == 0,
doubled);
	});
	return {
		get "count" () {
			return count;
		},
		"increment": () => count++
	};
}
