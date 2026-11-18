<template>
  <div v-for="allowed in 3" :key="allowed">
    <div v-for="allowed in 3" :key="allowed" />
    <div v-for="m in 3" :key="m" />
    <div v-for="p in 3" :key="p" />
  </div>
</template>
<script lang="ts">
export default {
  props: ['p'],
  methods: { m() {} },
  setup() { return { s: 1 } },
}
const allowed = 1
</script>
