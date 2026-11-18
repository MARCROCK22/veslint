<template>
  <p>{{ console.log(1) }}</p>
  <div @click="console.error('x')" />
  <div :a="console['warn']" />
  <div :a="Console.log" />
  <div @click="() => console.info" />
</template>

<script setup lang="ts">
console.log('script')
</script>
