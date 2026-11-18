<script lang="ts">
	// What returns before a type is looked at. The other paths need the `typescript` package
	// eslint-plugin-svelte loads from the current directory to be TypeScript 5 or 6, which it is
	// not here (TypeScript 7): the upstream cases cover them (tests/rules/svelte/no-unused-props/upstream.ts.json).
	class Model {
		value = 1;
		unused = 2;
	}
	interface Props {
		a: string;
		b: number;
	}
	let { a, ...others }: Props = $props();
	let whole: Props = $props();
	let { value }: Model = $props();
	let untyped = $props();
	const { [`a`]: computed }: Props = $props();
	console.log(a, others, whole, value, untyped, computed);
</script>
