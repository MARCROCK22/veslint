<script lang="ts">
  // No <svelte:options runes>: svelteFeatures.runes, else the svelteConfig (parserOptions'
  // or svelte.config.js, which says false) decides.
  let { label, value = $bindable(0) }: { label: string; value?: number } = $props();
  let count = $state(0);
  const double = $derived(count * 2);
</script>

<p>{label}{value}{double}</p>
<button type="button" onclick={() => count++}>+</button>
