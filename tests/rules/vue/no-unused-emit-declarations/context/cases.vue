<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  emits: ['a', 'b', 'c', 'd'],
  setup(props, context) {
    context.emit('a')
    context?.emit('b')
    other.emit('c')
    helper({ fn: context.emit })
  }
})
</script>
