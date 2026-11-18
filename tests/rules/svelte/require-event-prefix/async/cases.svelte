<script lang="ts">
	interface Props {
		load: () => Promise<void>;
		fetchIt: () => Promise<string>;
		maybe: () => void | Promise<void>;
		then: () => PromiseLike<undefined>;
	}
	let { load, fetchIt, maybe, then }: Props = $props();
</script>

<button onclick={load}>x</button>
