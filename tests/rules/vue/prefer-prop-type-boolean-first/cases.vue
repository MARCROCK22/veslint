<script lang="ts">
export default {
  props: {
    a: [String, Boolean],
    b: { type: [Number, Boolean, String] },
    c: [Boolean, String],
    d: { type: Boolean },
    e: [String, , Boolean, ...rest],
  },
}
declare const rest: any[]
</script>
