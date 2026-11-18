<template>
  <div ref="setupRef">{{ a }} {{ c1 }} {{ m1() }} {{ s1 }} {{ $props.p3 }}</div>
</template>
<script lang="ts">
// @ts-nocheck
import { mapState, mapActions } from 'vuex'
export default {
  props: ['p1', 'p2', 'p3'],
  inject: ['i1', 'i2'],
  data() {
    return { a: 1, b: 2 }
  },
  asyncData() {
    return { ad: 1 }
  },
  computed: {
    c1() { return this.p1 },
    c2: { get() { return 1 }, set(v) { this.b = v } },
    c3: (vm) => vm.i1,
    ...mapState(['stateA', 'stateB']),
  },
  methods: {
    m1() { return this.c3 },
    m2() {},
    ...mapActions({ act1: 'x', act2: 'y' }),
  },
  watch: {
    c2() {},
    'a.b.c': 'm2',
    stateA: { handler: 'act1' },
  },
  expose: ['c1'],
  setup() {
    const setupRef = null
    return { s1: 1, s2: 2, setupRef }
  },
}
</script>
