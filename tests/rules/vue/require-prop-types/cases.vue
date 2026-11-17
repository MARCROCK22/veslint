<script lang="ts">
export default {
  props: {
    a: {},
    b: { type: [] },
    c: { validator: (v: any) => true },
    d: [],
    e: () => {},
    f: String,
    g: x,
    ...rest,
  },
}
declare const x: any
declare const rest: any
</script>
