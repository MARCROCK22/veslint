<script setup lang="ts">
interface Props { a: string }
const emit = defineEmits(['change']); const props = defineProps<Props>()
const x = 1
</script>
