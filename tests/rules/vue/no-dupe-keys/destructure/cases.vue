<script setup lang="ts">
const { a, b: bb = 'x' } = defineProps<{ a: string; b?: string }>()
const b = 1
</script>
