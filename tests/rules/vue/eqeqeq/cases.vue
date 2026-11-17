<template>
  <p>{{ a == b }}</p>
  <div :a="a != null" />
  <div v-if="typeof a == 'string'" />
  <div @click="if (x == 1) y()" />
  <div :a="a === b" />
</template>

<script setup lang="ts">
const x: unknown = 1
console.log(x == 1)
</script>

<style>
.a {
  width: v-bind("a == b ? '1px' : '2px'");
}
</style>
