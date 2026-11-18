<template>
  <div title="a b">x y<!-- c d -->{{ "s t" }}</div>
</template>
<script lang="ts">
const a = "x y"; // c 
/* d  */
export default { a };
</script>
<style>a {}</style>
 
