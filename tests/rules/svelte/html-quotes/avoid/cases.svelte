<script lang="ts">
	let a = 'x';
	let b = 1;
	const handler = () => {};
</script>

<div title="double"></div>
<div title='single'></div>
<div title=unquoted></div>
<div title='has "double" inside'></div>
<div title="has 'single' inside"></div>
<div title={a}></div>
<div title="{a}"></div>
<div title='{a}'></div>
<div title="pre {a} post"></div>
<div title='pre {a} post'></div>
<div title={a + 'x y'}></div>
<div title="{a + 'x y'}"></div>
<button on:click={handler}>x</button>
<button on:click="{handler}">x</button>
<input bind:value={b} />
<input bind:value />
<div style:color={a}></div>
<div style:color='red'></div>
<svelte:element this={'div'}></svelte:element>
<div {a}></div>
