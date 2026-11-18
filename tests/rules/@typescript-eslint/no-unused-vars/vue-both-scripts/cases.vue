<script lang="ts">
export default { name: 'A' }
</script>
<script setup lang="ts">
// With another <script>, vue-eslint-parser parses the setup statements in a block whose scope it
// takes out of the tree (remapScope): the variables of the scopes inside it are not collected.
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
