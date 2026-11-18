<script setup lang="ts">
const { a = 'x', b, c } = defineProps<{ a?: string; b?: string; c: string }>()
</script>
