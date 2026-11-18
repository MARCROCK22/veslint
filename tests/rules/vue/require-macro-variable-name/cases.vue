<script setup lang="ts">
import { useSlots, useAttrs } from 'vue'
const p = defineProps<{ a: string }>()
const e = defineEmits(['a'])
const s = defineSlots()
const sl = useSlots()
const at = useAttrs()
const w: any = withDefaults(defineProps<{ b?: string }>(), {})
const { c } = defineProps({ c: String })
function f() {
  const inner = useAttrs()
}
</script>
