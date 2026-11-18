<template>
  <div :a="[a
    , b]" />
  <div :a="{x: 1
    , y: 2}" />
  <div @click="fn(a
    , b)" />
  <Comp v-slot="a
    , b">x</Comp>
  <div @click="const a = 1
    , b = 2" />
</template>

<script setup lang="ts">
const list = [1
  , 2]
console.log(list)
</script>
