<script lang="ts">
export default {
  props: {
    a: { type: Boolean, default: true },
    b: { type: Boolean, default: false },
    c: Boolean,
    d: { type: String, default: 'x' },
    e: { type: Boolean as any, default: () => true },
  },
}
</script>
