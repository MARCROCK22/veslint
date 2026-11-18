<script lang="ts">
  import { onMount } from 'svelte';
  import type {
      Snippet,
    Component
  } from 'svelte';

  interface Props {
      name: string;
    items: string[];
    render?: Snippet<[string]>;
  }

  let { name, items, render }: Props = $props();
  let count = $state(0);
	let tabbed = 1;
    const doubled = $derived(count *
  2);

  class Counter<T extends object> implements Iterable<T> {
    #value = 0;
      static readonly max: number = 10;
    constructor(private readonly start: number) {
      this.#value = start;
    }
    *[Symbol.iterator](): Iterator<T> {
        yield* [];
    }
  }

  function handle(event: MouseEvent,
      other: string): void {
    switch (event.button) {
      case 0:
        count += 1;
        break;
        case 1: {
        count -= 1;
      }
      default:
          count = 0;
    }
    const value = event.button > 0
      ? 'right'
        : 'left';
    if (value) {
      // comment
        console.log(value, other);
    } else
      console.log(
        value
          .toUpperCase()
      );
    for (const item of items) {
      console.log(item);
      }
    // trailing comment
  }

  onMount(async () => {
    const result = await fetch('/api')
      .then((r) => r.json())
        .catch(() => null);
    return () => {
       console.log(result);
    };
  });
</script>

<svelte:head>
    <title>{name}</title>
</svelte:head>

<!-- a comment -->
<div
  class="wrapper {name}"
    id="main"
  on:click={(e) =>
    handle(e, 'x')}
>
  <p>
    Hello {name}!
      Some text
  </p>
    <span>{count}</span>
  {#if count > 10}
    <strong>big</strong>
  {:else if count > 5}
      <em>medium</em>
  {:else}
    small
  {/if}
  {#each items as item, i (item)}
    <li>{i}: {item}</li>
      {:else}
    <li>none</li>
  {/each}
  {#await fetch('/x')}
    loading
  {:then res}
      {res.status}
  {:catch err}
    {err}
  {/await}
  {#await fetch('/y') then data}
    {data}
  {/await}
  {#key count}
      <i>{count}</i>
  {/key}
  {#snippet row(
      text: string,
    n: number
  )}
    <b>{text}{n}</b>
  {/snippet}
  {@render row('a', 1)}
  {@html '<b>x</b>'}
    {@debug count}
  <input
    bind:value={name}
    disabled
  />
  <button
      type="button"
    onclick={() => {
      count++;
        }}
  >
    +
  </button>
  <pre>
      keep
  this
  </pre>
  <textarea>
      keep
  </textarea>
  {#each items as item}
    {@const upper = item
      .toUpperCase()}
    {upper}
  {/each}
  <Component
    {...{ a: 1 }}
      {name}
  />
</div>

<style>
  .wrapper {
      color: red;
  }
</style>
