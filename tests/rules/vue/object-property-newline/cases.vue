<template>
  <div :a="{ a: 1, b: 2 }" />
  <div :a="{
    a: 1, b: 2
  }" />
  <div :a="{
    a: 1,
    b: 2
  }" />
</template>

<script setup lang="ts">
const o = { a: 1, b: 2 }
console.log(o)
</script>
