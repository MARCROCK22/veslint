<script setup lang="ts">
const emit = defineEmits<{
  (e: 'a', id: number): void
  b: [x: string]
  c(): void
}>()
</script>
