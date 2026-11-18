import { defineComponent, computed, ref } from 'vue'
export default defineComponent({
  setup() {
    const n = ref(0)
    const m = computed(() => n.value++)
    return { m }
  },
})
