<template>
  <p>{{ msg }}</p>
</template>
<script lang="ts">
function later(): Promise<number> { return Promise.resolve(1); }
const msg = "hello"   
later()
export default { data() { return { msg } } }
</script>
