<script lang="ts">
export default {}
</script>
<script setup lang="ts">
import { ref } from 'vue'
const props = withDefaults(defineProps<{ a?: string }>(), { a: 'x' })
const emit = defineEmits<{ (e: 'x'): void }>()
const r = ref(props.a)
</script>
