<template>
  <div ref="a" />
  <div ref="b" />
  <div ref="c" />
</template>
<script lang="ts">
import { ref, shallowRef } from 'vue'
export default {
  setup() {
    const a = ref()
    const b = shallowRef()
    if (true) { const c = ref() }
    return { a, b }
  }
}
const c = ref()
</script>
