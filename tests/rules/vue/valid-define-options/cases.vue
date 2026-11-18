<script setup lang="ts">
const name = 'Foo'
const computedName = name.toUpperCase()
defineOptions<{ a: 1 }>({ name, inheritAttrs: computedName === 'x', props: {}, emits: [] })
defineOptions()
</script>
