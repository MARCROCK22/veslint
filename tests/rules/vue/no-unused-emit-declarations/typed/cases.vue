<template>
  <button @click="emit('used', 'x', 1)" />
</template>
<script setup lang="ts">
import type { Emits } from './types'
const emit = defineEmits<Emits>()
</script>
