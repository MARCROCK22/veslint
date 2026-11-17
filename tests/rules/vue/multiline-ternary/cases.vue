<template>
  <p>{{ a ? b : c }}</p>
  <div :a="a
    ? b : c" />
  <div :a="a
    ? b
    : c" />
</template>

<script setup lang="ts">
const v = Math.random() ? 1 : 2
console.log(v)
</script>

<style>
.a {
  width: v-bind("a ? b : c");
}
</style>
