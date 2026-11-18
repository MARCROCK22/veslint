<script setup lang="ts">
defineProps({ a: String })
defineEmits(['x'])
defineExpose({ y: 1 })
const z = 2
</script>
