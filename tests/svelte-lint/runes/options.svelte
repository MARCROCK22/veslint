<svelte:options runes={true} />

<script lang="ts">
  // <svelte:options runes> wins over the svelteConfig, not over svelteFeatures.runes.
  let { label, value = $bindable(0) }: { label: string; value?: number } = $props();
  let count = $state(0);
  const double = $derived(count * 2);
</script>

<p>{label}{value}{double}</p>
<button type="button" onclick={() => count++}>+</button>
