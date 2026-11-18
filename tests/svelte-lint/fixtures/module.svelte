<script context="module" lang="ts">
	export const shared = { counter: 0 };
	var old = 1;
</script>

<script lang="ts">
	let local = shared.counter + old;
	let other = local
</script>

<p>{local} {other}</p>
