<script setup lang="ts">
import { watch } from 'vue'
const props = defineProps<{ a: string; b: { c: number } }>()
const a = props.a
const { b } = props
watch(props.a, () => {})
const { c } = withDefaults(defineProps<{ c?: number }>(), { c: 1 })
const d = c
</script>
