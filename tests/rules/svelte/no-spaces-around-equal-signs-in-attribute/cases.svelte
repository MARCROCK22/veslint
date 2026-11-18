<script lang="ts">
	let a = 1;
	const handler = () => {};
</script>

<div title = "x"></div>
<div title= "x"></div>
<div title ="x"></div>
<div title="x"></div>
<div title
	=
	"x"></div>
<div on:click = {handler}></div>
<input bind:value = {a} />
<div style:color = "red"></div>
<svelte:element this = {'div'}></svelte:element>
<div class:active = {a}></div>
<input disabled />
<div title = {a}></div>
