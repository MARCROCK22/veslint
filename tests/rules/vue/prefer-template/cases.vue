<template>
  <p>{{ 'Hello, ' + name + '!' }}</p>
  <div :a="'x' + y" />
  <div :a="a + b" />
  <div @click="msg = 'n: ' + n" />
</template>

<script setup lang="ts">
const n = 1
console.log('n: ' + n)
</script>

<style>
.a {
  content: v-bind("'a' + b");
}
</style>
