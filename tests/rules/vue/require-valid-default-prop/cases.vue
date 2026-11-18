<script lang="ts">
export default {
  props: {
    a: { type: String, default: 1 },
    b: { type: Number, default: () => 'x' },
    c: { type: Object, default: {} },
    d: { type: Array, default() { if (Math.random()) return 'x'; return [] } },
    e: { type: [String, Number], default: true },
    f: { type: Function, default: 1 },
    g: { type: String, default: `ok` },
    h: { type: BigInt, default: 1n },
    i: { type: Boolean, default: null },
    j: { type: Object, default: () => ({}) },
  },
}
</script>
