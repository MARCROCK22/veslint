<template>
  <button @click="$emit('foo')" />
</template>
<script lang="ts">
export default {
  emits: ['bar', `baz`],
  methods: { m() { this.$emit('qux'); this?.$emit('opt') } },
  setup(props, { emit }) { emit('fromSetup') },
}
</script>
