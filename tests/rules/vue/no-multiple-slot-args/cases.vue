<script lang="ts">
export default {
  render(h: any) {
    this.$slots.default(a, b)
    this.$scopedSlots.foo(...args)
    this.$slots.bar?.(a, b, c)
    const s = this.$scopedSlots.baz
    s(a, b)
    let t
    t = this.$slots.qux
    t(a, b)
    this.$slots.ok(a)
    foo(this.$slots.x, b)
    return h('div')
  },
}
declare const a: any, b: any, c: any, args: any[]
declare function foo(...x: any[]): void
</script>
