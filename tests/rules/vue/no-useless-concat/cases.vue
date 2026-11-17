<template>
  <p>{{ 'a' + 'b' }}</p>
  <div :a="`x` + 'y'" />
  <div :a="'a' + b + 'c'" />
  <div :a="'a' +
    'b'" />
</template>

<script setup lang="ts">
const s = 'a' + 'b'
console.log(s)
</script>

<style>
.a {
  content: v-bind("'a' + 'b'");
}
</style>
