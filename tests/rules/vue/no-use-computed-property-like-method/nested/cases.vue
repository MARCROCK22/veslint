<template>
  <div>{{ inner() }} {{ outer() }}</div>
</template>
<script lang="ts">
// @ts-nocheck
import Vue from 'vue'
export default {
  computed: {
    outer() { return 'a' },
  },
  methods: {
    m() {
      this.outer()
      Vue.component('x', {
        computed: { inner() { return 1 } },
        methods: { n() { this.inner(); this.outer() } },
      })
    },
  },
}
</script>
