<script setup lang="ts">
const { a = true, b = false, c = 1 } = defineProps<{ a?: boolean; b?: boolean; c?: number }>()
</script>
