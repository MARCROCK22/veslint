<template>
  <div v-for="s in 3" :key="s" />
  <div v-for="top in 3" :key="top" />
  <div v-for="asyncThing in 3" :key="asyncThing" />
</template>
<script lang="ts">
const top = 1
export default {
  setup() { return { s: 1 } },
  asyncData() { return { asyncThing: 1 } },
}
</script>
