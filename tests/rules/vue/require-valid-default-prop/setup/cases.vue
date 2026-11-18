<script setup lang="ts">
const flag = true
withDefaults(defineProps<{ a?: string; b?: number[]; c?: typeof flag; d?: Record<string, number> }>(), {
  a: 1,
  b: [],
  c: 'x',
  d: () => 1,
})
</script>
