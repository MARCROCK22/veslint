<script setup lang="ts">
defineProps({ a: {} })
const m = defineModel()
const n = defineModel('n', { required: true })
const o = defineModel<string>('o')
const p = defineModel('p', { type: String })
</script>
