<script setup lang="ts">
import { computed, ref, reactive } from 'vue'
const count = ref(0)
const state = reactive({ list: [] as number[] })
const a = computed(() => count.value++)
const b = computed(() => {
  state.list.push(1)
  const local = { x: 1 }
  local.x = 2
  return count.value
})
const c = computed({ get: () => { count.value = 1; return 1 }, set: (v: number) => { count.value = v } })
</script>
