<template>
  <p>{{ { a: 1 } }}</p>
  <div :a="{ b }" />
  <div @click="const { x } = $event" />
  <div :[{a:1}]="x" />
</template>

<script setup lang="ts">
const o = { a: 1 }
console.log(o)
</script>
