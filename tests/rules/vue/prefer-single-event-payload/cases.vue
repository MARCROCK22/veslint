<template>
  <button @click="$emit('one', a)" />
  <button @click="$emit('two', a, b)" />
  <button @click="emit('three', a, b, c)" />
  <button @click="$emit(name, a, b)" />
</template>
<script setup lang="ts">
const a = 1, b = 2, c = 3, name = 'x'
const emit = defineEmits<{
  (e: 'two', x: number, y: number): void
  (e: 'one', x: number): void
  three: [x: number, y: number, z: number]
  method(x: number, y: number): void
  single: [x: number]
}>()
emit('two', a, b)
emit?.('two', a, b)
</script>
<script lang="ts">
export default {
  emits: { obj: (x: number, y: number) => true, fn: function (x: number) { return true }, plain: null },
  methods: { m() { this.$emit('obj', 1, 2); other.$emit('any', 1, 2) } },
  setup(props, ctx) { ctx.emit('ctx', 1, 2) },
}
</script>
