<script setup lang="ts">
interface Props {
  a: string
  b?: string
  'c-d': number
  get e(): string
  f(): void
}
withDefaults(defineProps<Props>(), {
  a: 'x',
  b: 'y',
  'c-d': 1,
  e: 'z',
  f: () => {},
})
</script>
