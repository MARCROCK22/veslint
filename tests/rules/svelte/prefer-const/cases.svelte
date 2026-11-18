<script lang="ts">
	let { a, b } = $props();
	let count = $state(0);
	let doubled = $derived(count * 2);
	let tripled = $derived.by(() => count * 3);
	let raw = $state.raw([1]);
	let plain = 1;
	let other = 2, viaProps = $props();
	let wrapped = ($derived(count));
	let optional = $derived?.by(() => 1);
	let reassigned = 1;
	reassigned = 2;
	let { c } = $props(), d = 1;
	for (let i of [1]) {
		i;
	}
</script>

<p>{a} {b} {count} {doubled} {tripled} {raw} {plain} {other} {viaProps} {wrapped} {optional} {reassigned} {c} {d}</p>
