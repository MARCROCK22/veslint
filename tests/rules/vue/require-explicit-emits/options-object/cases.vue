<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  emits: { bar: null },
  setup(props, context) { context.emit('ctx') },
})
</script>
