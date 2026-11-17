<template>
  <p>{{ [1, 2] }}</p>
  <div :a="[
    1,
    2
  ]" />
  <div :a="[1,
    2, 3]" />
  <div :a="[a, , b]" />
</template>

<script setup lang="ts">
const list = [1, 2]
console.log(list)
</script>
