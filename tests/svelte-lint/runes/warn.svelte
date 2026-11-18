<script lang="ts">
  // No rune: the compiler is in runes mode only when the svelteConfig says so, and then warns that
  // count is updated but not declared with $state (svelte/valid-compile).
  let count = 0;
</script>

<button type="button" onclick={() => count++}>{count}</button>
