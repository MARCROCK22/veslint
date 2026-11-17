<script setup lang="ts">
defineProps({ a: String })
const { b } = defineProps<{ b: string }>()
</script>
