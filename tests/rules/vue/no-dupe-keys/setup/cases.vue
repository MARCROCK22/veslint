<script setup lang="ts">
import { toRef, toRefs, computed } from 'vue'
import { e } from './other'
const props = defineProps<{ a: string; b: string; c: string; d: string; e: string; f: string; g: string }>()
const a = computed(() => props.a)
const b = toRef(props, 'b')
const c = props.d
function d() {}
const { f, g: renamed } = toRefs(props)
const model = defineModel<string>('a')
const other = defineModel<number>('other')
const other2 = defineModel<number>('h')
const h = 1
</script>
