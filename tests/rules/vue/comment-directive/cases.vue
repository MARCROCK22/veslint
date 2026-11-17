<!-- eslint-disable -->
<template>
  <!-- eslint-disable vue/no-v-html -->
  <div v-html="a"></div>
  <!-- eslint-enable -->
  <div v-text="a"></div> <!-- eslint-disable-line -->
  <!-- eslint-disable-next-line vue/no-v-text, vue/no-v-html -- reason -->
  <div v-html="b"></div>
  <p>{{ a /* eslint-disable-line */ }}</p>
</template>
<script setup lang="ts">
const a = 1
const b = 2
</script>
