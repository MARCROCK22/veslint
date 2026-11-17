<script setup lang="ts">
const a = defineModel({ default: 1 })
const b = defineModel('b', { type: String, default: 'x' })
const c = defineModel<string>('c', { required: true })
const d = defineModel('d', { default: () => [] } as any)
const e = defineModel({ ...{ default: 1 } })
defineModel('f', { 'default': 2 })
const g = foo(defineModel({ default: 3 }))
</script>
