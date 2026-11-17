<template>
  <p>{{ `${ a }` }}</p>
  <div :a="`x${b}y`" />
  <div :a="`x${ b}y${c }`" />
</template>

<script setup lang="ts">
const t = `${ 1 }`
console.log(t)
</script>

<style>
.a {
  content: v-bind("`${ a }`");
}
</style>
