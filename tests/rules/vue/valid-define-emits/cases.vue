<script setup lang="ts">
import { other } from './other'
const def = { a: String }
const local = 1
defineEmits<{ a: string }>({ a: String })
defineEmits({ ...def, b: local, c: other, [local]: Number })
</script>
