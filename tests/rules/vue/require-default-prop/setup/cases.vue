<script setup lang="ts">
const flag = true
withDefaults(defineProps<{ a?: string; b?: string; c: string; d?: boolean; e?: typeof flag; f?: number | undefined }>(), {
  a: 'x',
})
</script>
