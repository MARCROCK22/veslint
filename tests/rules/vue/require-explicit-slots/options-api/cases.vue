<template>
  <slot name="a" />
  <slot name="b" />
</template>
<script lang="ts">
import { defineComponent, type SlotsType } from 'vue'
export default defineComponent({
  slots: Object as SlotsType<{
    a: { x: number }
    a(): void
    1: string
  }>,
})
</script>
