<script setup lang="ts">
import { ref, defineProps, defineEmits } from 'vue'
import { defineModel } from '@vue/runtime-core'
import { withDefaults as wd } from '@vue/runtime-dom'
import { defineSlots } from 'other'
import type { defineExpose } from 'vue'
const props = defineProps<{ a: string }>()
</script>
