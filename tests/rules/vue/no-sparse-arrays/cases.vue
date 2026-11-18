<template>
  <p>{{ [1,,2] }}</p>
  <div :a="[,]" />
  <div :a="[a, , b, ,]" />
  <div @click="const [, x] = $event" />
  <div :a="[1, 2]" />
</template>

<script setup lang="ts">
const arr = [1,,2]
console.log(arr)
</script>
