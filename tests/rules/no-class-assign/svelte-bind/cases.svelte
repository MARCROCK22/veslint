<script lang="ts">
  // A bind: directive's reference has no `init` (undefined, not false): not a modifying reference.
  class Klass {}
</script>

<!-- Not reported: a binding. -->
<input bind:value={Klass} />
<!-- Reported: an assignment. -->
<button on:click={() => (Klass = class {})}>x</button>
