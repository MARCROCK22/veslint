<script lang="ts">
  import { onMount } from 'svelte';
  let count = $state(0);
    const doubled = $derived(count *
  2);
  function handle(event: MouseEvent,
      other: string): void {
    if (event.button) {
        count += 1;
    }
      // a comment
    onMount(() => {
      count = 0;
    });
  }
  const items = [
      1,
    2,
  ];
</script>

<div class="a">
  {#each items as item}
    <span>{item}</span>
  {/each}
    <button onclick={(e) => handle(e, 'x')}>
      {count +
        doubled}
  </button>
  {#if count > 1}
    <p>{count
    }</p>
  {/if}
</div>

<style>
  div {
      color: red;
  }
</style>
