<script lang="ts">
	let x = 1;
</script>

<div class="a">{x}</div>

<style lang="postcss">
	.a { color: red; }
	@media (min-width: 1px) { .a { color: blue } }
</style>
