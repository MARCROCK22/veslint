<script lang="ts" generics="T">
	type Nothing = void;
	interface Props {
		select: (item: T) => void;
		pick: () => Nothing;
		get: () => T;
		maybe: () => (void | undefined);
		later: () => Promise<void>;
		nul: () => null;
	}
	let { select, pick, get, maybe, later, nul }: Props = $props();
</script>

<button onclick={() => select(get())}>x</button>
