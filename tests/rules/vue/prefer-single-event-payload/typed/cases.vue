<script setup lang="ts">
import type { Emits } from './types'
defineEmits<Emits>()
defineEmits<(e: 'fn', a: number, b: number) => void>()
</script>
