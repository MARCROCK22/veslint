<script setup lang="ts">
import { ref, computed, toRefs, reactive, watch } from 'vue'
const count = ref(0)
const plain = count.value
const { value } = count
const { a } = toRefs(reactive({ a: 1 }))
const av = a.value
count.value++
count.value = 2
const later = computed(() => count.value)
;(() => {
  const inner = count.value
})()
function f() {
  return count.value
}
const direct = ref(1).value
watch(count, () => {})
</script>
