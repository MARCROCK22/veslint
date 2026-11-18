<script setup lang="ts">
import { computed } from 'vue'
declare const api: { get(): Promise<number> }
const a = computed(async () => 1)
const b = computed(() => api.get().finally(() => {}))
const c = computed(() => {
  setInterval(() => {}, 10)
  return 1
})
</script>
