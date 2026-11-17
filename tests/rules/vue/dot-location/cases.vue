<template>
  <div :a="foo
    .bar" />
  <div :a="foo.
    bar" />
  <p>{{ foo
    .baz() }}</p>
  <div @click="obj
    ?.run()" />
</template>

<script setup lang="ts">
const s = "x"
  .trim()
console.log(s)
</script>
