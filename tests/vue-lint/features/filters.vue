<script setup lang="ts">
const msg = 'hello'
const upper = (text: string): string => text.toUpperCase()
</script>

<template>
  <p>{{ msg | upper }}</p>
  <p :title="msg | upper">{{ msg }}</p>
</template>
