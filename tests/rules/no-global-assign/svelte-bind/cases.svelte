<script lang="ts">
  // A bind: directive's reference has no `init` (undefined, not false): no-global-assign asks
  // `reference.init === false`.
</script>

<!-- Not reported: bindings. -->
<input bind:value={NaN} />
<input bind:value={undefined} />
<!-- Reported: an assignment. -->
<button on:click={() => (NaN = 1)}>x</button>
