<template>
  <button @click="$emit('fromTemplate')" />
  <button @click="emit('viaVariable')" />
</template>
<script setup lang="ts">
const emit = defineEmits(['fromTemplate', 'viaVariable', 'fromScript', 'unused', ''])
emit('fromScript')
const model = defineModel('value')
defineModel('other')
</script>
<script lang="ts">
export default {
  emits: ['update:value', 'update:other']
}
</script>
