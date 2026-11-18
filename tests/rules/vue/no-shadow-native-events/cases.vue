<template>
  <button @click="$emit('click')" />
  <button @click="$emit('CLICK')" />
  <button @click="emit('focus')" />
  <button @click="$emit('custom')" />
</template>
<script setup lang="ts">
const emit = defineEmits(['click', 'Input', 'custom'])
emit('keydown')
emit?.('keyup')
</script>
<script lang="ts">
export default {
  emits: { submit: null, ['change']: null },
  methods: { m() { this.$emit('scroll'); other.$emit('wheel') } },
  setup(props, { emit }) { emit('blur') },
}
</script>
