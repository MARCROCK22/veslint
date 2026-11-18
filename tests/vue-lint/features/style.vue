<script setup lang="ts">
const color = 'red'
const size = '1px'
</script>

<template>
  <p class="a">{{ size }}</p>
</template>

<style>
.a {
  color: v-bind(color);
}
</style>
