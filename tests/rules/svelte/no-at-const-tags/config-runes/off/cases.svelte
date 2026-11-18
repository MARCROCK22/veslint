<script lang="ts">
  let count = $state(1);
</script>

{#if count}
  {@const double = count * 2}
  <p>{double}</p>
{/if}
