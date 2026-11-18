<script lang="ts">
	let active = true;
	let n = 1;
	let s = 'a';
</script>

<div class={active ? 'active' : ''}></div>
<div class={active ? '' : 'inactive'}></div>
<div class={active ? 'on' : 'off'}></div>
<div class="a {active ? 'b' : ''}"></div>
<div class="a {active ? 'b' : ''} c"></div>
<div class="a{active ? 'b' : ''}"></div>
<div class="{active ? 'b' : ''}c"></div>
<div class={n === 1 ? 'one' : ''}></div>
<div class={n == 1 ? '' : 'not-one'}></div>
<div class={n !== 1 ? '' : 'one'}></div>
<div class={!active ? '' : 'yes'}></div>
<div class={active && n ? '' : 'no'}></div>
<div class={active ? (n ? 'x' : 'y') : ''}></div>
<div class={active ? s : ''}></div>
<div class={active ? 'a b' : ''}></div>
<div class={active ? ' a ' : ''}></div>
<div class={active ? `t` : ''}></div>
<Comp class={active ? 'a' : ''} />
<svelte:element this={'div'} class={active ? 'a' : ''}></svelte:element>
<div title={active ? 'a' : ''}></div>
<div class="x {active ? 'a' : ''} {n ? 'b' : ''} y"></div>
