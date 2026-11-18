<template>
  <div v-bind="$scopedSlots" @click="$scopedSlots.click()">
    <child v-for="$scopedSlots in list" :x="$scopedSlots" />
    {{ $scopedSlots }}
  </div>
</template>
<script lang="ts">
export default {
  mounted() {
    const vm = this
    console.log(this.$scopedSlots, vm.$scopedSlots, this?.$scopedSlots, this['$scopedSlots'], other.$scopedSlots)
  },
  data() {
    return { a: this.$scopedSlots }
  }
}
const notVue = { m() { return this.$scopedSlots } }
</script>
<script setup lang="ts">
const s = $scopedSlots
</script>
