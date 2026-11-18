<script lang="ts">
  // A rune's name (here a key) would put the file in runes mode without the config.
  const names = { $state: 1 };
  let count = names.$state;
</script>

{#if count}
  {@const double = count * 2}
  <p>{double}</p>
{/if}
