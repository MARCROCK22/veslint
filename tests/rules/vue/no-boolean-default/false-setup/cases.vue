<script setup lang="ts">
const flag = true
type Flag = boolean
withDefaults(defineProps<{ a?: boolean; b?: Flag; c?: typeof flag; d?: boolean | string; e?: boolean }>(), {
  a: true,
  b: false,
  c: true,
  d: true,
})
</script>
