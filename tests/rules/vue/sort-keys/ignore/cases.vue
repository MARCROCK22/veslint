<script lang="ts">
export default {
  props: {
    z: String,
    a: { type: String, default: 'a', required: false },
  },
  watch: {
    z: { handler() {}, deep: true },
  },
}
</script>
