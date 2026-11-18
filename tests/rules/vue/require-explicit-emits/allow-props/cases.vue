<template>
  <button @click="$emit('foo')" />
  <button @click="$emit('bar')" />
</template>
<script setup lang="ts">
defineProps<{ onFoo: () => void }>()
defineEmits<{ (e: 'baz'): void }>()
</script>
