<template>
  <div :a="a
    + b" />
  <div :a="a +
    b" />
  <div :a="cond
    ? x
    : y" />
  <div :a="cond ?
    x :
    y" />
  <div @click="x
    = 1" />
  <div :a="a
    &&
    b" />
</template>

<script setup lang="ts">
const v = 1 +
  2
console.log(v)
</script>
