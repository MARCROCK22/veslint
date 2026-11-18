<template>
  <button @click="$emit('declared')" />
  <button @click="$emit('missing')" />
  <button @click="emit('viaVar')" />
  <button @click="$emit('update:value')" />
</template>
<script setup lang="ts">
const emit = defineEmits(['declared'])
emit('scriptMissing')
defineModel('value')
</script>
