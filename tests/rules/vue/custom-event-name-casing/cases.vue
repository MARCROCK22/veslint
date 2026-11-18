<template>
  <button @click="$emit('fooBar')" />
  <button @click="$emit('foo-bar')" />
  <button @click="emit('my-event')" />
  <button @click="emit2('other-event')" />
  <button @click="$emit('update:modelValue')" />
  <button @click="$emit('update:model-value')" />
</template>
<script setup lang="ts">
const emit = defineEmits(['my-event'])
emit('setup-event')
emit('setupEvent')
emit?.('opt-event')
</script>
<script lang="ts">
export default {
  methods: {
    m() {
      this.$emit('options-event')
      this?.$emit('optionsEvent')
      other.$emit('any-object')
      this.$emit(`tpl-event`)
      this.$emit(name)
    }
  },
  setup(props, { emit }) {
    emit('setup-ctx-event')
  }
}
</script>
