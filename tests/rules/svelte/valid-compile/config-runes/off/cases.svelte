<script lang="ts">
  export let name: string;
  let count = 0;
  $: doubled = count * 2;
</script>

<button on:click={() => count++}>{name} {doubled}</button>
