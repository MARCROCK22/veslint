<template>
  <div @click="({}) => 1" />
  <div @click="([]) => 1" />
  <div @click="const {} = $event" />
  <div @click="const [] = $event" />
  <div @click="({ a: {} }) => a" />
  <div @click="({ a = {} }) => a" />
  <Comp v-slot="{}">x</Comp>
</template>

<script setup lang="ts">
const {} = { a: 1 }
</script>
