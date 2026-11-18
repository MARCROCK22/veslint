<template>
  <div :a="(x)=>x" />
  <div :a="(x) => x" />
  <div :a="(x)=> x" />
</template>

<script setup lang="ts">
const g = (a: number) => a
console.log(g)
</script>
