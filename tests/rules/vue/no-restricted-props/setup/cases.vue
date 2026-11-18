<script setup lang="ts">
const { foo = 'x', qux } = withDefaults(defineProps<{ foo?: string; qux?: number; other?: string }>(), {
  foo: 'y',
  qux: 1,
})
</script>
