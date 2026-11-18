<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  props: {
    a: Object,
    b: Array,
    c: [Object, String, Array],
    d: { type: Object, required: true },
    e: { type: [Array, Number] },
    f: Object as any,
    g: String,
  },
})
</script>
