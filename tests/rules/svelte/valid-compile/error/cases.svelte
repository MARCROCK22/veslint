<script lang="ts">
	let { a } = $props();
	let b = $state();
	b = $state(1);
</script>

<p>{a}{b}</p>
