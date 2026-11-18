<script lang="ts">
  const items: number[] = [1, 2];
</script>

{#each items as item}
  {@const double = item * 2}
  <p>{double}</p>
{/each}
