<script lang="ts">
	let count = $state(0);
	let doubled = $derived(count * 2);
	let { a, b } = $props();
	let [x, y] = [1, 2];
	y = 3;
</script>

<p>{count} {doubled} {a} {b} {x} {y}</p>
