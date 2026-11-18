<template>
  <div   class="foo"    :style="bar"  >
    <span  v-if="a  &&  b" />
    {{ count   +   1 }}
    <i   />   <!-- comment -->
  </div>
</template>
<script  setup   lang="ts">
const a = 1
const b = 2
const count = 3
</script>
<style   scoped>
</style  >
