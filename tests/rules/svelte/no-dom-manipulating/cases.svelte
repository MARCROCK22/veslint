<script lang="ts">
	let div: HTMLDivElement;
	let span: HTMLSpanElement | undefined = $state();
	let other: HTMLElement;
	let comp: unknown;
	let dynamic: HTMLElement;
	const notBound = document.createElement('p');

	function run() {
		div.remove();
		div.appendChild(document.createElement('p'));
		div.textContent = 'x';
		div.innerHTML += 'y';
		div['innerText'] = 'z';
		div[`outerHTML`] = 'w';
		div.className = 'c';
		div.getAttribute('a');
		span?.remove();
		span?.append?.('x');
		other.replaceWith('x');
		dynamic.prepend('x');
		notBound.remove();
		const local = div;
		local.remove();
		div.remove;
		div.insertAdjacentHTML('beforeend', 'x');
		div['in' + 'nerHTML'] = 'v';
	}
	run;
	comp;
</script>

<div bind:this={div}></div>
<span bind:this={span}></span>
<svelte:element this="p" bind:this={dynamic} />
<Foo bind:this={comp} />
<button onclick={() => other.remove()}>remove</button>
{#each [1] as item}
	<b bind:this={other}>{item}</b>
{/each}
