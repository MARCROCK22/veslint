<script lang="ts">
	let active = true;
</script>

<div class="used unused"></div>
<div class:active class:other={active}></div>
<div class="  spaced   out "></div>
<div class=""></div>
<div class="global-one"></div>
<Comp class="comp" />
<div
	class="multi
	line"
></div>

<style>
	.used { color: red; }
	.active { color: red; }
	:global(.global-one) { color: red; }
	@media (min-width: 1px) { .spaced { color: red; } }
	.multi { color: red; }
</style>
