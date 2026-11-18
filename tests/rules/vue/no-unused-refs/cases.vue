<template>
  <div ref="used" />
  <div ref="unused" />
  <div ref="inTemplate" @click="$refs.inTemplate.focus()" />
  <div ref="chained" />
  <div ref="destructured" />
  <div ref="byHook" />
  <div ref="fromSetup" />
  <div :ref="dynamic" />
  <div ref="" />
</template>
<script lang="ts">
import { useTemplateRef } from 'vue'
export default {
  setup() {
    useTemplateRef('byHook')
    return { fromSetup: 1 }
  },
  mounted() {
    this.$refs.used
    this?.$refs?.chained
    const { destructured } = this.$refs
  }
}
</script>
