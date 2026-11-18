<script setup lang="ts">
interface P {
  key: string
  'ref': number
  slotScope?: string
}
defineProps<P>()
</script>
