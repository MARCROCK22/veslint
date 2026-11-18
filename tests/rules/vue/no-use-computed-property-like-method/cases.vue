<template>
  <div>
    {{ count() }} {{ fn() }} {{ maybe() }} {{ list() }} {{ method() }}
    <button @click="label()">{{ label }}</button>
    <span v-for="x in items" :key="x">{{ x() }}</span>
  </div>
</template>
<script lang="ts">
import { defineComponent } from 'vue'
const constant = 1
let reassigned: unknown = 'a'
reassigned = 2
export default defineComponent({
  props: {
    propA: String,
    propB: { type: [Number, Boolean] },
    propC: Function,
    propD: { type: Object as () => object },
  },
  data() {
    return { items: [1, 2], dataFn: () => 1, dataNum: 1 }
  },
  computed: {
    count(): number { return 1 },
    fn(): () => number { return () => 1 },
    maybe(): unknown { return this.propC },
    list(): number[] { return [constant] },
    label: { get(): string { return `a${constant}` }, set(v: string) { void v } },
    fromProp(): string | undefined { return this.propA },
    fromData(): number { return this.dataNum },
    fromDataFn(): () => number { return this.dataFn },
    fromMethod(): number { return this.method() },
    fromCond(): number { return constant ? 1 : 2 },
    fromVar(): unknown { return reassigned },
    arrow: (): number => 3,
    fromOther(): number { return this.count },
  },
  methods: {
    method(): number { return 1 },
    use() {
      this.count()
      this.fn()
      this.maybe()
      this.label()
      this.fromProp()
      this.fromData()
      this.fromDataFn()
      this.fromMethod()
      this.fromCond()
      this.fromVar()
      this.arrow()
      this.fromOther()
      this.propA()
      const self = this
      self.count()
      this?.count()
      this.count?.()
    },
  },
})
</script>
