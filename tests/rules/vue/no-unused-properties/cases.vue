<template>
  <div :class="used" @click="$emit('x')">{{ props.shown }} {{ count }}</div>
</template>
<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ used: string; shown: number; hidden: boolean; inScript: string; forbidden?: never }>()
const count = computed(() => props.inScript.length)
const model = defineModel<string>('title')
defineModel<number>('unusedModel')
defineModel()
void model
</script>
<style>
.a { color: v-bind(styleOnly); }
</style>
