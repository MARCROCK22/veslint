<script lang="ts">
	let el: HTMLElement;
	let props = {};
	let v = '';
	let active = true;
	function act(_: HTMLElement) {}
	function f() {}
</script>

<div class="a" id="b"></div>
<div bind:this={el} id="x" name="n"></div>
<div style="color: red" style:top="0" class="c" --b="1" --a="2"></div>
<input on:input={f} bind:value={v} type="text" placeholder="p" />
<div class:b={active} class:a={active} use:act></div>
<div class="a" {...props} id="b"></div>
<div id="b" title="t" {...props} class="a" alt="x"></div>
<div data-z="1" data-a="2" aria-label="l"></div>
<div
	title="t"
	id="i"
	class="c"
></div>
<Comp b="1" a="2" id="i" />
<div use:act id="x"></div>
<div on:click={f} bind:this={el}></div>
