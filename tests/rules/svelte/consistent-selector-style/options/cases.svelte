<script lang="ts">
	let x = 1;
</script>

<div class="single">{x}</div>
<p id="only">a</p>
<span class="twice"></span>
<span class="twice"></span>

<style>
	.single { color: red; }
	#only { color: red; }
	p { color: red; }
	span { color: red; }
	:global(.single) { color: red; }
	:global(#only) { color: red; }
	:global { .single { color: red; } }
</style>
