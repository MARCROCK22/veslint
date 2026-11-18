<template>
  <div v-if="a" v-bind="$attrs" />
  <div v-else-if="b" />
  <div v-else v-bind="$attrs" />
</template>
<script setup lang="ts">
const a = 1, b = 2
</script>
