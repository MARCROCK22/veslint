<script lang="ts">
	let a = 1;
</script>

<div class="a" title="b"></div>
<div
	class="a" title="b"></div>
<div class="a"
	title="b"></div>
<div
	class="a"
	title="b"
></div>
<input
	bind:value={a} />
<Comp.Child prop={a}
	other={a} />
<svelte:element this={'div'} class="x"></svelte:element>
<div /* not a comment */ class="x"></div>
<div {a}
></div>
