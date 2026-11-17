<template>
  <p>{{ [a, b,] }}</p>
  <div :a="{ x: 1, y: 2, }" />
  <div :a="[
    1,
    2,
  ]" />
  <div @click="fn(a, b,)" />
  <div :a="{ x: 1 }" />
</template>

<script setup lang="ts">
const list = [1, 2,]
console.log(list)
</script>
