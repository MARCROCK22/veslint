<template>
  <div ref="input" />
  <div ref="other" />
  <div ref="typeOnly" />
  <div v-for="x in 3" ref="loop" @click="$refs" />
</template>
<script setup lang="ts">
import { ref } from 'vue'
const input = ref()
type typeOnly = string
</script>
