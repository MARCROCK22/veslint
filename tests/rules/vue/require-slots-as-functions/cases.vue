<script lang="ts">
export default {
  render(h: any) {
    const a = this.$slots.default.x
    const [b] = this.$slots.foo
    const c = [...this.$slots.bar]
    const d = [this.$slots.baz]
    const e = this.$slots.qux
    e.length
    e.other
    let f
    f = this.$slots.quux
    ;[f]
    ;(this.$slots?.chain).x
    this.$slots.ok()
    return h('div')
  },
}
</script>
