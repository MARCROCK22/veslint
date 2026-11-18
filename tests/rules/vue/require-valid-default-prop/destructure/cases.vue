<script setup lang="ts">
const { a = 1, b = [], c = () => 1 } = defineProps<{ a?: string; b?: number[]; c?: string }>()
</script>
