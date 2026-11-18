<script setup lang="ts">
declare function definePage(o: object): void
const a = 1
defineModel('a')
definePage({ x: 1 })
defineModel('b')
defineSlots<{ default(): any }>()
</script>
