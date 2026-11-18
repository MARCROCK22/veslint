<script setup lang="ts">
import { other } from './other'
const def = { a: String }
const local = 1
defineProps<{ a: string }>({ a: String })
defineProps({ ...def, b: local, c: other, [local]: Number })
</script>
