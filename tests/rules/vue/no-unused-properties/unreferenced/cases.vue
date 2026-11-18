<template>
  <div />
</template>
<script lang="ts">
// @ts-nocheck
export default {
  props: ['a', 'b', 'c'],
  computed: {
    x() { return this[name] },
    y() { return this.a },
  },
  methods: {
    m() { return this.b },
    n() { const self = this; return self },
  },
}
</script>
