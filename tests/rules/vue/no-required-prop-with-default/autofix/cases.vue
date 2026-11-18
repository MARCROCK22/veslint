<script lang="ts">
export default {
  props: {
    a: { type: String, required: true, default: 'x' },
    b: { type: String, required: false, default: 'x' },
    c: { type: Number, required: 1, default: 1 },
    d: { type: Number, required: true },
  },
}
</script>
