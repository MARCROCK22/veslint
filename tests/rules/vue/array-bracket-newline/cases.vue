<template>
  <p>{{ [
    1, 2] }}</p>
  <div :a="[1,
    2]" />
  <div :a="[
    1
  ]" />
  <div :a="[1, 2]" />
  <div :[[x]]="y" />
</template>

<script setup lang="ts">
const list = [
  1, 2]
console.log(list)
</script>
