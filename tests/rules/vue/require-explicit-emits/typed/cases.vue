<template>
  <button @click="$emit('a')" />
  <button @click="$emit('c')" />
</template>
<script setup lang="ts">
import type { Emits } from './types'
defineEmits<Emits>()
</script>
