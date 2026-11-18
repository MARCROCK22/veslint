<script setup lang="ts">
import { ref, computed, toRefs, reactive, type Ref } from 'vue'
const count = ref(0)
const doubled = computed(() => count.value * 2)
const { a, b: bb } = toRefs(reactive({ a: 1, b: 2 }))
declare const typed: Ref<number>
let other = ref('x')
const emit = defineEmits<{ (e: 'change', v: number): void }>()
if (count) {}
count++
const sum = count + doubled
const neg = -count
const s = `${count}`
const t = count ? 1 : 2
const u = count || 1
const v = count.foo
const w = count.value
other = 'y'
const x = a + bb
const y = typed + 1
emit('change', count)
switch (count) {}
other += 'z'
</script>
