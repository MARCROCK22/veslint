<script lang="ts">
  // A bind: directive reads and writes the name, but svelte-eslint-parser's reference of it has
  // no `init` (undefined, not false): getModifyingReferences does not take it.
  const name = 'a';
  const obj = { a: 'b' };
  const list = ['c'];
</script>

<!-- Not reported: bindings. -->
<input bind:value={name} />
<input bind:value={obj.a} />
<input bind:value={list[0]} />
<!-- Reported: an assignment. -->
<input bind:value={name} on:input={() => (name = 'b')} />
<button on:click={() => name++}>{name}</button>
