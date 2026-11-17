<script setup lang="ts">
const props = defineProps<{ title: string; count?: number }>()
const emit = defineEmits(['close'])
let local = props.title
function close() {
  emit('close')
}
</script>

<template>
  <button @click="close">{{ local }}</button>
</template>
