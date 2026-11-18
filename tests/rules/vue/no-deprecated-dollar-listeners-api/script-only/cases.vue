<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  computed: {
    x(): unknown { return this.$listeners }
  }
})
</script>
