<template>
  <p>{{ msg }}</p>
</template>

<script lang="ts">
async function later (): Promise<number> {
  return 1;
}
const msg = "hello";
later();
export default {data () {
  return {msg};
}};
</script>
