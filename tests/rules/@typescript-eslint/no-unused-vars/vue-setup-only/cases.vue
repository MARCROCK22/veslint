<script setup lang="ts">
// Alone, the same statements are in the module scope, and their scopes in the tree.
const bar = (e?: unknown) => {}
function baz(...a: number[]) {}
if (bar) {
  const inner = 1
}
class K {
  m(p: number) {}
}
const unused = 1
</script>
<template>
  <div @click="bar(); baz()">{{ K }}</div>
</template>
