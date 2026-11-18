<script lang="ts" generics="T extends string = 'a', U = number">
  import { writable } from 'svelte/store';
  let { a, b = $bindable(), c = 1 }: { a: T; b?: U; c?: number } = $props();
  const s = writable(1);
  let d = $derived(a.length * 2);
  let n = 0
  $: doubled = n * 2;
  $: console.log($s, $$props, $$restProps, $$slots);
  export const shared = 1;
</script>

<slot name="x" />
<slot />
{doubled}{d}{b}{c}
