<script lang="ts">
export default {
  props: {
    a: String,
    b: { type: Number },
    c: { type: Number, required: true },
    d: { type: Number, default: 1 },
    e: Boolean,
    f: [Boolean],
    g: { type: Boolean },
    h: Foo(),
    ['i' + 'j']: String,
  },
}
declare function Foo(): any
</script>
