<script setup lang="ts">
import { ref } from 'vue'
type T = { a: string }
const count = ref(0)
// emits
const emit = defineEmits(['change'])
/** props */
const props = defineProps<T>()
defineOptions({ name: 'X' })
</script>
