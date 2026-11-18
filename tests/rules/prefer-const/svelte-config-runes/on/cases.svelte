<script lang="ts">
  // Runes mode comes from svelte.config.js here (no <svelte:options runes>): when it is off,
  // svelte-eslint-parser declares no rune in the code typescript-eslint parses ($state and the
  // others are unresolved, error-typed calls) and the props $props() destructures are plain
  // variables of the scope.
  let { label, value = $bindable(0) }: { label: string; value?: number } = $props();
  let count = $state(0);
  const double = $derived(count * 2);
  const copy: number = count;
</script>

<p>{label}{value}{double}{copy}</p>
<button type="button" onclick={() => count++}>+</button>
