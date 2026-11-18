<script lang="ts">
	import Child from './Child.svelte';
	interface Props {
		label: string;
		count?: number;
	}
	let { label, count = 0 }: Props = $props();
	let doubled = $derived(count * 2);
	let local = 0;
	console.log(label);
	function bump(): void {
		local += 1;
	}
	// svelte-ignore state_referenced_locally
	const copy = count;
	class Box {
		value = $state(0);
	}
	const box = new Box();
</script>

<img src="x.png" />
<!-- svelte-ignore a11y_missing_attribute -->
<img src="y.png" />
<div onclick={bump}>{local} {doubled} {copy} {box.value}</div>
<a href="#">link</a>
<span />
<input autofocus />
<div role="buton" aria-hiden="true"></div>
<label>Name</label>
<button></button>
<marquee>old</marquee>
{#if count}
	
{/if}
<Child {label} />
<p>bidi ‮ text</p>
