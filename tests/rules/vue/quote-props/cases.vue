<template>
  <div :style="{height: '100vh'}" />
  <div :style='{height: "100vh"}' />
  <p>{{ { a: 1, 'b': 2 } }}</p>
  <div :a="{ [c]: 1 }" />
</template>

<script setup lang="ts">
const o = { a: 1 }
console.log(o)
</script>
