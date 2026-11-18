<template>
  <div>{{ a.b.c }} {{ a.x }} {{ cfoo }} {{ sa }} {{ act1() }} {{ fromRefs }} {{ notDefined }}</div>
</template>
<script lang="ts">
// @ts-nocheck
import { reactive, toRefs } from 'vue'
import { mapState, mapActions } from 'vuex'
export default {
  props: ['p'],
  data(vm) {
    console.log(vm.p, vm.cfoo)
    return { a: { b: { c: 1 } }, d: 1 }
  },
  computed: {
    cfoo() { return this.d + this.zzz },
    cbar: (vm) => vm.yyy,
    cget: { get: (vm) => vm.xxx },
    ...mapState(['sa']),
  },
  methods: {
    ...mapActions({ act1: 'x' }),
    m() {
      this.missingMethod()
      this.missingMethod()
      this.$refs.x
      const self = this
      self.viaSelf
    },
  },
  watch: {
    'a.b.q'() {},
    d: 'unknownHandler',
  },
  expose: ['notExposed'],
  setup(props) {
    const state = reactive({ fromRefs: 1 })
    console.log(props.p, props.notAProp)
    return { ...toRefs(state) }
  },
}
</script>
