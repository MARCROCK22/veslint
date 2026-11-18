<template>
  <p>{{ a+b }}</p>
  <div :a="a||b" />
  <div @click="x=1" />
  <div :a="c?d:e" />
  <div :[a+b]="x" />
</template>

<script setup lang="ts">
const s = 1+2
console.log(s)
</script>

<style>
.a {
  width: v-bind("a+b");
}
</style>
