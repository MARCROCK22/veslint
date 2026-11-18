<script lang="ts">
  import Comp from './Comp.svelte';
  import { writable } from 'svelte/store';
  let el: HTMLElement;
  let value = $state('');
  let items = $state([1, 2, 3]);
  const store = writable(0);
  function handle(e: Event) {}
  function act(node: HTMLElement, p: number) {}
</script>

<div><p><b>x</b></div>
<ul><li>a<li>b</ul>
<textarea>{value}&lt;</textarea>
<input title="a &amp b &copy; &#x41;&#65;" bind:value={() => value, (v) => (value = v)} />
<svelte:element this="div" />
<svelte:element this={'span'} class:active={true} />
<Comp.Inner let:item on:click={handle} use:act={1} prop={items} onclick={handle}>
  {item}
  {#snippet row(x, y: number)}<i>{x}{y}</i>{/snippet}
</Comp.Inner>
{#each items, i}{i}{/each}
{#each items as item, i (item)}{(item)}{:else}  empty  {/each}
{#await Promise.resolve(1)}…{:then v}{v}{:catch err}{err}{/await}
{#await store then s}{s}{/await}
{#key value}<span style:color={value} style:width="1px" style:height|important />{/key}
<div bind:this={el} {items} {...{ a: 1 }} // line
  /* block */ class="x">{$store}{@html value}{@debug value, items}</div>
{#if value}a{:else if items}b{:else}c{/if}
{@const z = 1}
