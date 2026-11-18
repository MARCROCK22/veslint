<script setup lang="ts">
import { ref } from 'vue'
import type { foo } from './x'
const props = defineProps<{ foo: string; bar: number; baz: boolean; qux: string; fn: string }>()
const bar = ref(1)
function baz() {}
type qux = string
class fn {}
</script>
