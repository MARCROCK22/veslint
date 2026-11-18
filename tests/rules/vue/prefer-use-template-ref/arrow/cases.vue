<template>
  <div ref="a" />
  <div ref="b" />
</template>
<script lang="ts">
import { defineComponent, ref } from 'vue'
export default defineComponent({
  setup: () => {
    const a = ref()
    return { a }
  }
})
const other = defineComponent({ setup: () => ({ b: ref() }) })
</script>
