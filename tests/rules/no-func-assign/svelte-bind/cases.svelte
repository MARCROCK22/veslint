<script lang="ts">
  // A bind: directive's reference has no `init` (undefined, not false): not a modifying reference.
  function handler(): void {}
</script>

<!-- Not reported: a binding. -->
<input bind:value={handler} />
<!-- Reported: an assignment. -->
<button on:click={() => (handler = (): void => {})}>x</button>
