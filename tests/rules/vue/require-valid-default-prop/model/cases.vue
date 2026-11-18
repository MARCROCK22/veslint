<script setup lang="ts">
const a = defineModel<string>({ default: 1 })
const b = defineModel('b', { type: Number, default: 'x' })
const c = defineModel('c', { type: Array, default() { return 'x' } })
</script>
