<template>
  <div>{{ state.used }} {{ state.nested.x }} {{ other }}</div>
</template>
<script lang="ts">
// @ts-nocheck
const shared = { s1: 1, s2: 2 }
export default {
  data() {
    return {
      state: { used: 1, unused: 2, nested: { x: 1, y: 2 } },
      other: shared,
      fn: { a: 1 },
    }
  },
  methods: {
    m() { useIt(this.fn); console.log(this.other.s1) },
  },
}
</script>
