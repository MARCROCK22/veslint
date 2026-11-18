<script context="module" lang="ts">
	export const shared = { counter: 0 };
	var old = 1;
</script>

<script lang="ts">
	const local = shared.counter + old;
	const other = local;
</script>

<p>{local} {other}</p>
