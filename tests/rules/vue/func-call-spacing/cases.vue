<template>
  <p>{{ fn (a) }}</p>
  <div @click="fn
    ()" />
  <div :a="fn(b)" />
  <div :[fn (a)]="x" />
</template>

<script setup lang="ts">
console.log (1)
</script>

<style>
.a {
  width: v-bind('fn ()');
}
</style>
