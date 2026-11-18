<script lang="ts">
	let active = true;
	let name = 'x';
	const prefix = 'pre-' + name;
	let items = [1, 2];
</script>

<div class="single"></div>
<span class="twice"></span>
<span class="twice"></span>
<p id="only">a</p>
<p id="other">b</p>
<b class:active>x</b>
<i class="dyn-{name}"></i>
<i class={prefix}></i>
{#each items as item (item)}
	<em class="repeated">{item}</em>
{/each}
{#if active}
	<strong class="maybe">x</strong>
{/if}
<section class="s1"><h1 class="h">t</h1></section>
<Comp class="comp" />
<u class="x  y"></u>
<a id={`link-${name}`} href="/">x</a>

<style>
	.single { color: red; }
	.twice { color: red; }
	#only { color: red; }
	p { color: red; }
	.active { color: red; }
	.dyn-a { color: red; }
	.pre-x { color: red; }
	.repeated { color: red; }
	em { color: red; }
	.maybe { color: red; }
	strong { color: red; }
	h1, .h { color: red; }
	section > .h, .s1 .h:hover { color: red; }
	:global(.single) { color: red; }
	:global(div) .single { color: red; }
	.x.y { color: red; }
	#link-a { color: red; }
	@media (min-width: 1px) {
		.single { color: blue; }
	}
	.missing { color: red; }
	#missing { color: red; }
	table { color: red; }
	.single,
	.twice
	{ color: red; }
</style>
