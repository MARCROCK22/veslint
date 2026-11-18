<script lang="ts">
	let a = 1;
	const items = [1, 2];
	const p = Promise.resolve(1);
	const handler = () => {};
	let value = '';
</script>

<p>{a}</p>
<p>{ a }</p>
<p>{ a}</p>
<p>{a }</p>
<p>{/* c */a}</p>
<p>{a/* c */ }</p>
<div title={a}></div>
<div title="{ a }"></div>
<div {a}></div>
<div { a }></div>
<div {...{ a }}></div>
<div { ...{ a } }></div>
<button on:click={ handler }>x</button>
<input bind:value={ value } />
<div style:color={ value }></div>
{@html a}
{ @html a }
{@debug a}
{ @debug a }
{#if a}x{:else if a}y{:else}z{/if}
{ #if a }x{ :else if a }y{ :else }z{ /if }
{#each items as item, i (item)}{item}{i}{/each}
{ #each items as item }{item}{ /each }
{#key a}x{/key}
{ #key a }x{ /key }
{#await p}w{:then v}{v}{:catch e}{e}{/await}
{ #await p }w{ :then v }{v}{ :catch e }{e}{ /await }
{#await p then v}{v}{/await}
{ #await p then }x{ /await }
{#snippet s(x: number)}{x}{/snippet}
{ #snippet t() }y{ /snippet }
{@render s(1)}
{ @render s(2) }
{@const c = a}
