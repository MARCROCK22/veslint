<script module lang="ts">
  export const top = 1;
</script>

<script lang="ts">
  export let legacy: string;
  export let inferred = 'x';
  let count = 0
</script>

<svelte:options runes={false} />
<button on:click={() => count++}>{count}{legacy}{inferred}{top}</button>
