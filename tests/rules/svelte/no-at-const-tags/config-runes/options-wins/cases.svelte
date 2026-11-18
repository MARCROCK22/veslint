<svelte:options runes={true} />

<script lang="ts">
  const items: string[] = ['a'];
</script>

{#each items as item}
  {@const upper = item.toUpperCase()}
  <p>{upper}</p>
{/each}
