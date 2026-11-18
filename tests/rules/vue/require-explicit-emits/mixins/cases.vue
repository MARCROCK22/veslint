<template>
  <button @click="$emit('foo')" />
</template>
<script lang="ts">
export default { mixins: [], emits: ['bar'], methods: { m() { this.$emit('x') } } }
</script>
