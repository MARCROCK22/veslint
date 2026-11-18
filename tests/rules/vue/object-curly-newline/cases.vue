<template>
  <div :a="{
    a: 1}" />
  <div :a="{a: 1,
    b: 2
  }" />
  <div @click="const {
    x} = $event" />
  <div :a="{a: 1}" />
</template>

<script setup lang="ts">
const o = {
  a: 1}
console.log(o)
</script>
