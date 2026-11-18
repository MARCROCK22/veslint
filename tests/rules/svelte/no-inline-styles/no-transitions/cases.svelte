<script lang="ts">
	import { fade } from 'svelte/transition';
	let color = 'red';
</script>

<div style="color: red"></div>
<div style:color={color}></div>
<div style:color></div>
<div transition:fade></div>
<div in:fade out:fade></div>
<Comp style="x" />
<svelte:element this={'div'} style="x"></svelte:element>
<div
	style="a: b"
	style:color="blue"
></div>
<div class="x"></div>
