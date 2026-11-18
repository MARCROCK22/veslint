<template>
  <button @click="$emit('bad')" />
  <button @click="$emit('ok')" />
  <button @click="$emit('regex-one')" />
  <button @click="emit('bad')" />
</template>
<script setup lang="ts">
const emit = defineEmits(['bad'])
emit('bad')
</script>
<script lang="ts">
export default {
  methods: {
    m() {
      this.$emit('bad')
      this.$emit("quoted")
      this.$emit(`tpl`)
    }
  },
  setup(props, { emit }) {
    emit('regex-two')
  }
}
</script>
