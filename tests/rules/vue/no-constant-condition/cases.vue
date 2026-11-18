<template>
  <div v-if="true" />
  <div v-else-if="{}" />
  <div v-show="1 + 1" />
  <p>{{ true ? a : b }}</p>
  <div @click="if (0) a()" />
  <div @click="while (true) { a() }" />
  <div v-if="a" />
  <div v-other="true" />
</template>

<script setup lang="ts">
if (true) console.log(1)
</script>
