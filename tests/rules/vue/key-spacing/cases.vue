<template>
  <div :a="{a:1, b :2}" />
  <p>{{ { x :1 } }}</p>
  <div :a="{
    short: 1,
    longer:  2
  }" />
  <div @click="const { a:b } = $event" />
</template>

<script setup lang="ts">
const o = {a:1}
console.log(o)
</script>
