<template>
  <p>{{ [ 1, 2 ] }}</p>
  <div :a="[ a ]" :b="[b]" />
  <div @click="const [ x ] = $event" />
  <div :[[ x ]]="y" />
</template>

<script setup lang="ts">
const list = [ 1, 2 ]
console.log(list)
</script>
